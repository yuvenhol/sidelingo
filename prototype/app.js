import { buildReviewQueue, classifyTask, copyTargetFor, createRequestGate, createTask, filterHistory, isEditableTarget, openInWorkspace, shouldHandleScenarioShortcut } from './app-model.mjs';

const dictionaryTerms = new Set(['relocate']);

const fixtures = {
  'zh-en': {
    mode: 'translate',
    source: 'selection',
    provider: 'OpenAI',
    input: '这个方案我需要再看一下，晚点回复你。',
    kind: 'zh-to-en',
    result: {
      english: "Let me take another look at this and get back to you later.",
      backTranslationZh: '让我再看一下这个，晚点再回复你。',
    },
  },
  'en-zh': {
    mode: 'translate',
    source: 'clipboard',
    provider: 'DeepSeek',
    input: 'Could you verify that scmp.io is working after the migration?',
    kind: 'en-to-zh',
    result: {
      translationZh: '你可以在迁移完成后确认一下 scmp.io 是否正常吗？',
      suggestedReplyEn: "Sure, I'll check it after the migration and let you know.",
    },
  },
  'improve-en': {
    mode: 'improve',
    source: 'selection',
    provider: 'Doubao',
    input: 'Is there anything need from our end?',
    kind: 'improvement',
    result: {
      improvedText: 'Is there anything you need from our side?',
      changes: [
        { original: 'anything need', replacement: 'anything you need', type: 'grammar', explanation: '关系从句需要主语 you，后面再接动词 need。' },
        { original: 'from our end', replacement: 'from our side', type: 'naturalness', explanation: '两种表达都能理解，但在这个工作场景中 from our side 更自然。' },
      ],
    },
  },
  'improve-mixed': {
    mode: 'improve',
    source: 'typed',
    provider: 'OpenAI',
    input: 'Hi Vincent，这个 PR I already checked，应该可以 deploy to labs。',
    kind: 'improvement',
    result: {
      improvedText: "Hi Vincent, I've reviewed the PR, and it should be ready to deploy to the labs environment.",
      changes: [
        { original: '这个 PR I already checked', replacement: "I've reviewed the PR", type: 'structure', explanation: '将中英混杂片段整理为完整英文，并保留 PR 这个技术缩写。' },
        { original: '应该可以 deploy to labs', replacement: 'should be ready to deploy to the labs environment', type: 'naturalness', explanation: '补充 ready to，使发布状态更清晰；labs 作为环境名称保留。' },
      ],
    },
  },
  dictionary: {
    mode: 'translate',
    source: 'selection',
    provider: 'Local · ECDICT',
    input: 'relocate',
    kind: 'dictionary',
    result: {
      word: 'relocate', phonetic: '/ˌriːləʊˈkeɪt/', pos: 'v:100',
      translation: 'vt. 重新安置；迁移；搬迁\nvi. 重新定居',
      definition: 'v. move or establish in a new location',
      exchange: 'd:relocated / p:relocated / 3:relocates / i:relocating',
      frequency: 'BNC 8,942 · Contemporary 6,316',
      tags: ['IELTS', 'CET6', 'GRE', 'TOEFL', 'Oxford 3000'],
    },
  },
};

const historyRecords = [
  { id: 'h1', mode: 'improve', input: 'Is there anything need from our end?', output: 'Is there anything you need from our side?', time: 'Just now', provider: 'Doubao', savedForReview: true, repeatCount: 4, reviewType: 'Grammar', note: '关系从句缺少主语 you。' },
  { id: 'h2', mode: 'translate', input: 'Could you verify it after the migration?', output: '你可以在迁移完成后确认一下吗？', time: '12 min ago', provider: 'DeepSeek', savedForReview: false, repeatCount: 1 },
  { id: 'h3', mode: 'dictionary', input: 'relocate', output: '搬迁；重新安置；迁移', time: 'Yesterday', provider: 'ECDICT', savedForReview: true, repeatCount: 3, reviewType: 'Vocabulary', note: '常见搭配：relocate resources / relocate to a new cluster' },
  { id: 'h4', mode: 'translate', input: '这个方案我需要再看一下，晚点回复你。', output: 'Let me take another look at this and get back to you later.', time: 'Yesterday', provider: 'OpenAI', savedForReview: true, repeatCount: 2, reviewType: 'Workplace phrase', note: 'get back to you：稍后回复你。' },
  { id: 'h5', mode: 'improve', input: 'I will let you know before migration starting.', output: 'I’ll let you know before the migration starts.', time: 'Mon', provider: 'OpenAI', savedForReview: false, repeatCount: 3, reviewType: 'Grammar', note: 'before 后接完整从句：before the migration starts。' },
  { id: 'h6', mode: 'dictionary', input: 'keep me posted', output: '随时告诉我最新进展', time: 'Mon', provider: 'ECDICT', savedForReview: true, repeatCount: 5, reviewType: 'Phrase', note: '职场高频表达，用于请求持续更新。' },
];

