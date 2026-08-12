import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildReviewQueue,
  classifyTask,
  copyTargetFor,
  createRequestGate,
  createTask,
  filterHistory,
  isEditableTarget,
  openInWorkspace,
  resolveInputSource,
  shouldHandleScenarioShortcut,
} from '../app-model.mjs';

test('starting a newer request prevents an older callback from running', () => {
  const gate = createRequestGate();
  const completed = [];
  const olderRequest = gate.begin();
  const newerRequest = gate.begin();

  assert.equal(gate.runIfCurrent(olderRequest, () => completed.push('older')), false);
  assert.equal(gate.runIfCurrent(newerRequest, () => completed.push('newer')), true);
  assert.deepEqual(completed, ['newer']);
});

test('cancelling a request prevents its callback from running', () => {
  const gate = createRequestGate();
  const request = gate.begin();
  let completed = false;

  gate.cancel();

  assert.equal(gate.runIfCurrent(request, () => { completed = true; }), false);
  assert.equal(completed, false);
});

test('scenario shortcuts are ignored for editable controls and content', () => {
  for (const tagName of ['INPUT', 'TEXTAREA', 'SELECT']) {
    assert.equal(isEditableTarget({ tagName, isContentEditable: false }), true);
  }
  assert.equal(isEditableTarget({ tagName: 'DIV', isContentEditable: true }), true);
  assert.equal(isEditableTarget({ tagName: 'BUTTON', isContentEditable: false }), false);
});

test('scenario shortcuts are disabled while workspace is open', () => {
  const base = {
    key: '1',
    metaKey: false,
    altKey: false,
    target: { tagName: 'BUTTON', isContentEditable: false },
  };

  assert.equal(shouldHandleScenarioShortcut({ ...base, workspaceOpen: true }), false);
  assert.equal(shouldHandleScenarioShortcut({ ...base, workspaceOpen: false }), true);
});

test('selected text takes priority over clipboard text', () => {
  assert.deepEqual(
    resolveInputSource({ selection: 'selected text', clipboard: 'old clipboard', typed: '' }),
    { source: 'selection', text: 'selected text' },
  );
});

test('clipboard is used when there is no selected text', () => {
  assert.deepEqual(
    resolveInputSource({ selection: '', clipboard: 'clipboard text', typed: '' }),
    { source: 'clipboard', text: 'clipboard text' },
  );
});

test('typed input is used when selection and clipboard are empty', () => {
  assert.deepEqual(
    resolveInputSource({ selection: '', clipboard: '', typed: 'typed text' }),
    { source: 'typed', text: 'typed text' },
  );
});

test('translate classifies an ECDICT word as dictionary', () => {
  assert.equal(
    classifyTask({ mode: 'translate', text: 'relocate', dictionaryTerms: new Set(['relocate']) }),
    'dictionary',
  );
});

test('translate classifies a sentence as translation', () => {
  assert.equal(
    classifyTask({ mode: 'translate', text: 'Can we move this to Tuesday?', dictionaryTerms: new Set() }),
    'translation',
  );
});

test('improve never silently becomes translation or dictionary', () => {
  assert.equal(
    classifyTask({ mode: 'improve', text: 'relocate', dictionaryTerms: new Set(['relocate']) }),
    'improvement',
  );
});

test('opening a quick-panel task in workspace preserves its task identity and result', () => {
  const task = createTask({ mode: 'translate', source: 'selection', text: 'Please keep me posted.' });
  const workspaceTask = openInWorkspace({ ...task, result: { translationZh: '请随时告诉我进展。' } });

  assert.equal(workspaceTask.id, task.id);
  assert.equal(workspaceTask.surface, 'workspace');
  assert.deepEqual(workspaceTask.result, { translationZh: '请随时告诉我进展。' });
});

test('copy target follows the primary result for each workflow', () => {
  assert.equal(copyTargetFor({ kind: 'zh-to-en', result: { english: 'Sounds good.' } }), 'Sounds good.');
  assert.equal(copyTargetFor({ kind: 'en-to-zh', result: { translationZh: '听起来不错。' } }), '听起来不错。');
  assert.equal(copyTargetFor({ kind: 'improvement', result: { improvedText: 'Is there anything you need?' } }), 'Is there anything you need?');
});

test('history can be filtered by mode and text without changing the original records', () => {
  const records = [
    { id: '1', mode: 'translate', input: 'Please keep me posted', output: '请随时告诉我进展' },
    { id: '2', mode: 'improve', input: 'anything need', output: 'anything you need' },
    { id: '3', mode: 'dictionary', input: 'relocate', output: '搬迁' },
  ];

  assert.deepEqual(filterHistory(records, { mode: 'improve', query: 'need' }).map(record => record.id), ['2']);
  assert.equal(records.length, 3);
});

test('review queue prioritizes saved and repeated learning items', () => {
  const records = [
    { id: '1', savedForReview: false, repeatCount: 1 },
    { id: '2', savedForReview: true, repeatCount: 1 },
    { id: '3', savedForReview: false, repeatCount: 4 },
    { id: '4', savedForReview: true, repeatCount: 3 },
  ];

  assert.deepEqual(buildReviewQueue(records).map(record => record.id), ['4', '3', '2']);
});
