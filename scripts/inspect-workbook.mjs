import { FileBlob, SpreadsheetFile } from "@oai/artifact-tool";

const sourcePath = process.argv[2];

if (!sourcePath) {
  throw new Error("Usage: node scripts/inspect-workbook.mjs <workbook.xlsx>");
}

const input = await FileBlob.load(sourcePath);
const workbook = await SpreadsheetFile.importXlsx(input);

const overview = await workbook.inspect({
  kind: "workbook,sheet,definedName,drawing,table",
  maxChars: 20_000,
  tableMaxRows: 12,
  tableMaxCols: 16,
  tableMaxCellChars: 160,
});

console.log("__OVERVIEW__");
console.log(overview.ndjson);

const sheetOverview = await workbook.inspect({
  kind: "sheet",
  include: "id,name",
  maxChars: 10_000,
});

console.log("__SHEETS__");
console.log(sheetOverview.ndjson);

for (const sheet of workbook.worksheets.items) {
  const used = sheet.getUsedRange();
  console.log(`__SHEET__ ${sheet.name} ${used?.address ?? "empty"}`);
  if (!used) continue;

  const region = await workbook.inspect({
    kind: "region,formula",
    sheetId: sheet.name,
    range: used.address,
    maxChars: 30_000,
    tableMaxRows: 80,
    tableMaxCols: 24,
    tableMaxCellChars: 200,
    options: { maxResults: 500 },
  });
  console.log(region.ndjson);
}