const els = {
  panel: document.querySelector('#quickPanel'),
  input: document.querySelector('#sourceInput'),
  result: document.querySelector('#resultRegion'),
  modeIcon: document.querySelector('#modeIcon'),
  modeStatus: document.querySelector('#modeStatus'),
  sourceStatus: document.querySelector('#sourceStatus'),
  providerStatus: document.querySelector('#providerStatus'),
  workspace: document.querySelector('#workspace'),
  workspaceResult: document.querySelector('#workspaceResult'),
  workspaceHeading: document.querySelector('#workspaceHeading'),
  workspaceEyebrow: document.querySelector('.workspace-heading .eyebrow'),
  workspaceControls: document.querySelector('#workspaceControls'),
  toast: document.querySelector('#toast'),
  settings: document.querySelector('#settingsDialog'),
};

let currentScenario = 'zh-en';
let currentFixture = fixtures[currentScenario];
let currentTask = createTask({ mode: currentFixture.mode, source: currentFixture.source, text: currentFixture.input });
currentTask = { ...currentTask, kind: currentFixture.kind, result: currentFixture.result };
let currentWorkspaceView = 'current';
const requestGate = createRequestGate();
let pendingRequestTimer = null;

function escapeHtml(value = '') {
  return value.replace(/[&<>'"]/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#039;', '"': '&quot;' }[char]));
}

function copyButton(value, label = 'Copy') {
  return `<button class="copy-button" data-copy="${encodeURIComponent(value)}" type="button">${label}<kbd>⌘C</kbd></button>`;
}

function currentPrimaryCopyValue() {
  if (currentFixture.kind === 'dictionary') {
    return `${currentFixture.result.word}\n${currentFixture.result.translation}`;
  }
  return copyTargetFor({ kind: currentFixture.kind, result: currentFixture.result });
}

