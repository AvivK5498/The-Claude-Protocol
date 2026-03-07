#!/usr/bin/env node

const { execSync } = require('child_process');
const path = require('path');

const args = process.argv.slice(2);
const command = args[0];
const packageDir = path.dirname(__dirname);
const bootstrapScript = path.join(packageDir, 'bootstrap.py');

function showHelp() {
  console.log(`
claude-protocol - Enforcement-first orchestration for Claude Code

Usage:
  claude-protocol init [options]

Commands:
  init          Install into current project (beads, agents, hooks, rules, skills)
  help             Show this help message

Options:
  --project-name   Project name (auto-inferred if not provided)
  --project-dir    Project directory (default: current)
  --no-rules       Skip dev rules (implementation, logging, TDD)

Examples:
  claude-protocol init
  claude-protocol init --project-dir /path/to/project
  claude-protocol init --no-rules
`);
}

function runInstall() {
  const bootstrapArgs = args.slice(1);
  // --with-rules by default, unless --no-rules is specified
  if (!bootstrapArgs.includes('--no-rules')) {
    if (!bootstrapArgs.includes('--with-rules')) {
      bootstrapArgs.push('--with-rules');
    }
  } else {
    // Remove --no-rules (bootstrap.py doesn't know this flag)
    const idx = bootstrapArgs.indexOf('--no-rules');
    bootstrapArgs.splice(idx, 1);
  }
  try {
    const pythonCmd = process.platform === 'win32' ? 'python' : 'python3';
    execSync(`${pythonCmd} "${bootstrapScript}" ${bootstrapArgs.join(' ')}`, { stdio: 'inherit' });
  } catch (err) {
    process.exit(err.status || 1);
  }
}

switch (command) {
  case 'init':
    runInstall();
    break;
  case 'help':
  case '--help':
  case '-h':
  case undefined:
    showHelp();
    break;
  default:
    console.error(`Unknown command: ${command}`);
    showHelp();
    process.exit(1);
}
