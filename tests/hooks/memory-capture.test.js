import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import os from 'os';

const HOOK_PATH = path.resolve(__dirname, '../../templates/hooks/memory-capture.cjs');

function runHook(stdinData, env = {}) {
  const input = JSON.stringify(stdinData);
  try {
    const stdout = execFileSync('node', [HOOK_PATH], {
      input,
      encoding: 'utf8',
      timeout: 5000,
      env: { ...process.env, ...env },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return { stdout, exitCode: 0 };
  } catch (err) {
    return { stdout: err.stdout || '', stderr: err.stderr || '', exitCode: err.status };
  }
}

describe('memory-capture hook', () => {
  let tmpDir;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'memory-capture-test-'));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it('captures LEARNED entry from bd comment', () => {
    const result = runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-001 "LEARNED: TaskGroup requires @Sendable closures"' },
        cwd: '/project/src',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    expect(result.exitCode).toBe(0);

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    expect(fs.existsSync(knowledgeFile)).toBe(true);

    const lines = fs.readFileSync(knowledgeFile, 'utf8').trim().split('\n');
    expect(lines.length).toBe(1);

    const entry = JSON.parse(lines[0]);
    expect(entry.type).toBe('learned');
    expect(entry.content).toBe('TaskGroup requires @Sendable closures');
    expect(entry.bead).toBe('BD-001');
    expect(entry.source).toBe('orchestrator');
    expect(entry.tags).toContain('learned');
    expect(entry.key).toMatch(/^learned-/);
    expect(entry.ts).toBeGreaterThan(0);
  });

  it('detects worktree source as supervisor', () => {
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-002 "LEARNED: API needs auth header"' },
        cwd: '/project/.worktrees/bd-002/src',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    const entry = JSON.parse(fs.readFileSync(knowledgeFile, 'utf8').trim());
    expect(entry.source).toBe('supervisor');
  });

  it('auto-detects tags from content', () => {
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-003 "LEARNED: async middleware needs concurrency guard"' },
        cwd: '/project',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    const entry = JSON.parse(fs.readFileSync(knowledgeFile, 'utf8').trim());
    expect(entry.tags).toContain('async');
    expect(entry.tags).toContain('middleware');
    expect(entry.tags).toContain('concurrency');
  });

  it('generates slug key from content', () => {
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-004 "LEARNED: Use pino for structured logging"' },
        cwd: '/project',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    const entry = JSON.parse(fs.readFileSync(knowledgeFile, 'utf8').trim());
    expect(entry.key).toBe('learned-use-pino-for-structured-logging');
  });

  it('ignores non-Bash tool', () => {
    const result = runHook(
      {
        tool_name: 'Edit',
        tool_input: { command: 'bd comment BD-001 "LEARNED: something"' },
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );
    expect(result.exitCode).toBe(0);

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    expect(fs.existsSync(knowledgeFile)).toBe(false);
  });

  it('ignores bd comment without LEARNED prefix', () => {
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-001 "Completed: task done"' },
        cwd: '/project',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    // File might exist (empty) or not exist at all
    if (fs.existsSync(knowledgeFile)) {
      expect(fs.readFileSync(knowledgeFile, 'utf8').trim()).toBe('');
    }
  });

  it('ignores non-bd commands', () => {
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'echo "LEARNED: something"' },
        cwd: '/project',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const knowledgeFile = path.join(tmpDir, '.beads', 'memory', 'knowledge.jsonl');
    if (fs.existsSync(knowledgeFile)) {
      expect(fs.readFileSync(knowledgeFile, 'utf8').trim()).toBe('');
    }
  });

  it('handles rotation when exceeding 1000 lines', () => {
    // Pre-fill with 1001 lines
    const memoryDir = path.join(tmpDir, '.beads', 'memory');
    fs.mkdirSync(memoryDir, { recursive: true });
    const knowledgeFile = path.join(memoryDir, 'knowledge.jsonl');

    const lines = [];
    for (let i = 0; i < 1001; i++) {
      lines.push(JSON.stringify({
        key: `learned-item-${i}`,
        type: 'learned',
        content: `Item ${i}`,
        source: 'orchestrator',
        tags: ['learned'],
        ts: 1700000000 + i,
        bead: 'BD-TEST',
      }));
    }
    fs.writeFileSync(knowledgeFile, lines.join('\n') + '\n');

    // Run hook to trigger rotation (adds entry, then checks >1000)
    runHook(
      {
        tool_name: 'Bash',
        tool_input: { command: 'bd comment BD-ROT "LEARNED: rotation test entry"' },
        cwd: '/project',
      },
      { CLAUDE_PROJECT_DIR: tmpDir }
    );

    const archiveFile = path.join(memoryDir, 'knowledge.archive.jsonl');
    expect(fs.existsSync(archiveFile)).toBe(true);

    const remaining = fs.readFileSync(knowledgeFile, 'utf8').trim().split('\n').filter(Boolean);
    // After rotation: 1002 lines → archive 500, keep 502
    expect(remaining.length).toBeLessThanOrEqual(600);
    expect(remaining.length).toBeGreaterThan(400);
  });
});