function renderResult(fixture = currentFixture) {
  const { kind, result } = fixture;
  if (kind === 'zh-to-en') {
    return `<div class="result-content">
      <section class="result-section"><div class="section-heading"><span class="section-label primary">English · Ready to send</span>${copyButton(result.english)}</div><p class="result-text">${escapeHtml(result.english)}</p></section>
      <section class="result-section"><div class="section-heading"><span class="section-label">中文回译 · Meaning check</span></div><p class="result-text zh">${escapeHtml(result.backTranslationZh)}</p></section>
      <div class="action-row"><button class="action-chip">Make shorter</button><button class="action-chip">More polite</button><button class="action-chip">Explain wording</button></div>
    </div>`;
  }
  if (kind === 'en-to-zh') {
    return `<div class="result-content">
      <section class="result-section"><div class="section-heading"><span class="section-label primary">中文翻译</span>${copyButton(result.translationZh)}</div><p class="result-text zh">${escapeHtml(result.translationZh)}</p></section>
      <section class="result-section"><div class="section-heading"><span class="section-label">Suggested reply · 建议回复</span>${copyButton(result.suggestedReplyEn, 'Copy reply')}</div><p class="result-text">${escapeHtml(result.suggestedReplyEn)}</p></section>
    </div>`;
  }
  if (kind === 'improvement') {
    const cards = result.changes.map((change, index) => `<article class="change-card"><span class="change-index">${index + 1}</span><div class="change-content"><strong>${escapeHtml(change.original)}</strong> → <strong>${escapeHtml(change.replacement)}</strong><span class="change-type">${escapeHtml(change.type)}</span><br>${escapeHtml(change.explanation)}</div></article>`).join('');
    return `<div class="result-content">
      <section class="result-section"><div class="section-heading"><span class="section-label">Original</span></div><p class="result-text zh">${escapeHtml(fixture.input)}</p></section>
      <section class="result-section"><div class="section-heading"><span class="section-label primary">Improved</span>${copyButton(result.improvedText)}</div><p class="result-text">${escapeHtml(result.improvedText)}</p></section>
      <section class="result-section"><div class="section-heading"><span class="section-label">Detailed changes</span></div><div class="change-list">${cards}</div></section>
    </div>`;
  }
  if (kind === 'dictionary') {
    return `<div class="result-content">
      <div class="dictionary-head"><div><div class="section-label primary">Dictionary · ECDICT</div><h2 class="word-title">${escapeHtml(result.word)}</h2><p class="phonetic">${escapeHtml(result.phonetic)} · ${escapeHtml(result.pos)}</p></div><button class="speak-button" type="button" aria-label="Pronounce">◖))</button></div>
      <div class="dict-grid">
        <section class="dict-card full"><label>中文释义</label><p>${escapeHtml(result.translation).replaceAll('\n','<br>')}</p></section>
        <section class="dict-card full"><label>English definition</label><p>${escapeHtml(result.definition)}</p></section>
        <section class="dict-card"><label>Word forms</label><p>${escapeHtml(result.exchange)}</p></section>
        <section class="dict-card"><label>Frequency</label><p>${escapeHtml(result.frequency)}</p></section>
        <section class="dict-card full"><label>Tags</label><div class="tags">${result.tags.map(tag => `<span class="tag">${escapeHtml(tag)}</span>`).join('')}</div></section>
      </div>
    </div>`;
  }
  return '';
}

function providerMarkup(name) {
  const providerClass = name.startsWith('OpenAI') ? 'openai' : name.startsWith('DeepSeek') ? 'deepseek' : name.startsWith('Doubao') ? 'doubao' : 'local';
  return `<span class="provider-dot ${providerClass}"></span>${escapeHtml(name)}`;
}

function updatePanel(fixture, { loading = false } = {}) {
  currentFixture = fixture;
  els.input.value = fixture.input;
  autoGrow();
  const improve = fixture.mode === 'improve';
  els.modeIcon.textContent = improve ? '优' : '译';
  els.modeIcon.className = `mode-icon ${improve ? 'improve' : 'translate'}`;
  els.modeStatus.textContent = improve ? 'Improve' : fixture.kind === 'dictionary' ? 'Dictionary' : 'Translate';
  els.sourceStatus.textContent = fixture.source[0].toUpperCase() + fixture.source.slice(1);
  els.providerStatus.innerHTML = providerMarkup(fixture.provider);
  els.result.innerHTML = loading ? `<div class="result-content"><div class="loading-wrap"><span class="loader"></span><span>${improve ? 'Improving' : 'Translating'} with ${escapeHtml(fixture.provider)}…</span></div></div>` : renderResult(fixture);
  currentTask = createTask({ mode: fixture.mode, source: fixture.source, text: fixture.input });
  currentTask = { ...currentTask, kind: fixture.kind, result: fixture.result };
  bindCopyButtons();
}

function invalidatePendingRequest() {
  if (pendingRequestTimer !== null) {
    window.clearTimeout(pendingRequestTimer);
    pendingRequestTimer = null;
  }
  requestGate.cancel();
}

function schedulePanelUpdate(fixture, delay) {
  const requestGeneration = requestGate.begin();
  pendingRequestTimer = window.setTimeout(() => {
    requestGate.runIfCurrent(requestGeneration, () => {
      pendingRequestTimer = null;
      updatePanel(fixture);
    });
  }, delay);
}

function showScenario(name, simulate = false) {
  invalidatePendingRequest();
  currentScenario = name;
  document.querySelectorAll('[data-scenario]').forEach(button => button.classList.toggle('active', button.dataset.scenario === name));
  const fixture = fixtures[name];
  if (simulate) {
    updatePanel(fixture, { loading: true });
    schedulePanelUpdate(fixture, 520);
  } else updatePanel(fixture);
  els.panel.classList.remove('hidden');
}

