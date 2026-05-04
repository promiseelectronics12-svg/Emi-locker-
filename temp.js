
const MODULE_PHASE_MAP = {
  'project-structure': 'Phase 1', 'database-schema': 'Phase 1', 'backend-auth': 'Phase 1',
  'backend-devices': 'Phase 1', 'backend-notifications': 'Phase 1', 'backend-emi': 'Phase 1',
  'backend-server-entry': 'Phase 1', 'backend-lock-engine': 'Phase 2', 'backend-keys': 'Phase 2',
  'backend-decoupling': 'Phase 2', 'backend-location': 'Phase 2', 'backend-admin-api': 'Phase 2',
  'backend-fraud': 'Phase 2', 'user-app-foundation': 'Phase 3', 'user-app-lock-states': 'Phase 3',
  'user-app-paut': 'Phase 3', 'user-app-dashboard': 'Phase 3', 'dealer-app-foundation': 'Phase 4',
  'dealer-app-enrollment': 'Phase 4', 'dealer-app-device-management': 'Phase 4', 'dealer-app-analytics': 'Phase 4',
  'reseller-app': 'Phase 5', 'admin-panel': 'Phase 5'
};

const state = {
  modules: new Map(),
  logs: [],
  phases: new Set(),
  selectedFilter: 'all',
  currentTab: 'modules',
  stats: {},
  buildComplete: false,
  isAtBottomLog: true
};

// --- DOM References ---
const els = {
  tabModules: document.getElementById('tab-modules'),
  tabLog: document.getElementById('tab-log'),
  tabFiles: document.getElementById('tab-files'),
  mainTabs: document.getElementById('mainTabs'),
  elapsedTime: document.getElementById('elapsedTime'),
  buildStatePill: document.getElementById('buildStatePill'),
  liveIndicator: document.getElementById('liveIndicator'),
  liveDot: document.getElementById('liveDot'),
  liveText: document.getElementById('liveText'),
  globalProgressBar: document.getElementById('globalProgressBar'),
  sidebarRunner: document.getElementById('sidebarRunner'),
  sidebarStatus: document.getElementById('sidebarStatus'),
  filterSidebar: document.getElementById('filterSidebar'),
  phaseSidebar: document.getElementById('phaseSidebar'),
  completeBanner: document.getElementById('completeBanner'),
  completeBannerText: document.getElementById('completeBannerText'),
  phaseSubtitle: document.getElementById('phaseSubtitle'),
  moduleList: document.getElementById('moduleList'),
  statsPct: document.getElementById('statsPct'),
  statsRatio: document.getElementById('statsRatio'),
  statsBar: document.getElementById('statsBar'),
  statsFailedCount: document.getElementById('statsFailedCount'),
  statsFailedList: document.getElementById('statsFailedList'),
  telemetryPulse: document.getElementById('telemetryPulse'),
  chatFeed: document.getElementById('chatFeed'),
  logSearch: document.getElementById('logSearch'),
  fullLogContainer: document.getElementById('fullLogContainer'),
  fileTreeContainer: document.getElementById('fileTreeContainer'),
  fileViewerPath: document.getElementById('fileViewerPath'),
  fileViewerContent: document.getElementById('fileViewerContent'),
  mainScrollArea: document.getElementById('mainScrollArea')
};

// --- Core Logic ---
function switchTab(tabId) {
  state.currentTab = tabId;
  els.tabModules.classList.toggle('hidden', tabId !== 'modules');
  els.tabModules.classList.toggle('block', tabId === 'modules');
  els.tabLog.classList.toggle('hidden', tabId !== 'log');
  els.tabLog.classList.toggle('flex', tabId === 'log');
  els.tabFiles.classList.toggle('hidden', tabId !== 'files');
  els.tabFiles.classList.toggle('flex', tabId === 'files');
  
  const buttons = els.mainTabs.querySelectorAll('button');
  buttons.forEach(btn => {
    if (btn.innerText.toLowerCase().includes(tabId.replace('log', 'full log'))) {
      btn.className = "pb-2 px-3 py-2 rounded-t-md transition-colors tab-active";
    } else {
      btn.className = "pb-2 px-3 py-2 rounded-t-md transition-colors tab-inactive";
    }
  });

  if (tabId === 'files') fetchTree();
  if (tabId === 'log') {
    renderFullLog();
    scrollToBottom('fullLogContainer');
  }
}

function setFilter(filter) {
  state.selectedFilter = filter;
  renderAll();
}

