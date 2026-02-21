#!/usr/bin/env node
'use strict';

// recall.js — Search the project knowledge base
//
// Usage:
//   node recall.js "keyword"                  # Search by keyword
//   node recall.js "keyword" --type learned   # Filter by type
//   node recall.js --recent 10                # Show N most recent
//   node recall.js --stats                    # Knowledge base stats
//   node recall.js "keyword" --all            # Include archive

const fs = require('fs');
const path = require('path');

const scriptDir = path.dirname(process.argv[1] || __filename);
const knowledgeFile = path.join(scriptDir, 'knowledge.jsonl');
const archiveFile = path.join(scriptDir, 'knowledge.archive.jsonl');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function readJsonl(filePath) {
  try {
    return fs.readFileSync(filePath, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map(line => { try { return JSON.parse(line); } catch { return null; } })
      .filter(Boolean);
  } catch {
    return [];
  }
}

function formatEntry(e) {
  const typeLabel = (e.type || '').toUpperCase().slice(0, 5);
  const snippet = (e.content || '').slice(0, 200);
  const tagsStr = Array.isArray(e.tags) ? e.tags.join(',') : '';
  return `[${typeLabel}] ${e.key}\n  ${snippet}\n  source=${e.source} bead=${e.bead} tags=${tagsStr}\n`;
}

// ---------------------------------------------------------------------------
// Check file exists
// ---------------------------------------------------------------------------

if (!fs.existsSync(knowledgeFile) || fs.statSync(knowledgeFile).size === 0) {
  console.log('No knowledge entries yet.');
  console.log('Entries are created automatically from bd comment commands with LEARNED: prefixes.');
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Parse arguments
// ---------------------------------------------------------------------------

const args = process.argv.slice(2);
let query = '';
let typeFilter = '';
let includeArchive = false;
let showRecent = 0;
let showStats = false;

for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case '--type':
      typeFilter = args[++i] || '';
      break;
    case '--all':
      includeArchive = true;
      break;
    case '--recent':
      showRecent = parseInt(args[++i], 10) || 10;
      break;
    case '--stats':
      showStats = true;
      break;
    case '--help':
    case '-h':
      console.log('Usage: recall.js [query] [--type learned] [--all] [--recent N] [--stats]');
      process.exit(0);
      break;
    default:
      query = args[i];
  }
}

// ---------------------------------------------------------------------------
// Stats mode
// ---------------------------------------------------------------------------

if (showStats) {
  const entries = readJsonl(knowledgeFile);
  const learned = entries.filter(e => e.type === 'learned').length;
  const investigation = entries.filter(e => e.type === 'investigation').length;
  const uniqueKeys = new Set(entries.map(e => e.key)).size;
  const archiveEntries = readJsonl(archiveFile);

  console.log('## Knowledge Base Stats');
  console.log(`  Active entries: ${entries.length}`);
  console.log(`  Unique keys:    ${uniqueKeys}`);
  console.log(`  Learned:        ${learned}`);
  console.log(`  Investigation:  ${investigation}`);
  console.log(`  Archived:       ${archiveEntries.length}`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Recent mode
// ---------------------------------------------------------------------------

if (showRecent > 0) {
  const entries = readJsonl(knowledgeFile);
  const recent = entries.slice(-showRecent);
  console.log(`## Recent Knowledge (${showRecent} entries)\n`);
  for (const e of recent) {
    const typeLabel = (e.type || '').toUpperCase().slice(0, 5);
    const snippet = (e.content || '').slice(0, 120);
    console.log(`[${typeLabel}] ${e.key}\n  ${snippet}\n  source=${e.source} bead=${e.bead}\n`);
  }
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Search mode (default)
// ---------------------------------------------------------------------------

if (!query) {
  console.log('Usage: recall.js <keyword> [--type learned] [--all]');
  process.exit(1);
}

// Build entry list
let entries = readJsonl(knowledgeFile);
if (includeArchive) {
  entries = [...readJsonl(archiveFile), ...entries];
}

// Filter by keyword (case-insensitive)
const lowerQuery = query.toLowerCase();
let results = entries.filter(e => {
  const blob = JSON.stringify(e).toLowerCase();
  return blob.includes(lowerQuery);
});

// Apply type filter
if (typeFilter) {
  results = results.filter(e => e.type === typeFilter);
}

if (results.length === 0) {
  console.log(`No knowledge entries matching '${query}'`);
  if (typeFilter) console.log(`  (filtered by type: ${typeFilter})`);
  process.exit(0);
}

// Deduplicate by key (latest timestamp wins)
const byKey = new Map();
for (const e of results) {
  const existing = byKey.get(e.key);
  if (!existing || (e.ts || 0) > (existing.ts || 0)) {
    byKey.set(e.key, e);
  }
}

// Sort by timestamp descending and output
const deduped = [...byKey.values()].sort((a, b) => (b.ts || 0) - (a.ts || 0));
for (const e of deduped) {
  process.stdout.write(formatEntry(e));
}
