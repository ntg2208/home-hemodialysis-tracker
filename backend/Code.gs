// Treatment tracker — Google Apps Script backend
//
// Bound to a Google Sheet with three tabs: `sessions`, `readings`, `legacy_view`.
// Deploy as a Web App: Execute as Me, Who has access: Anyone.
// One-time setup: set a long random SHARED_SECRET via `setSecret()` below.
//
// The PWA POSTs JSON with `{secret, action, data}` against the web app /exec URL.
// All responses are JSON with an `ok` boolean — Apps Script can't set HTTP
// status codes on web apps, so the client must check `body.ok`.

const SHEET_SESSIONS = 'sessions';
const SHEET_READINGS = 'readings';
const SHEET_LEGACY   = 'legacy_view';

const SESSION_COLS = [
  'session_id', 'date',
  'pre_weight', 'uf_goal', 'uf_rate', 'pre_bp_sys', 'pre_bp_dia', 'pre_pulse',
  'post_weight', 'post_bp_sys', 'post_bp_dia', 'post_pulse',
  'duration_min', 'dialysate_volume', 'total_uf', 'blood_processed',
  'created_at'
];

const READING_COLS = [
  'reading_id', 'session_id', 'seq', 'time',
  'bp_sys', 'bp_dia', 'pulse', 'blood_flow',
  'venous_pressure', 'arterial_pressure', 'note', 'created_at'
];

// === Entry points ===

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    if (!verifySecret_(body.secret)) return json_({ ok: false, error: 'unauthorized' });
    switch (body.action) {
      case 'save_session':   return json_(saveSession_(body.data));
      case 'save_reading':   return json_(saveReading_(body.data));
      case 'update_session': return json_(updateSession_(body.data));
      default:               return json_({ ok: false, error: 'unknown_action' });
    }
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  }
}

function doGet(e) {
  if (!verifySecret_(e.parameter.secret)) return json_({ ok: false, error: 'unauthorized' });
  const since = e.parameter.since;
  return json_({
    ok: true,
    sessions: readTab_(SHEET_SESSIONS, SESSION_COLS, since, 'date'),
    readings: readTab_(SHEET_READINGS, READING_COLS, null, null),
  });
}

// === Write paths ===

function saveSession_(data) {
  const sh = sheet_(SHEET_SESSIONS);
  ensureHeader_(sh, SESSION_COLS);
  appendAsText_(sh, SESSION_COLS, data);
  rebuildLegacyView_();
  return { ok: true, session_id: data.session_id };
}

function saveReading_(data) {
  const sh = sheet_(SHEET_READINGS);
  ensureHeader_(sh, READING_COLS);
  appendAsText_(sh, READING_COLS, data);
  rebuildLegacyView_();
  return { ok: true, reading_id: data.reading_id };
}

function updateSession_(data) {
  const sh = sheet_(SHEET_SESSIONS);
  const values = sh.getDataRange().getValues();
  if (values.length < 1) return { ok: false, error: 'sessions_empty' };
  const header = values[0];
  const idCol = header.indexOf('session_id');
  if (idCol < 0) return { ok: false, error: 'no_session_id_column' };
  for (let i = 1; i < values.length; i++) {
    if (values[i][idCol] === data.session_id) {
      SESSION_COLS.forEach((c, j) => {
        if (c in data) {
          const cell = sh.getRange(i + 1, j + 1);
          cell.setNumberFormat('@');
          cell.setValue(data[c]);
        }
      });
      rebuildLegacyView_();
      return { ok: true };
    }
  }
  return { ok: false, error: 'session_not_found' };
}

// === Legacy view rebuild ===
// Rebuilds the legacy multi-row-per-session layout on every write so clinical
// readers see the format they already know. Simple full rebuild; optimize later
// if the dataset grows enough for it to be slow.

