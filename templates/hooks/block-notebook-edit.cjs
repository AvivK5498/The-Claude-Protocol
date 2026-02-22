#!/usr/bin/env node
'use strict';

// PreToolUse: NotebookEdit — Block orchestrator from notebook editing

const { readStdinJSON, deny, runHook } = require('./hook-utils.cjs');

runHook('block-notebook-edit', () => {
  readStdinJSON(); // Sets _permissionMode for bypass check in deny()
  deny('Tool \'NotebookEdit\' blocked. Orchestrators investigate and delegate via Task(). Supervisors implement.');
});
