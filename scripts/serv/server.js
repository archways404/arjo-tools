import Fastify from "fastify";
import ExcelJS from "exceljs";
import dotenv from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, ".env") });

const app = Fastify({ logger: true });

const EXCEL_PATH = process.env.EXCEL_PATH;
const SHEET_NAME = process.env.SHEET_NAME ?? "Computers";
const START_ROW = parseInt(process.env.START_ROW ?? "2", 10);

console.log(EXCEL_PATH);

const COLUMN_MAP = {
  D: "PCName",
  AD: "Manufacturer",
  AF: "Model",
  AG: "ProductCode",
  X: "Serial",
  Y: "MACAddresses",
  //: "OSCaption",
  P: "OSRelease",
  //: "OSBuild",
};

// Static values — always written regardless of input
const STATIC_MAP = {
  AC: "No",
  AB: "Laptop",
  AH: "2026",
  AI: "01-06-2026",
  AJ: "EGISS",
  AK: "Win11",
};

function colLetterToIndex(col) {
  let index = 0;
  for (let i = 0; i < col.length; i++) {
    index = index * 26 + col.charCodeAt(i) - 64;
  }
  return index;
}

app.post("/pc-info", async (request, reply) => {
  try {
    const data = request.body;
    console.log("[RECEIVED]", data.PCName);

    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.readFile(EXCEL_PATH);

    const ws = workbook.getWorksheet(SHEET_NAME);
    // Find the next empty row starting from START_ROW
    let nextRow = START_ROW;
    while (ws.getRow(nextRow).getCell(1).value !== null) {
      nextRow++;
    }
    const row = ws.getRow(nextRow);

    for (const [col, field] of Object.entries(COLUMN_MAP)) {
      const colIndex = colLetterToIndex(col);
      row.getCell(colIndex).value = data[field] ?? "";
    }

    for (const [col, value] of Object.entries(STATIC_MAP)) {
      const colIndex = colLetterToIndex(col);
      row.getCell(colIndex).value = value;
    }

    row.commit();
    await workbook.xlsx.writeFile(EXCEL_PATH);

    console.log(`[SAVED] Row ${nextRow} written`);
    return { ok: true, row: nextRow };
  } catch (err) {
    console.error("[ERROR]", err.message);
    reply.status(500);
    return { ok: false, error: err.message };
  }
});

try {
  await app.listen({ port: 3000, host: "0.0.0.0" });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
