const localSchemaVersion = 1;

const localSchema = <String>[
  '''
  CREATE TABLE IF NOT EXISTS app_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS document_counters (
    tenant_id TEXT NOT NULL,
    branch_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    document_type TEXT NOT NULL,
    next_value INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (tenant_id, branch_id, device_id, document_type)
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('stock','service')),
    sale_price_minor INTEGER NOT NULL DEFAULT 0,
    purchase_price_minor INTEGER NOT NULL DEFAULT 0,
    unit_name TEXT NOT NULL DEFAULT 'وحدة',
    barcode TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    sync_version INTEGER NOT NULL DEFAULT 0,
    UNIQUE(tenant_id, normalized_name)
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS invoices (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    branch_id TEXT NOT NULL,
    creator_user_id TEXT NOT NULL,
    creator_display_name TEXT NOT NULL,
    local_operation_id TEXT NOT NULL,
    number TEXT NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('sale','purchase','sale_return','purchase_return')),
    status TEXT NOT NULL CHECK(status IN ('posted','voided')),
    total_minor INTEGER NOT NULL,
    paid_minor INTEGER NOT NULL,
    due_minor INTEGER NOT NULL,
    occurred_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    sync_state TEXT NOT NULL DEFAULT 'pending',
    server_version INTEGER,
    UNIQUE(tenant_id, local_operation_id),
    UNIQUE(tenant_id, number)
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS invoice_items (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    invoice_id TEXT NOT NULL REFERENCES invoices(id),
    product_id TEXT NOT NULL REFERENCES products(id),
    product_name_snapshot TEXT NOT NULL,
    quantity_milli INTEGER NOT NULL CHECK(quantity_milli > 0),
    unit_price_minor INTEGER NOT NULL CHECK(unit_price_minor >= 0),
    line_total_minor INTEGER NOT NULL CHECK(line_total_minor >= 0)
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS journal_entries (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    branch_id TEXT NOT NULL,
    reference_type TEXT NOT NULL,
    reference_id TEXT NOT NULL,
    posted_at TEXT NOT NULL,
    reversal_of_id TEXT,
    UNIQUE(tenant_id, reference_type, reference_id, id)
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS journal_lines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id TEXT NOT NULL,
    entry_id TEXT NOT NULL REFERENCES journal_entries(id),
    account_code TEXT NOT NULL,
    debit_minor INTEGER NOT NULL DEFAULT 0,
    credit_minor INTEGER NOT NULL DEFAULT 0,
    CHECK(debit_minor >= 0 AND credit_minor >= 0),
    CHECK((debit_minor = 0) <> (credit_minor = 0))
  ) STRICT
  ''',
  '''
  CREATE TABLE IF NOT EXISTS outbox (
    id TEXT PRIMARY KEY,
    tenant_id TEXT NOT NULL,
    aggregate_type TEXT NOT NULL,
    aggregate_id TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    occurred_at TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    next_attempt_at TEXT,
    delivered_at TEXT,
    UNIQUE(tenant_id, aggregate_type, aggregate_id, operation)
  ) STRICT
  ''',
  'CREATE INDEX IF NOT EXISTS idx_products_tenant_name ON products(tenant_id, normalized_name)',
  'CREATE INDEX IF NOT EXISTS idx_invoices_tenant_date ON invoices(tenant_id, occurred_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_outbox_pending ON outbox(delivered_at, next_attempt_at)',
];
