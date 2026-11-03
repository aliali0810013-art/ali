import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../domain/accounting/money.dart';
import '../../domain/invoices/sales_posting_service.dart';
import '../local/local_schema.dart';

class InvoiceLineDraft {
  const InvoiceLineDraft({
    this.productId,
    required this.name,
    required this.kind,
    required this.quantityMilli,
    required this.unitPriceMinor,
    required this.purchaseCostMinor,
  });
  final String? productId;
  final String name;
  final String kind;
  final int quantityMilli;
  final int unitPriceMinor;
  final int purchaseCostMinor;
}

class SalesInvoiceDraft {
  const SalesInvoiceDraft({
    required this.tenantId,
    required this.branchId,
    required this.branchCode,
    required this.deviceId,
    required this.creatorUserId,
    required this.creatorDisplayName,
    required this.localOperationId,
    required this.paidMinor,
    required this.occurredAt,
    required this.lines,
  });
  final String tenantId;
  final String branchId;
  final String branchCode;
  final String deviceId;
  final String creatorUserId;
  final String creatorDisplayName;
  final String localOperationId;
  final int paidMinor;
  final DateTime occurredAt;
  final List<InvoiceLineDraft> lines;
}

class SavedInvoice {
  const SavedInvoice({
    required this.id,
    required this.number,
    required this.wasAlreadySaved,
  });
  final String id;
  final String number;
  final bool wasAlreadySaved;
}

class LocalInvoiceRepository {
  LocalInvoiceRepository(this.database, {Uuid? uuid})
    : uuid = uuid ?? const Uuid();
  final Database database;
  final Uuid uuid;

  void migrate() {
    database.execute('PRAGMA foreign_keys = ON');
    for (final statement in localSchema) {
      database.execute(statement);
    }
  }

