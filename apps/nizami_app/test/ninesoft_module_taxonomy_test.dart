import 'package:flutter_test/flutter_test.dart';
import 'package:nizami/src/features/navigation/ninesoft_module_taxonomy.dart';

void main() {
  test('navigation taxonomy follows the six approved business groups', () {
    expect(
      NineSoftModuleTaxonomy.keysFor(
        NineSoftModuleGroup.salesAndCollection,
      ),
      ['sales', 'sales.returns', 'customers'],
    );
    expect(
      NineSoftModuleTaxonomy.keysFor(
        NineSoftModuleGroup.purchasesAndPayments,
      ),
      ['purchases', 'suppliers'],
    );
    expect(
      NineSoftModuleTaxonomy.keysFor(NineSoftModuleGroup.inventory),
      ['products', 'inventory'],
    );
    expect(
      NineSoftModuleTaxonomy.keysFor(NineSoftModuleGroup.accounting),
      ['cashbox', 'debts', 'accounts', 'wasl'],
    );
    expect(
      NineSoftModuleTaxonomy.keysFor(NineSoftModuleGroup.reports),
      ['reports'],
    );
    expect(
      NineSoftModuleTaxonomy.keysFor(NineSoftModuleGroup.administration),
      ['payroll', 'users', 'branches', 'backup', 'whatsapp', 'settings'],
    );
  });

  test('child modules inherit their business group from their root', () {
    expect(
      NineSoftModuleTaxonomy.groupFor('sales.returns'),
      NineSoftModuleGroup.salesAndCollection,
    );
    expect(
      NineSoftModuleTaxonomy.groupFor('purchases.invoices'),
      NineSoftModuleGroup.purchasesAndPayments,
    );
    expect(
      NineSoftModuleTaxonomy.groupFor('accounts.journals'),
      NineSoftModuleGroup.accounting,
    );
    expect(
      NineSoftModuleTaxonomy.groupFor('reports.profit-loss'),
      NineSoftModuleGroup.reports,
    );
  });

  test('labels match the implementation brief wording', () {
    expect(
      NineSoftModuleTaxonomy.labelFor(
        NineSoftModuleGroup.salesAndCollection,
      ),
      'البيع والتحصيل',
    );
    expect(
      NineSoftModuleTaxonomy.labelFor(NineSoftModuleGroup.accounting),
      'المحاسبة',
    );
    expect(
      NineSoftModuleTaxonomy.labelFor(NineSoftModuleGroup.administration),
      'الإدارة',
    );
  });
}