function labelize(id) {
  return (id || 'unknown').replace(/^backend-/, '').split('-').map(part => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

function ensureModule(id, patch = {}) {
  if (!id) return null;
  const inferredPhase = patch.phase || MODULE_PHASE_MAP[id] || 'Unassigned';
  let mod = state.modules.get(id);
  if (!mod) {
    mod = {
      id, label: labelize(id), phase: inferredPhase,
      status: 'pending', lastMessage: '', score: null, iteration: null, errorDetail: []
    };
    state.modules.set(id, mod);
  }
  Object.assign(mod, patch);
  if (mod.phase) state.phases.add(String(mod.phase));
  return mod;
}

function parsePhase(message) {
  const m = message.match(/Phase\s+(\d+)/i);
  return m ? `Phase ${m[1]}` : null;
}

function parseModuleFromMessage(message) {
  const patterns = [
    /^\[MODULE:\s*([\w-]+)\]/i,
    /MODULE:\s*([\w-]+)/i,
    /^WORKER[^:]*:\s*Implementing\s+([\w-]+)/i,
    /^WORKER[^:]*:\s*Fixing\s+\d+\s+issue.*?in\s+([\w-]+)/i,
    /^EXECUTOR[^:]*:\s*Reviewing\s+([\w-]+)/i,
    /APPROVED:\s*([\w-]+)/i,
    /NEEDS WORK:\s*([\w-]+)/i,
    /Skipping\s+([\w-]+)/i,
    /FAILED to implement ([\w-]+)/i
  ];
  for (const pattern of patterns) {
    const m = message.match(pattern);
    if (m && m[1]) return m[1];
  }
  return null;
}

function applyLog(entry) {
  const message = entry.message || '';
  const moduleId = entry.module || parseModuleFromMessage(message);
  const phase = parsePhase(message);
  const action = entry.action;

  if (moduleId) {
    const mod = ensureModule(moduleId, { phase });
    mod.lastMessage = message;
    
    if (entry.score !== null && entry.score !== undefined) mod.score = entry.score;
    
    const iterMatch = message.match(/Fix iteration (\d+)\/\d+/i);
    if (iterMatch) mod.iteration = iterMatch[1];
    
    if (message.includes('FAILED to implement') || message.includes('exit code 1') || message.includes('Traceback')) {
      if (!mod.errorDetail.includes(message)) mod.errorDetail.push(message);
    }

    if (action === 'implementing' || action === 'fixing' || action === 'started' || action === 're-reviewing') {
      mod.status = 'running';
    } else if (action === 'approved') {
      mod.status = 'approved';
    } else if (action === 'failed' || message.includes('FAILED to implement')) {
      mod.status = 'failed';
    } else if (/status=needs_changes/i.test(message) && mod.status !== 'running') {
      mod.status = 'failed';
    }
  } else if (phase) {
    state.phases.add(phase);
  }

  // Auto-select phase tracking
  const phaseMatch = message.match(/\[(\d+)\/\d+\]\s+MODULE:.*\(Phase\s+(\d+)\)/i);
  if (phaseMatch) {
    state.selectedFilter = `Phase ${phaseMatch[2]}`;
  } else if (/Running Phase\s+(\d+)/i.test(message)) {
    state.selectedFilter = `Phase ${message.match(/Running Phase\s+(\d+)/i)[1]}`;
  }
}

// --- Fetch API Stats ---
function fetchStats() {
  fetch('/api/stats').then(r => r.json()).then(data => {
    state.stats = data;
    
    const h = Math.floor(data.elapsedSeconds / 3600).toString().padStart(2, '0');
    const m = Math.floor((data.elapsedSeconds % 3600) / 60).toString().padStart(2, '0');
    const s = (data.elapsedSeconds % 60).toString().padStart(2, '0');
    els.elapsedTime.textContent = `${h}:${m}:${s} elapsed`;
    
    if (data.note) {
      els.sidebarRunner.textContent = "Supervisor Agent";
    }

    if (data.running === 0 && !data.builderActive) {
      els.liveIndicator.className = "px-md py-sm bg-slate-100 border border-slate-300 text-slate-700 rounded-full font-mono-label text-mono-label flex items-center gap-2 transition-colors";
      els.liveDot.classList.add('hidden');
      els.liveText.innerHTML = `<span class="material-symbols-outlined text-[14px]">stop_circle</span> Stopped`;
      els.telemetryPulse.classList.replace('bg-primary', 'bg-slate-400');
      els.telemetryPulse.classList.remove('animate-pulse');
    } else {
      els.liveIndicator.className = "px-md py-sm bg-green-50 border border-green-200 text-green-700 rounded-full font-mono-label text-mono-label flex items-center gap-2 transition-colors";
      els.liveDot.classList.remove('hidden');
      els.liveText.textContent = `Live`;
      els.telemetryPulse.classList.replace('bg-slate-400', 'bg-primary');
      els.telemetryPulse.classList.add('animate-pulse');
    }

    if (data.builderActive && data.running > 0) {
      els.buildStatePill.textContent = `Running module...`;
    } else if (data.failed > 0) {
      els.buildStatePill.textContent = `${data.failed} modules failed`;
    } else {
      els.buildStatePill.textContent = `Build healthy`;
    }
    
    renderSidebar();
  }).catch(e => console.error(e));
}

// --- Renderers ---
function renderSidebar() {
  const allModules = [...state.modules.values()];
  
  // Navigation filters
  ['all', 'failed', 'running'].forEach(f => {
    const el = document.getElementById(`filter-${f}`);
    if (el) el.className = `flex items-center gap-md px-lg py-sm transition-all cursor-pointer ${state.selectedFilter === f ? 'bg-white text-blue-600 border-r-4 border-blue-600 shadow-sm' : 'text-slate-500 hover:bg-slate-100 border-r-4 border-transparent'}`;
  });

  // Phases
  const phases = [...state.phases].sort((a, b) => Number(a.replace(/\D/g, '')) - Number(b.replace(/\D/g, '')));
  const html = phases.map(phase => {
    const phaseMods = allModules.filter(m => m.phase === phase);
    const approved = phaseMods.filter(m => m.status === 'approved').length;
    const failed = phaseMods.filter(m => m.status === 'failed').length;
    const total = phaseMods.length;
    
    let badgeClass = 'text-slate-400 bg-slate-100';
    if (total > 0 && approved === total) badgeClass = 'text-green-600 bg-green-50 border border-green-200';
    if (failed > 0) badgeClass = 'text-error bg-error-container border border-error/20';

    const isActive = state.selectedFilter === phase;
    const activeClasses = isActive ? 'bg-white text-blue-600 border-r-4 border-blue-600 shadow-sm' : 'text-slate-500 hover:bg-slate-100 border-r-4 border-transparent';
    return `<a class="flex items-center justify-between gap-md px-lg py-sm transition-all cursor-pointer ${activeClasses}" onclick="setFilter('${phase}')">
      <div class="flex items-center gap-2"><span class="material-symbols-outlined text-[18px]">folder_open</span><span>${phase}</span></div>
      <span class="px-2 py-0.5 rounded-md text-[10px] ${badgeClass}">${approved}/${total}</span>
    </a>`;
  }).join('');
  
  els.phaseSidebar.innerHTML = html;
  
  // Status Overview
  const tDone = state.stats.approved || 0;
  const tFail = state.stats.failed || 0;
  const tRun = state.stats.running || 0;
  els.sidebarStatus.textContent = `${tDone} approved · ${tFail} failed · ${tRun} running`;
  els.sidebarStatus.className = `font-mono-label text-mono-label mt-xs ${tFail > 0 ? 'text-error' : 'text-green-600'}`;

  // Main subtitle
  let sub = 'All phases';
  if (state.selectedFilter === 'failed') sub = 'Failed modules only';
  else if (state.selectedFilter === 'running') sub = 'Running modules only';
  else if (state.selectedFilter !== 'all') sub = `${state.selectedFilter} active module board`;
  els.phaseSubtitle.textContent = sub;
}

function renderModules() {
  if (state.currentTab !== 'modules') return;
  const modules = [...state.modules.values()]
    .filter(mod => {
      if (state.selectedFilter === 'all') return true;
      if (state.selectedFilter === 'failed') return mod.status === 'failed';
      if (state.selectedFilter === 'running') return mod.status === 'running';
      return mod.phase === state.selectedFilter;
    })
    .sort((a, b) => {
      // Sort running first, then failed, then by phase, then alphabetical
      if (a.status === 'running' && b.status !== 'running') return -1;
      if (b.status === 'running' && a.status !== 'running') return 1;
      if (a.status === 'failed' && b.status !== 'failed') return -1;
      if (b.status === 'failed' && a.status !== 'failed') return 1;
      const pa = Number(a.phase.replace(/\D/g, '')) || 999;
      const pb = Number(b.phase.replace(/\D/g, '')) || 999;
      return pa - pb || a.label.localeCompare(b.label);
    });

  if (!modules.length) {
    els.moduleList.innerHTML = '<div class="text-on-surface-variant p-lg border border-outline-variant border-dashed rounded-xl text-center">No modules found for this filter.</div>';
    return;
  }

  els.moduleList.innerHTML = modules.map(mod => {
    let cardClasses = 'bg-surface-container-lowest border-outline-variant hover:shadow-sm';
    let iconClass = 'bg-surface-container text-primary border-outline-variant/50';
    let iconName = 'schema';
    let pillClasses = 'bg-surface-container-high text-on-surface';
    let bottomBorder = '';
    
    if (mod.status === 'running') {
      cardClasses = 'bg-surface-container-lowest border-blue-300 hover:shadow-md';
      iconClass = 'bg-blue-50 text-blue-600 border-blue-200';
      iconName = 'autorenew';
      pillClasses = 'bg-blue-100 text-blue-700 border border-blue-200';
      bottomBorder = '<div class="absolute bottom-0 left-0 h-1 w-full bg-gradient-to-r from-blue-500 via-cyan-400 to-blue-500 opacity-90" style="background-size: 200% 100%; animation: sweep 2s linear infinite;"></div>';
    } else if (mod.status === 'failed') {
      cardClasses = 'bg-error-container/20 border-error/40 hover:shadow-sm';
      iconClass = 'bg-error-container text-error border-error/20';
      iconName = 'error';
      pillClasses = 'bg-error-container text-on-error-container border border-error/20';
    } else if (mod.status === 'approved') {
      iconClass = 'bg-green-50 text-green-600 border-green-200';
      iconName = 'check_circle';
      pillClasses = 'bg-green-50 text-green-700 border border-green-200';
    }

    return `
    <div class="border rounded-xl p-lg relative overflow-hidden group transition-all duration-200 ${cardClasses}">
      ${bottomBorder}
      <div class="flex justify-between items-start mb-md">
        <div class="flex items-center gap-md">
          <div class="w-12 h-12 rounded-lg flex items-center justify-center border ${iconClass}">
            <span class="material-symbols-outlined" style="font-variation-settings: 'FILL' 1;">${iconName}</span>
          </div>
          <div>
            <h3 class="font-h3 text-h3 text-on-surface">${mod.label}</h3>
            <div class="flex items-center gap-sm mt-xs">
              <span class="font-mono-code text-mono-code text-on-surface-variant">ID: ${mod.id}</span>
              <span class="text-outline-variant">•</span>
              <span class="font-mono-code text-mono-code text-on-surface-variant">${mod.phase}</span>
            </div>
          </div>
        </div>
        <div class="flex flex-col items-end gap-1">
          <div class="px-sm py-xs rounded-full font-mono-label text-mono-label ${pillClasses}">
            ${mod.status.toUpperCase()}
          </div>
          ${mod.score !== null ? `<div class="px-2 py-0.5 rounded border border-outline-variant/50 text-[10px] font-mono-label text-slate-500 bg-surface-container">Score: ${mod.score}/100</div>` : ''}
          ${mod.iteration ? `<div class="text-[10px] font-mono-label text-amber-600">Iter: ${mod.iteration}</div>` : ''}
        </div>
      </div>
      
      ${mod.lastMessage ? `
      <div class="bg-surface-container-low p-md rounded-lg border border-outline-variant/30 mb-md ${mod.status === 'failed' ? 'bg-error-container/30 border-error/20' : ''}">
        <p class="font-mono-code text-mono-code break-words ${mod.status === 'failed' ? 'text-on-error-container' : 'text-on-surface'}">${escapeHtml(mod.lastMessage)}</p>
      </div>` : ''}

      ${mod.errorDetail && mod.errorDetail.length > 0 && mod.status === 'failed' ? `
      <div class="bg-error-container/50 p-md rounded-lg border border-error/30 mb-md font-mono-code text-[11px] text-error">
        ${mod.errorDetail.map(e => `<div>• ${escapeHtml(e)}</div>`).join('')}
      </div>` : ''}
      
      <div class="flex items-center justify-between gap-md mt-4">
        <div class="flex-1 flex gap-xs items-center h-2">
          ${renderMiniTimeline(mod.status)}
        </div>
        <button onclick="els.logSearch.value='${mod.id}'; switchTab('log');" class="text-xs text-blue-600 hover:text-blue-800 font-medium px-2 py-1 bg-blue-50 rounded border border-blue-200 shrink-0">View Log</button>
      </div>
    </div>
    `;
  }).join('');
}

function renderMiniTimeline(status) {
  let capsules = [];
  const color = status === 'failed' ? 'bg-error' : (status === 'running' ? 'bg-blue-500' : (status === 'approved' ? 'bg-green-500' : 'bg-primary'));
  const count = status === 'approved' ? 10 : (status === 'running' ? 6 : (status === 'failed' ? 8 : 2));
  
  for(let i=0; i<10; i++) {
    const opacity = i < count ? 'opacity-100' : (i === count ? 'opacity-40' : 'bg-surface-container-high opacity-100');
    const cl = i < count ? color : (i === count ? color : 'bg-surface-container-high');
    capsules.push(`<div class="h-full flex-1 rounded-full ${cl} ${opacity}"></div>`);
  }
  return capsules.join('');
}

function renderStats() {
  if (state.currentTab !== 'modules') return;
  const modules = [...state.modules.values()];
  const total = modules.length;
  const done = modules.filter(m => m.status === 'approved').length;
  const failed = modules.filter(m => m.status === 'failed').length;
  const pct = total > 0 ? Math.round((done / total) * 100) : 0;

  els.statsPct.textContent = pct;
  els.statsRatio.textContent = `${done} / ${total}`;
  els.statsBar.style.width = `${pct}%`;
  els.statsFailedCount.textContent = failed;
  els.globalProgressBar.style.width = `${pct}%`;
  
  const failedList = modules.filter(m => m.status === 'failed');
  if (failedList.length > 0) {
    els.statsFailedList.innerHTML = failedList.map(m => `<a href="#" onclick="els.logSearch.value='${m.id}'; switchTab('log');" class="hover:underline hover:text-red-700 block truncate cursor-pointer py-1 border-b border-error/10 last:border-0">• ${m.label} <span class="text-[10px] text-error/60">(${m.phase})</span></a>`).join('');
  } else {
    els.statsFailedList.innerHTML = '<span class="text-slate-400">All clear</span>';
  }

  if (state.buildComplete) {
    els.completeBanner.classList.remove('hidden');
    els.completeBannerText.textContent = `The autonomous builder has stopped. ${done} modules approved, ${failed} failed.`;
  } else {
    els.completeBanner.classList.add('hidden');
  }
}

function renderFeed() {
  if (state.currentTab !== 'modules') return;
  els.chatFeed.innerHTML = '';
  const snippetLogs = state.logs.slice(-50); // Show last 50
  
  snippetLogs.forEach(entry => {
    const row = document.createElement('div');
    row.className = 'flex gap-sm border-b border-outline-variant/10 pb-2 mb-2 last:border-0 last:pb-0 last:mb-0';
    
    let levelClass = 'text-primary font-medium shrink-0';
    if (entry.level === 'WARN') levelClass = 'text-amber-600 font-medium shrink-0';
    if (entry.level === 'ERROR') levelClass = 'text-error font-medium shrink-0';
    if (entry.level === 'INFO' && !entry.model) levelClass = 'text-slate-500 shrink-0';
    
    let displayMsg = escapeHtml(entry.message);
    if (entry.model) {
      const color = entry.model === 'gemini' ? 'violet-600' : (entry.model === 'claude' ? 'amber-600' : 'blue-600');
      displayMsg = `<span class="text-${color} font-bold mr-1">[${entry.model.toUpperCase()}]</span> ${displayMsg}`;
    }

    row.innerHTML = `
      <span class="text-outline shrink-0">[${entry.timestamp.split(' ')[1] || entry.timestamp}]</span>
      <span class="${levelClass}">[${entry.level}]</span>
      <span class="text-on-surface-variant break-words flex-1">${displayMsg}</span>
    `;
    els.chatFeed.appendChild(row);
  });
  scrollToBottom('chatFeed');
}

function renderFullLog() {
  if (state.currentTab !== 'log') return;
  const term = els.logSearch.value.toLowerCase();
  
  let html = '';
  // Optimization: render last 2000 lines if no search, otherwise all matching
  const linesToRender = term ? state.logs : state.logs.slice(-2000);
  
  linesToRender.forEach(entry => {
    const rawLine = `[${entry.timestamp}] [${entry.level}] ${entry.message}`;
    if (term && !rawLine.toLowerCase().includes(term)) return;
    
    let color = 'text-slate-700';
    if (entry.level === 'WARN') color = 'text-amber-700 bg-amber-50';
    if (entry.level === 'ERROR') color = 'text-error bg-error-container/30 border-l-2 border-error font-bold';
    
    html += `<div class="px-2 py-1 ${color}">${escapeHtml(rawLine)}</div>`;
  });
  
  const isAtBottom = els.fullLogContainer.scrollHeight - els.fullLogContainer.scrollTop <= els.fullLogContainer.clientHeight + 50;
  els.fullLogContainer.innerHTML = html;
  if (isAtBottom || !state.isLoaded) scrollToBottom('fullLogContainer');
}

els.fullLogContainer.addEventListener('scroll', () => {
  const isAtBottom = els.fullLogContainer.scrollHeight - els.fullLogContainer.scrollTop <= els.fullLogContainer.clientHeight + 50;
  state.isAtBottomLog = isAtBottom;
});

function scrollToBottom(id) {
  const el = document.getElementById(id);
  if (el) el.scrollTop = el.scrollHeight;
}

function renderAll() {
  renderSidebar();
  renderModules();
  renderStats();
  renderFeed();
  if (state.currentTab === 'log') renderFullLog();
}

function escapeHtml(value) {
  return String(value || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// --- File Tree Logic ---
function fetchTree() {
  fetch('/tree').then(r => r.json()).then(data => {
    els.fileTreeContainer.innerHTML = renderTreeNodes(data, '');
  }).catch(e => {
    els.fileTreeContainer.innerHTML = '<span class="text-error">Failed to load tree.</span>';
  });
}

function renderTreeNodes(nodes, indent) {
  return nodes.map(node => {
    if (node.type === 'dir') {
      return `
        <div class="mt-1">
          <div class="flex items-center gap-2 cursor-pointer hover:bg-surface-container-low px-1 rounded text-slate-700 font-medium select-none" onclick="this.nextElementSibling.classList.toggle('hidden')">
            <span class="text-slate-400 select-none font-sans">${indent}</span>
            <span class="material-symbols-outlined text-[16px] text-blue-500">folder</span>
            ${escapeHtml(node.name)}
          </div>
          <div class="hidden ml-1 border-l border-outline-variant/30">${renderTreeNodes(node.children, indent + '&nbsp;&nbsp;')}</div>
        </div>
      `;
    } else {
      return `
        <div class="flex items-center gap-2 cursor-pointer hover:bg-surface-container-low px-1 rounded text-slate-600 mt-1 select-none" onclick="viewFile('${escapeHtml(node.path).replace(/\\/g,'\\\\')}')">
          <span class="text-slate-400 select-none font-sans">${indent}</span>
          <span class="material-symbols-outlined text-[16px] text-slate-400">description</span>
          ${escapeHtml(node.name)}
        </div>
      `;
    }
  }).join('');
}

function viewFile(path) {
  els.fileViewerPath.textContent = path;
  els.fileViewerContent.textContent = 'Loading...';
  fetch(`/file?path=${encodeURIComponent(path)}`).then(r => {
    if (!r.ok) throw new Error('File not found or unreadable');
    return r.text();
  }).then(content => {
    els.fileViewerContent.textContent = content;
  }).catch(e => {
    els.fileViewerContent.textContent = `Error: ${e.message}`;
  });
}

// --- Event Streams ---
function connectEvents() {
  const es = new EventSource('/events');
  es.onmessage = event => {
    const payload = JSON.parse(event.data);
    if (payload.type === 'log') {
      state.logs.push(payload.data);
      if (state.logs.length > 5000) state.logs.shift(); // Keep last 5000 lines
      applyLog(payload.data);
      renderAll();
    }
    if (payload.type === 'state') {
      // Seed missing modules from state json directly to state.modules
      (payload.data.completed || []).forEach(id => {
        const mod = ensureModule(id);
        if (mod.status !== 'running') mod.status = 'approved';
      });
      (payload.data.failed || []).forEach(id => {
        const mod = ensureModule(id);
        if (mod.status !== 'running' && mod.status !== 'approved') mod.status = 'failed';
      });
      renderAll();
    }
    if (payload.type === 'build_complete') {
      state.buildComplete = true;
      fetchStats();
    }
  };
}

setInterval(fetchStats, 2000);
fetchStats();
connectEvents();
state.isLoaded = true;

