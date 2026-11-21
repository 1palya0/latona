// Loads the Latona product catalog (spec, section 4) from the CSV static resource
// Latona_Product_Catalog into Product2 + Standard Price Book entries (UAH incl. VAT).
// Prerequisites (deploy first): static resource Latona_Product_Catalog, standard value sets
// Product2Family and QuantityUnitOfMeasure.
// Idempotent: products are matched by ProductCode and updated; prices in the Standard Price Book
// are created or updated. Products missing from the CSV are left untouched.
// Run: sf apex run --file scripts/apex/load_latona_product_catalog.apex

String csv = [SELECT Body FROM StaticResource WHERE Name = 'Latona_Product_Catalog' LIMIT 1].Body.toString();
csv = csv.removeStart('﻿').replace('\r\n', '\n').replace('\r', '\n');

// Minimal CSV parser: comma-separated, fields optionally wrapped in double quotes ("" = escaped quote).
List<List<String>> rows = new List<List<String>>();
for (String line : csv.split('\n')) {
    if (String.isBlank(line)) continue;
    List<String> cells = new List<String>();
    String cell = '';
    Boolean quoted = false;
    for (Integer i = 0; i < line.length(); i++) {
        String c = line.substring(i, i + 1);
        if (quoted) {
            if (c == '"' && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') { cell += '"'; i++; }
            else if (c == '"') quoted = false;
            else cell += c;
        } else if (c == '"') quoted = true;
        else if (c == ',') { cells.add(cell.trim()); cell = ''; }
        else cell += c;
    }
    cells.add(cell.trim());
    rows.add(cells);
}

List<String> header = rows.remove(0);
Map<String, Integer> col = new Map<String, Integer>();
for (Integer i = 0; i < header.size(); i++) col.put(header[i], i);
for (String required : new List<String>{ 'ProductCode', 'Name', 'Family', 'QuantityUnitOfMeasure', 'UnitPrice' }) {
    if (!col.containsKey(required)) throw new IllegalArgumentException('CSV is missing column ' + required);
}

Map<String, List<String>> rowByCode = new Map<String, List<String>>();
for (List<String> r : rows) rowByCode.put(r[col.get('ProductCode')], r);

Map<String, Product2> productByCode = new Map<String, Product2>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :rowByCode.keySet()]) {
    productByCode.put(p.ProductCode, p);
}
List<Product2> products = new List<Product2>();
for (String code : rowByCode.keySet()) {
    List<String> r = rowByCode.get(code);
    Product2 p = productByCode.containsKey(code) ? productByCode.get(code) : new Product2(ProductCode = code);
    p.Name = r[col.get('Name')];
    p.Family = r[col.get('Family')];
    p.QuantityUnitOfMeasure = r[col.get('QuantityUnitOfMeasure')];
    p.IsActive = true;
    products.add(p);
    productByCode.put(code, p);
}
upsert products;

Id stdPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Map<Id, PricebookEntry> entryByProduct = new Map<Id, PricebookEntry>();
for (PricebookEntry e : [SELECT Id, Product2Id FROM PricebookEntry
                         WHERE Pricebook2Id = :stdPricebookId AND Product2Id IN :new Map<Id, Product2>(products).keySet()]) {
    entryByProduct.put(e.Product2Id, e);
}
List<PricebookEntry> entries = new List<PricebookEntry>();
for (String code : rowByCode.keySet()) {
    Product2 p = productByCode.get(code);
    PricebookEntry e = entryByProduct.containsKey(p.Id)
        ? entryByProduct.get(p.Id)
        : new PricebookEntry(Pricebook2Id = stdPricebookId, Product2Id = p.Id, UseStandardPrice = false);
    e.UnitPrice = Decimal.valueOf(rowByCode.get(code)[col.get('UnitPrice')]);
    e.IsActive = true;
    entries.add(e);
}
upsert entries;

System.debug('Latona catalog loaded: ' + products.size() + ' products, ' + entries.size() + ' Standard Price Book entries');