  SavedInvoice saveSale(SalesInvoiceDraft draft) {
    if (draft.lines.isEmpty) {
      throw ArgumentError('Invoice requires at least one line');
    }
    final existing = database.select(
      'SELECT id, number FROM invoices WHERE tenant_id = ? AND local_operation_id = ?',
      [draft.tenantId, draft.localOperationId],
    );
    if (existing.isNotEmpty) {
      return SavedInvoice(
        id: existing.first['id'] as String,
        number: existing.first['number'] as String,
        wasAlreadySaved: true,
      );
    }

    database.execute('BEGIN IMMEDIATE');
    try {
      final invoiceId = uuid.v7();
      final number = _nextNumber(draft);
      final now = DateTime.now().toUtc().toIso8601String();
      var total = 0;
      var cost = 0;
      final resolvedLines =
          <({InvoiceLineDraft draft, String productId, int total})>[];

      for (final line in draft.lines) {
        if (line.quantityMilli <= 0 ||
            line.unitPriceMinor < 0 ||
            line.purchaseCostMinor < 0) {
          throw ArgumentError('Invalid line amounts');
        }
        final productId =
            line.productId ?? _findOrCreateProduct(draft.tenantId, line, now);
        final lineTotal = (line.quantityMilli * line.unitPriceMinor) ~/ 1000;
        total += lineTotal;
        cost += (line.quantityMilli * line.purchaseCostMinor) ~/ 1000;
        resolvedLines.add((
          draft: line,
          productId: productId,
          total: lineTotal,
        ));
      }
      if (draft.paidMinor < 0 || draft.paidMinor > total) {
        throw ArgumentError('Invalid paid amount');
      }

      database.execute(
        '''INSERT INTO invoices(id, tenant_id, branch_id, creator_user_id, creator_display_name,
        local_operation_id, number, type, status, total_minor, paid_minor, due_minor, occurred_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'sale', 'posted', ?, ?, ?, ?, ?)''',
        [
          invoiceId,
          draft.tenantId,
          draft.branchId,
          draft.creatorUserId,
          draft.creatorDisplayName,
          draft.localOperationId,
          number,
          total,
          draft.paidMinor,
          total - draft.paidMinor,
          draft.occurredAt.toUtc().toIso8601String(),
          now,
        ],
      );
      for (final line in resolvedLines) {
        database.execute(
          '''INSERT INTO invoice_items(id, tenant_id, invoice_id, product_id, product_name_snapshot,
          quantity_milli, unit_price_minor, line_total_minor) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            uuid.v7(),
            draft.tenantId,
            invoiceId,
            line.productId,
            line.draft.name.trim(),
            line.draft.quantityMilli,
            line.draft.unitPriceMinor,
            line.total,
          ],
        );
      }
      _postJournal(draft, invoiceId, total, cost, now);
      database.execute(
        '''INSERT INTO outbox(id, tenant_id, aggregate_type, aggregate_id, operation, payload_json, occurred_at)
        VALUES (?, ?, 'invoice', ?, 'upsert', ?, ?)''',
        [
          uuid.v7(),
          draft.tenantId,
          invoiceId,
          jsonEncode({
            'invoice_id': invoiceId,
            'local_operation_id': draft.localOperationId,
          }),
          now,
        ],
      );
      database.execute('COMMIT');
      return SavedInvoice(
        id: invoiceId,
        number: number,
        wasAlreadySaved: false,
      );
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  String _nextNumber(SalesInvoiceDraft draft) {
    database.execute(
      '''INSERT OR IGNORE INTO document_counters(tenant_id, branch_id, device_id, document_type, next_value)
      VALUES (?, ?, ?, 'sale', 1)''',
      [draft.tenantId, draft.branchId, draft.deviceId],
    );
    final row = database
        .select(
          '''SELECT next_value FROM document_counters
      WHERE tenant_id = ? AND branch_id = ? AND device_id = ? AND document_type = 'sale' ''',
          [draft.tenantId, draft.branchId, draft.deviceId],
        )
        .single;
    final value = row['next_value'] as int;
    database.execute(
      '''UPDATE document_counters SET next_value = next_value + 1
      WHERE tenant_id = ? AND branch_id = ? AND device_id = ? AND document_type = 'sale' ''',
      [draft.tenantId, draft.branchId, draft.deviceId],
    );
    final day = DateTime.now()
        .toUtc()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    final device = draft.deviceId
        .replaceAll('-', '')
        .substring(0, draft.deviceId.length.clamp(1, 6));
    return 'S-${draft.branchCode}-$day-$device-${value.toString().padLeft(6, '0')}';
  }

  String _findOrCreateProduct(
    String tenantId,
    InvoiceLineDraft line,
    String now,
  ) {
    final normalized = _normalizeName(line.name);
    if (normalized.isEmpty) throw ArgumentError('Product name is required');
    final found = database.select(
      'SELECT id FROM products WHERE tenant_id = ? AND normalized_name = ? AND deleted_at IS NULL',
      [tenantId, normalized],
    );
    if (found.isNotEmpty) return found.single['id'] as String;
    final id = uuid.v7();
    database.execute(
      '''INSERT INTO products(id, tenant_id, normalized_name, name, kind, sale_price_minor,
      purchase_price_minor, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        tenantId,
        normalized,
        line.name.trim(),
        line.kind,
        line.unitPriceMinor,
        line.purchaseCostMinor,
        now,
        now,
      ],
    );
    return id;
  }

  void _postJournal(
    SalesInvoiceDraft draft,
    String invoiceId,
    int total,
    int cost,
    String now,
  ) {
    final entries = const SalesPostingService().post(
      invoiceId: invoiceId,
      total: Money(total),
      paid: Money(draft.paidMinor),
      costOfGoodsSold: Money(cost),
    );
    for (final entry in entries) {
      database.execute(
        '''INSERT INTO journal_entries(id, tenant_id, branch_id, reference_type, reference_id, posted_at)
        VALUES (?, ?, ?, 'sales_invoice', ?, ?)''',
        [entry.id, draft.tenantId, draft.branchId, invoiceId, now],
      );
      for (final line in entry.lines) {
        database.execute(
          '''INSERT INTO journal_lines(tenant_id, entry_id, account_code, debit_minor, credit_minor)
          VALUES (?, ?, ?, ?, ?)''',
          [
            draft.tenantId,
            entry.id,
            line.accountCode,
            line.side.name == 'debit' ? line.amount.minorUnits : 0,
            line.side.name == 'credit' ? line.amount.minorUnits : 0,
          ],
        );
      }
    }
  }

  String _normalizeName(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ');
}