function autoGrow() {
  els.input.style.height = 'auto';
  els.input.style.height = `${Math.min(els.input.scrollHeight, 126)}px`;
}

function inferFixtureFromInput() {
  const text = els.input.value.trim();
  const mode = currentFixture.mode;
  const classification = classifyTask({ mode, text, dictionaryTerms });
  if (classification === 'dictionary' && text.toLowerCase() === 'relocate') return { ...fixtures.dictionary, input: text, source: 'typed' };
  if (mode === 'improve') {
    const hasChinese = /[\u3400-\u9fff]/.test(text);
    return { ...(hasChinese ? fixtures['improve-mixed'] : fixtures['improve-en']), input: text || fixtures['improve-en'].input, source: 'typed' };
  }
  const hasChinese = /[\u3400-\u9fff]/.test(text);
  return { ...(hasChinese ? fixtures['zh-en'] : fixtures['en-zh']), input: text || fixtures['zh-en'].input, source: 'typed' };
}

function runCurrent() {
  invalidatePendingRequest();
  const fixture = inferFixtureFromInput();
  updatePanel(fixture, { loading: true });
  schedulePanelUpdate(fixture, 600);
}

async function copyText(value, successMessage = 'Copied') {
  let copied = false;
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      copied = true;
    }
  } catch { /* LAN HTTP may not expose the async clipboard API */ }
  if (!copied) {
    const textarea = document.createElement('textarea');
    textarea.value = value;
    textarea.setAttribute('readonly', '');
    textarea.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.append(textarea);
    textarea.select();
    copied = document.execCommand('copy');
    textarea.remove();
  }
  showToast(copied ? successMessage : 'Copy unavailable');
  return copied;
}

function bindCopyButtons(root = document) {
  root.querySelectorAll('[data-copy]').forEach(button => {
    button.onclick = () => {
      const value = decodeURIComponent(button.dataset.copy);
      return copyText(value, button.textContent.includes('reply') ? 'Reply copied' : 'Copied');
    };
  });
}

function showToast(message) {
  els.toast.textContent = message;
  els.toast.classList.add('show');
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => els.toast.classList.remove('show'), 1200);
}

function renderHistoryRows(records) {
  return records.map((record) => `<article class="history-row">
    <span class="history-kind ${record.mode}">${record.mode}</span>
    <div class="history-copy"><strong>${escapeHtml(record.input)}</strong><span>${escapeHtml(record.output)}</span></div>
    <div class="history-meta">${escapeHtml(record.time)}<br>${escapeHtml(record.provider)}</div>
  </article>`).join('');
}

function renderHistory(records = historyRecords) {
  return `<div class="summary-strip">
      <div class="summary-card"><strong>128</strong><span>Total records</span></div>
      <div class="summary-card"><strong>42</strong><span>Learned terms</span></div>
      <div class="summary-card"><strong>17</strong><span>Review queue</span></div>
    </div>
    <div class="history-tools"><input id="workspaceHistorySearch" class="history-search" aria-label="Search history" placeholder="Search original text, result, or term…"><select id="workspaceHistoryMode" class="filter-button" aria-label="Filter history by mode"><option value="all">All modes</option><option value="translate">Translate</option><option value="improve">Improve</option><option value="dictionary">Dictionary</option></select></div>
    <div id="historyList" class="history-list">${renderHistoryRows(records)}</div>`;
}

function renderReview() {
  const queue = buildReviewQueue(historyRecords);
  const cards = queue.slice(0, 3).map((record, index) => `<article class="review-card ${index === 0 ? 'featured' : ''}">
    <header><span class="review-type">${escapeHtml(record.reviewType ?? record.mode)}</span><span class="repeat-badge">Seen ${record.repeatCount}×</span></header>
    <h3>${escapeHtml(record.input)}</h3>
    <p>${escapeHtml(record.note ?? record.output)}</p>
    <footer><span class="history-meta">${escapeHtml(record.time)}</span><div class="review-actions"><button class="mini-button" data-workspace-action="again">Again</button><button class="mini-button" data-workspace-action="mastered">Mastered</button></div></footer>
  </article>`).join('');
  return `<div class="summary-strip">
      <div class="summary-card"><strong>17</strong><span>Due for review</span></div>
      <div class="summary-card"><strong>6</strong><span>Repeated mistakes</span></div>
      <div class="summary-card"><strong>73%</strong><span>Weekly progress</span></div>
    </div>
    <div class="review-layout"><section class="review-queue">${cards}</section>
      <aside class="review-insights"><h3>This week's patterns</h3>
        <div class="insight-row"><span>Relative clauses</span><strong>4 times</strong></div>
        <div class="insight-row"><span>Verb tense</span><strong>3 times</strong></div>
        <div class="insight-row"><span>Workplace phrases</span><strong>8 saved</strong></div>
        <div class="insight-row"><span>Dictionary lookups</span><strong>21 words</strong></div>
        <div class="progress-line"><i></i></div>
      </aside></div>`;
}

