let nextTaskId = 1;

export function createRequestGate() {
  let generation = 0;

  return {
    begin() {
      generation += 1;
      return generation;
    },
    cancel() {
      generation += 1;
    },
    runIfCurrent(requestGeneration, callback) {
      if (requestGeneration !== generation) return false;
      callback();
      return true;
    },
  };
}

export function isEditableTarget(target) {
  const tagName = target?.tagName?.toUpperCase?.() ?? '';
  return ['INPUT', 'TEXTAREA', 'SELECT'].includes(tagName) || target?.isContentEditable === true;
}

export function shouldHandleScenarioShortcut({ key, metaKey, altKey, target, workspaceOpen }) {
  return !workspaceOpen
    && !metaKey
    && !altKey
    && !isEditableTarget(target)
    && ['1', '2', '3', '4', '5'].includes(key);
}

export function resolveInputSource({ selection = '', clipboard = '', typed = '' }) {
  if (selection.trim()) return { source: 'selection', text: selection.trim() };
  if (clipboard.trim()) return { source: 'clipboard', text: clipboard.trim() };
  return { source: 'typed', text: typed.trim() };
}

export function classifyTask({ mode, text, dictionaryTerms = new Set() }) {
  if (mode === 'improve') return 'improvement';
  const normalized = text.trim().toLowerCase();
  if (normalized && dictionaryTerms.has(normalized)) return 'dictionary';
  return 'translation';
}

export function createTask({ mode, source, text }) {
  return {
    id: `task-${nextTaskId++}`,
    mode,
    source,
    text,
    surface: 'quick-panel',
    result: null,
  };
}

export function openInWorkspace(task) {
  return { ...task, surface: 'workspace' };
}

export function copyTargetFor({ kind, result }) {
  if (kind === 'zh-to-en') return result.english;
  if (kind === 'en-to-zh') return result.translationZh;
  if (kind === 'improvement') return result.improvedText;
  return '';
}

export function filterHistory(records, { mode = 'all', query = '' } = {}) {
  const needle = query.trim().toLowerCase();
  return records.filter((record) => {
    const modeMatches = mode === 'all' || record.mode === mode;
    const text = `${record.input ?? ''} ${record.output ?? ''}`.toLowerCase();
    return modeMatches && (!needle || text.includes(needle));
  });
}

export function buildReviewQueue(records) {
  return records
    .filter((record) => record.savedForReview || (record.repeatCount ?? 0) > 1)
    .toSorted((left, right) => {
      const leftRepeated = (left.repeatCount ?? 0) > 1;
      const rightRepeated = (right.repeatCount ?? 0) > 1;
      const leftBoth = left.savedForReview && leftRepeated;
      const rightBoth = right.savedForReview && rightRepeated;
      if (leftBoth !== rightBoth) return Number(rightBoth) - Number(leftBoth);
      if ((left.repeatCount ?? 0) !== (right.repeatCount ?? 0)) {
        return (right.repeatCount ?? 0) - (left.repeatCount ?? 0);
      }
      return Number(right.savedForReview) - Number(left.savedForReview);
    });
}
