import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { csvToRows } from './csv';

const here = dirname(fileURLToPath(import.meta.url));
const csvPath = resolve(here, '../../scripts/pkb_backfill/blood_tests.csv');
const outPath = resolve(here, '../data/blood_tests.json');

const rows = csvToRows(readFileSync(csvPath, 'utf8'));
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(rows));
console.log(`build-data: wrote ${rows.length} rows to ${outPath}`);