function renderGlossary() {
  const terms = [
    ['scmp.io', 'Project domain · preserve exactly'],
    ['labs cluster', 'Preferred wording · environment'],
    ['relocate resources', '迁移资源 · used 4 times'],
    ['get back to you', '稍后回复你 · saved phrase'],
    ['API gateway', 'Technical term · preserve case'],
    ['keep me posted', '随时告诉我进展 · saved phrase'],
  ];
  return `<div class="summary-strip"><div class="summary-card"><strong>42</strong><span>Active terms</span></div><div class="summary-card"><strong>8</strong><span>Auto learned</span></div><div class="summary-card"><strong>3</strong><span>Needs review</span></div></div>
    <div class="glossary-grid">${terms.map(([term, note]) => `<article class="term-card"><strong>${escapeHtml(term)}</strong><span>${escapeHtml(note)}</span></article>`).join('')}</div>`;
}

function bindHistorySearch() {
  const search = document.querySelector('#workspaceHistorySearch');
  const mode = document.querySelector('#workspaceHistoryMode');
  const list = document.querySelector('#historyList');
  if (!search || !mode || !list) return;
  const update = () => {
    const records = filterHistory(historyRecords, { query: search.value, mode: mode.value });
    list.innerHTML = renderHistoryRows(records) || '<div class="empty-state">No matching history</div>';
  };
  search.addEventListener('input', update);
  mode.addEventListener('change', update);
}

function switchWorkspaceView(view) {
  currentWorkspaceView = view;
  document.querySelectorAll('[data-workspace-view]').forEach(button => button.classList.toggle('active', button.dataset.workspaceView === view));
  els.workspaceResult.classList.toggle('wide', view !== 'current');
  if (view === 'history') {
    els.workspaceEyebrow.textContent = 'LOCAL RECORDS';
    els.workspaceHeading.textContent = 'History';
    els.workspaceControls.innerHTML = '<button class="secondary-button" data-workspace-action="clear">Clear all</button><button class="primary-button" data-workspace-action="export">Export</button>';
    els.workspaceResult.innerHTML = renderHistory();
    bindHistorySearch();
    return;
  }
  if (view === 'review') {
    els.workspaceEyebrow.textContent = 'LEARNING FROM REAL WORK';
    els.workspaceHeading.textContent = 'Review';
    els.workspaceControls.innerHTML = '<button class="secondary-button" data-workspace-action="export">Export Markdown</button><button class="primary-button" data-workspace-action="start-review">Start review</button>';
    els.workspaceResult.innerHTML = renderReview();
    return;
  }
  if (view === 'glossary') {
    els.workspaceEyebrow.textContent = 'LOCAL PERSONALIZATION';
    els.workspaceHeading.textContent = 'Glossary';
    els.workspaceControls.innerHTML = '<button class="secondary-button" data-workspace-action="export">Export</button><button class="primary-button" data-workspace-action="add-term">Add term</button>';
    els.workspaceResult.innerHTML = renderGlossary();
    return;
  }
  els.workspaceEyebrow.textContent = 'CURRENT TASK';
  els.workspaceHeading.textContent = currentFixture.kind === 'dictionary' ? `Dictionary · ${currentFixture.result.word}` : currentFixture.mode === 'improve' ? 'Improve' : 'Translate';
  els.workspaceControls.innerHTML = '<button class="secondary-button" data-workspace-action="save-review">Save for review</button><button class="primary-button" data-workspace-action="copy-primary">Copy result</button>';
  els.workspaceResult.innerHTML = renderResult(currentFixture);
  bindCopyButtons(els.workspaceResult);
}