function rebuildLegacyView_() {
  const sessions = readTab_(SHEET_SESSIONS, SESSION_COLS, null, 'date');
  const readings = readTab_(SHEET_READINGS, READING_COLS, null, null);

  const readingsBySession = {};
  readings.forEach(r => {
    // Apps Script V8 rejected `||=` in this context — explicit if/check instead.
    if (!readingsBySession[r.session_id]) readingsBySession[r.session_id] = [];
    readingsBySession[r.session_id].push(r);
  });
  Object.values(readingsBySession).forEach(list => list.sort((a, b) => a.seq - b.seq));

  const out = [[
    'Date', 'Weight', 'UF Goal', 'UF rate', 'Blood Pressure', 'Pulse',
    'Time', 'Blood Pressure', 'Pulse', 'Bloodflow', 'Venous Pressure', 'Arterial Pressure', 'Note',
    'Weight', 'Blood Pressure', 'Pulse', 'Treatment Time', 'Dialysate volume', 'Total UF', 'Blood Processed'
  ]];

  sessions.forEach(s => {
    const rs = readingsBySession[s.session_id] || [];
    const n = Math.max(rs.length, 1);
    for (let i = 0; i < n; i++) {
      const r = rs[i] || {};
      const isFirst = i === 0;
      const isLast  = i === n - 1;
      out.push([
        isLast ? s.date : '',
        isFirst ? s.pre_weight : '', isFirst ? s.uf_goal : '', isFirst ? s.uf_rate : '',
        isFirst && s.pre_bp_sys ? s.pre_bp_sys + '/' + s.pre_bp_dia : '',
        isFirst ? s.pre_pulse : '',
        r.time || '',
        r.bp_sys ? r.bp_sys + '/' + r.bp_dia : '',
        r.pulse || '',
        r.blood_flow || '',
        r.venous_pressure || '',
        r.arterial_pressure || '',
        r.note || '',
        isLast ? s.post_weight : '',
        isLast && s.post_bp_sys ? s.post_bp_sys + '/' + s.post_bp_dia : '',
        isLast ? s.post_pulse : '',
        isLast ? formatDuration_(s.duration_min) : '',
        isLast ? s.dialysate_volume : '',
        isLast ? s.total_uf : '',
        isLast ? s.blood_processed : '',
      ]);
    }
  });

  const sh = sheet_(SHEET_LEGACY);
  sh.clear();
  if (out.length > 0) sh.getRange(1, 1, out.length, out[0].length).setValues(out);
}

// === Helpers ===

// `appendRow` re-coerces date-like strings into Date objects even when the
// target column is formatted as plain text. We need format-then-write at the
// cell level so '2026-05-12' stays a string and '19:15' doesn't become
// 1899-12-30T19:15Z.
function appendAsText_(sh, cols, data) {
  const row = cols.map(c => {
    if (c === 'created_at') return new Date().toISOString();
    const v = data[c];
    return v === undefined || v === null ? '' : v;
  });
  const targetRow = sh.getLastRow() + 1;
  const range = sh.getRange(targetRow, 1, 1, cols.length);
  range.setNumberFormat('@');
  range.setValues([row]);
  return row;
}

function ensureHeader_(sh, cols) {
  if (sh.getLastRow() === 0) {
    sh.getRange(1, 1, 1, cols.length).setValues([cols]);
  }
}

function sheet_(name) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  return ss.getSheetByName(name) || ss.insertSheet(name);
}

function readTab_(name, cols, sinceDate, dateCol) {
  const sh = sheet_(name);
  const values = sh.getDataRange().getValues();
  if (values.length < 2) return [];
  const header = values[0];
  const idx = {};
  cols.forEach(c => { idx[c] = header.indexOf(c); });
  return values.slice(1)
    .map(row => {
      const obj = {};
      cols.forEach(c => { obj[c] = idx[c] >= 0 ? row[idx[c]] : ''; });
      return obj;
    })
    .filter(r => !sinceDate || !dateCol || new Date(r[dateCol]) >= new Date(sinceDate));
}

function verifySecret_(provided) {
  const expected = PropertiesService.getScriptProperties().getProperty('SHARED_SECRET');
  return Boolean(expected && provided && provided === expected);
}

function json_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function formatDuration_(min) {
  if (!min) return '';
  const h = Math.floor(min / 60);
  const m = min % 60;
  const pad = n => String(n).padStart(2, '0');
  return pad(h) + ':' + pad(m);
}

// === One-time setup ===
// 1. Uncomment the body of `setSecret` below.
// 2. Replace 'paste-a-long-random-string' with a real long random secret.
// 3. Run `setSecret` once from the Apps Script editor.
// 4. Re-comment the body so it doesn't accidentally execute again.
// The secret is stored in Script Properties and never appears in the source.

function setSecret() {
  // PropertiesService.getScriptProperties().setProperty('SHARED_SECRET', 'paste-a-long-random-string');
}