function openWorkspace(view = 'current') {
  currentTask = openInWorkspace(currentTask);
  switchWorkspaceView(view);
  document.body.classList.add('workspace-open');
  els.workspace.classList.add('open');
  els.workspace.setAttribute('aria-hidden', 'false');
}

function closeWorkspace() {
  document.body.classList.remove('workspace-open');
  els.workspace.classList.remove('open');
  els.workspace.setAttribute('aria-hidden', 'true');
}

document.querySelectorAll('[data-scenario]').forEach(button => button.addEventListener('click', () => showScenario(button.dataset.scenario)));
document.querySelector('#runButton').addEventListener('click', runCurrent);
document.querySelector('#openWorkspace').addEventListener('click', () => openWorkspace('current'));
document.querySelector('#quickReview').addEventListener('click', () => openWorkspace('review'));
document.querySelector('#reviewButton').addEventListener('click', () => openWorkspace('review'));
document.querySelector('#closeWorkspace').addEventListener('click', closeWorkspace);
document.querySelector('#settingsButton').addEventListener('click', () => els.settings.showModal());
document.querySelector('#translateShortcut').addEventListener('click', () => showScenario('en-zh', true));
document.querySelector('#improveShortcut').addEventListener('click', () => showScenario('improve-en', true));
document.querySelectorAll('[data-workspace-view]').forEach(button => button.addEventListener('click', () => switchWorkspaceView(button.dataset.workspaceView)));

document.addEventListener('click', (event) => {
  const action = event.target.closest('[data-workspace-action]')?.dataset.workspaceAction;
  if (action === 'copy-primary') copyText(currentPrimaryCopyValue());
  else if (action === 'save-review') showToast('Saved for review');
  else if (action === 'export') showToast('Export prepared');
  else if (action === 'clear') showToast('Confirmation required');
  else if (action === 'start-review') showToast('Review started');
  else if (action === 'again') showToast('Scheduled again');
  else if (action === 'mastered') showToast('Marked as mastered');
  else if (action === 'add-term') showToast('Add-term form opened');

  if (event.target.closest('.action-chip')) showToast('Prototype action applied');
  if (event.target.closest('.shortcut-recorder')) showToast('Press a new shortcut');
  if (event.target.closest('.speak-button')) {
    speechSynthesis.cancel();
    speechSynthesis.speak(new SpeechSynthesisUtterance(currentFixture.result.word ?? currentFixture.input));
  }
});

els.input.addEventListener('input', autoGrow);
els.input.addEventListener('keydown', (event) => {
  if (event.metaKey && event.key === 'Enter') { event.preventDefault(); runCurrent(); }
});

document.addEventListener('keydown', (event) => {
  if (els.settings.open) return;
  if (event.metaKey && event.key.toLowerCase() === 'c') {
    const selectedText = window.getSelection()?.toString() ?? '';
    const editingInput = document.activeElement === els.input;
    if (!selectedText && !editingInput && (!els.workspace.classList.contains('open') || currentWorkspaceView === 'current')) {
      event.preventDefault();
      copyText(currentPrimaryCopyValue());
      return;
    }
  }
  if (event.key === 'Escape') {
    if (els.workspace.classList.contains('open')) closeWorkspace();
    else els.panel.classList.add('hidden');
    return;
  }
  if (event.metaKey && event.key.toLowerCase() === 'o') { event.preventDefault(); openWorkspace('current'); return; }
  if (shouldHandleScenarioShortcut({
    key: event.key,
    metaKey: event.metaKey,
    altKey: event.altKey,
    target: event.target,
    workspaceOpen: els.workspace.classList.contains('open'),
  })) {
    const names = ['zh-en','en-zh','improve-en','improve-mixed','dictionary'];
    showScenario(names[Number(event.key) - 1]);
  }
});

document.addEventListener('click', (event) => {
  if (els.panel.classList.contains('hidden') && !event.target.closest('.scenario-dock')) els.panel.classList.remove('hidden');
});

updatePanel(currentFixture);

const initialView = new URLSearchParams(window.location.search).get('view');
if (['current', 'history', 'glossary', 'review'].includes(initialView)) {
  openWorkspace(initialView);
}
