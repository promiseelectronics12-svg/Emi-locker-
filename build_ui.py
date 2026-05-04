import os

html_content = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta content="width=device-width, initial-scale=1.0" name="viewport"/>
<title>EMI Monitor - Autonomous Builder</title>
<!-- Tailwind CSS -->
<script src="https://cdn.tailwindcss.com?plugins=forms,container-queries"></script>
<!-- Google Fonts & Material Symbols -->
<link href="https://fonts.googleapis.com" rel="preconnect"/>
<link crossorigin="" href="https://fonts.gstatic.com" rel="preconnect"/>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet"/>
<link href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:wght,FILL@100..700,0..1&display=swap" rel="stylesheet"/>
<script>
  tailwind.config = {
    theme: {
      extend: {
        colors: {
          emerald: { 50: '#ecfdf5', 100: '#d1fae5', 400: '#34d399', 500: '#10b981', 600: '#059669', 700: '#047857' },
          slate: { 50: '#f8fafc', 100: '#f1f5f9', 200: '#e2e8f0', 800: '#1e293b', 900: '#0f172a' }
        },
        fontFamily: {
          sans: ['Inter', 'sans-serif'],
          mono: ['JetBrains Mono', 'monospace'],
        }
      }
    }
  }
</script>
<style>
  @keyframes pulse-ring { 0% { transform: scale(0.8); opacity: 0.5; } 100% { transform: scale(1.3); opacity: 0; } }
  .pulse-dot { position: relative; }
  .pulse-dot::before { content: ''; position: absolute; left: -4px; top: -4px; right: -4px; bottom: -4px; border-radius: 50%; border: 2px solid currentColor; animation: pulse-ring 2s cubic-bezier(0.215, 0.61, 0.355, 1) infinite; }
  @keyframes sweep { 0% { background-position: 100% 0; } 100% { background-position: -100% 0; } }
  .bg-sweep { background-size: 200% 100%; animation: sweep 2s linear infinite; }
  .scrollbar-hide::-webkit-scrollbar { display: none; }
  .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
  /* Worker Selection Highlight */
  .worker-card { transition: all 0.2s ease; cursor: pointer; border: 2px solid transparent; }
  .worker-card:hover { transform: translateY(-2px); box-shadow: 0 10px 15px -3px rgba(0,0,0,0.05); }
  .worker-card.selected { border-color: #10b981; box-shadow: 0 0 0 4px rgba(16, 185, 129, 0.1); }
</style>
</head>
<body class="bg-slate-50 text-slate-900 font-sans h-screen flex flex-col overflow-hidden">

<!-- TOP BANNER -->
<header class="bg-white border-b border-slate-200 shrink-0 h-16 flex items-center justify-between px-6 z-10 shadow-sm">
  <div class="flex items-center gap-4">
    <div class="w-8 h-8 bg-emerald-500 rounded flex items-center justify-center text-white shadow-sm">
      <span class="material-symbols-outlined text-[20px]">precision_manufacturing</span>
    </div>
    <div>
      <h1 class="font-bold text-lg leading-tight tracking-tight">EMI Locker</h1>
      <div class="text-xs text-slate-500 font-medium font-mono uppercase tracking-widest">Autonomous Builder</div>
    </div>
  </div>
  
  <div class="flex items-center gap-6">
    <div class="flex items-center gap-2 text-slate-600 font-mono text-sm">
      <span class="material-symbols-outlined text-[18px]">timer</span>
      <span id="elapsedTime">00:00:00</span>
    </div>
    
    <!-- SYSTEM STATUS BADGE -->
    <div id="systemStatusBadge" class="flex items-center gap-3 px-4 py-1.5 rounded-full bg-slate-100 border border-slate-200 text-slate-600 font-bold text-sm tracking-wide">
      <div class="w-2 h-2 rounded-full bg-slate-400"></div>
      <span id="systemStatusText">CONNECTING...</span>
    </div>
    
    <button onclick="document.getElementById('controlModal').classList.remove('hidden')" class="w-9 h-9 flex items-center justify-center rounded-full hover:bg-slate-100 transition-colors text-slate-500 border border-transparent hover:border-slate-200">
      <span class="material-symbols-outlined text-[20px]">settings</span>
    </button>
  </div>
</header>

<div class="flex-1 flex flex-col p-6 gap-6 min-h-0 overflow-hidden max-w-[1600px] mx-auto w-full">

  <!-- AI WORKERS ROW (BENTO TOP) -->
  <div class="shrink-0">
    <div class="flex justify-between items-end mb-3">
      <h2 class="font-bold text-slate-800 text-sm tracking-wide uppercase">Live Worker Telemetry</h2>
      <div class="text-xs text-slate-500 flex items-center gap-1 bg-white px-2 py-1 rounded border border-slate-200 cursor-pointer hover:bg-slate-50 transition-colors" onclick="setTerminalFilter('all')">
        <span class="material-symbols-outlined text-[14px]">filter_list_off</span> Clear Filter
      </div>
    </div>
    
    <div class="grid grid-cols-1 md:grid-cols-4 gap-4" id="workersGrid">
      <!-- Worker cards injected here by JS -->
    </div>
  </div>

  <!-- MAIN SPLIT (BENTO BOTTOM) -->
  <div class="flex-1 flex gap-6 min-h-0">
    
    <!-- LEFT: MODULES & STATS (2/3 width) -->
    <div class="flex-1 flex flex-col gap-6 min-h-0 min-w-0 w-2/3">
      
      <!-- Stats Summary Card -->
      <div class="bg-white rounded-2xl border border-slate-200 p-5 shrink-0 shadow-sm flex items-center justify-between">
        <div class="flex items-center gap-8 w-2/3">
          <div>
            <div class="text-4xl font-black text-slate-900 tracking-tighter" id="statsPct">0%</div>
            <div class="text-xs text-slate-500 font-bold uppercase tracking-wider mt-1">Total Progress</div>
          </div>
          <div class="flex-1">
            <div class="flex justify-between text-sm font-semibold mb-2">
              <span class="text-slate-700" id="statsRatio">0 / 23 Approved</span>
              <span class="text-red-600" id="statsFailedCount">0 Failed</span>
            </div>
            <div class="h-2.5 w-full bg-slate-100 rounded-full overflow-hidden border border-slate-200/50">
              <div class="h-full bg-emerald-500 transition-all duration-700 ease-out" id="statsBar" style="width: 0%"></div>
            </div>
          </div>
        </div>
        <div class="w-1/3 pl-8 border-l border-slate-100 flex flex-col gap-2">
           <div class="text-xs font-bold text-slate-400 uppercase tracking-wider">Phase Filter</div>
           <select id="phaseSelector" onchange="setPhaseFilter(this.value)" class="w-full text-sm border border-slate-200 rounded-lg p-2 focus:ring-2 focus:ring-emerald-500 outline-none text-slate-700 bg-slate-50 cursor-pointer font-medium">
             <option value="all">All Phases</option>
             <!-- Phases injected here -->
           </select>
        </div>
      </div>

      <!-- Module Grid -->
      <div class="bg-white rounded-2xl border border-slate-200 flex-1 flex flex-col min-h-0 shadow-sm overflow-hidden">
        <div class="px-5 py-3 border-b border-slate-100 bg-slate-50/50 flex justify-between items-center shrink-0">
          <h3 class="font-bold text-slate-800 flex items-center gap-2"><span class="material-symbols-outlined text-[18px] text-emerald-600">view_cozy</span> Module Board</h3>
        </div>
        <div class="flex-1 overflow-y-auto p-5 scrollbar-hide bg-slate-50/30">
          <div class="grid grid-cols-1 xl:grid-cols-2 gap-4" id="moduleList">
            <!-- Module cards injected here -->
          </div>
        </div>
      </div>

    </div>

    <!-- RIGHT: TERMINAL FEED (1/3 width) -->
    <div class="w-1/3 flex flex-col bg-white rounded-2xl border border-slate-200 shadow-sm min-h-0 overflow-hidden shrink-0">
      <div class="px-5 py-3 border-b border-slate-100 bg-slate-50/80 flex justify-between items-center shrink-0">
        <div class="flex items-center gap-2">
          <span class="material-symbols-outlined text-[18px] text-slate-400">terminal</span>
          <h3 class="font-bold text-slate-800 text-sm">Live Terminal</h3>
          <span id="terminalFilterBadge" class="hidden ml-2 px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider bg-emerald-100 text-emerald-700 border border-emerald-200"></span>
        </div>
        <button onclick="document.getElementById('fullLogModal').classList.remove('hidden'); renderFullLog();" class="text-xs font-semibold text-slate-500 hover:text-emerald-600 transition-colors flex items-center gap-1 bg-white border border-slate-200 px-2 py-1 rounded">
          <span class="material-symbols-outlined text-[14px]">open_in_new</span> Full Log
        </button>
      </div>
      <div class="flex-1 overflow-y-auto p-4 font-mono text-[11px] leading-relaxed text-slate-600 bg-[#fafafa]" id="chatFeed">
        <!-- Logs injected here -->
      </div>
    </div>

  </div>
</div>

<!-- Modals -->
<!-- Full Log Modal -->
<div id="fullLogModal" class="fixed inset-0 z-[100] bg-slate-900/60 backdrop-blur-sm hidden items-center justify-center p-8">
  <div class="bg-white rounded-2xl shadow-2xl w-full h-full max-w-[1400px] flex flex-col overflow-hidden border border-slate-200">
    <div class="p-4 border-b border-slate-200 flex justify-between items-center bg-slate-50">
      <div class="flex items-center gap-3">
        <span class="material-symbols-outlined text-slate-500">list_alt</span>
        <h2 class="font-bold text-lg text-slate-800">Complete Log Output</h2>
      </div>
      <div class="flex gap-3">
        <input type="text" id="logSearch" placeholder="Filter logs..." class="px-3 py-1.5 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-emerald-500 outline-none w-64" oninput="renderFullLog()">
        <button onclick="document.getElementById('fullLogModal').classList.add('hidden')" class="w-8 h-8 flex justify-center items-center rounded hover:bg-slate-200 text-slate-500 transition-colors"><span class="material-symbols-outlined">close</span></button>
      </div>
    </div>
    <div class="flex-1 overflow-y-auto p-4 font-mono text-[12px] bg-[#fafafa]" id="fullLogContainer"></div>
  </div>
</div>

<!-- Control Panel Modal (Simplified) -->
<div id="controlModal" class="fixed inset-0 z-[100] bg-slate-900/60 backdrop-blur-sm hidden items-center justify-center">
  <div class="bg-white rounded-2xl shadow-2xl border border-slate-200 w-[400px] flex flex-col overflow-hidden">
    <div class="p-5 border-b border-slate-100 flex justify-between items-center bg-slate-50">
      <h2 class="font-bold text-slate-900">Process Control</h2>
      <button onclick="document.getElementById('controlModal').classList.add('hidden')" class="text-slate-400 hover:text-slate-600"><span class="material-symbols-outlined">close</span></button>
    </div>
    <div class="p-5 flex flex-col gap-3">
      <button onclick="controlBuilder('start')" class="w-full bg-emerald-600 hover:bg-emerald-700 text-white py-2.5 rounded-lg font-semibold transition-colors flex justify-center items-center gap-2"><span class="material-symbols-outlined text-[18px]">play_arrow</span> Start Builder</button>
      <button onclick="controlBuilder('resume')" class="w-full bg-slate-800 hover:bg-slate-900 text-white py-2.5 rounded-lg font-semibold transition-colors flex justify-center items-center gap-2"><span class="material-symbols-outlined text-[18px]">fast_forward</span> Resume Checkpoint</button>
      <button onclick="controlBuilder('stop')" class="w-full bg-red-100 hover:bg-red-200 text-red-700 py-2.5 rounded-lg font-semibold transition-colors flex justify-center items-center gap-2 mt-4"><span class="material-symbols-outlined text-[18px]">stop</span> Force Stop</button>
      <p id="controlFeedback" class="text-xs text-center font-mono mt-2 hidden"></p>
    </div>
  </div>
</div>

<script>
// Data Structures
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
  selectedPhase: 'all',
  terminalFilter: 'all', // 'all', 'minimax', 'gemma', 'gemini', 'claude'
  stats: { approved: 0, failed: 0, running: 0, builderActive: false },
  buildComplete: false,
  workers: {
    minimax: { id: 'minimax', name: 'MiniMax M2.7', role: 'Worker 1 (Primary)', status: 'idle', module: null, lastLog: 'Waiting...' },
    gemma: { id: 'gemma', name: 'Gemma 4 31B', role: 'Worker 2 (Fallback)', status: 'idle', module: null, lastLog: 'Waiting...' },
    gemini: { id: 'gemini', name: 'Gemini CLI', role: 'Executor (Review)', status: 'idle', module: null, lastLog: 'Waiting...' },
    claude: { id: 'claude', name: 'Claude/Codex', role: 'Supervisor (Tier 4)', status: 'idle', module: null, lastLog: 'Waiting...' }
  }
};

// Initialization
Object.keys(MODULE_PHASE_MAP).forEach(id => {
  state.phases.add(MODULE_PHASE_MAP[id]);
  state.modules.set(id, {
    id, label: id.split('-').map(p=>p.charAt(0).toUpperCase()+p.slice(1)).join(' '),
    phase: MODULE_PHASE_MAP[id], status: 'pending', logs: [], errorDetail: []
  });
});

// Parsers
function parseModuleFromMessage(message) {
  const m = message.match(/^\\[([a-z][a-z0-9-]+)\\]/i) || message.match(/issue\\(s\\) in ([\\w-]+)/i) || message.match(/MODULE:\\s*([\\w-]+)|Implementing\\s+([\\w-]+)|Reviewing\\s+([\\w-]+)|APPROVED:\\s*([\\w-]+)|NEEDS WORK:\\s*([\\w-]+)|Skipping\\s+([\\w-]+)|FAILED.*?([\\w-]+)/i);
  return m ? (m[1] || m[2] || m[3] || m[4] || m[5] || m[6] || m[7]) : null;
}

function applyLog(entry) {
  const message = entry.message || '';
  const moduleId = entry.module || parseModuleFromMessage(message);
  const action = entry.action;
  
  // 1. Update Module State
  if (moduleId && state.modules.has(moduleId)) {
    const mod = state.modules.get(moduleId);
    mod.logs.push(entry);
    
    if (entry.level === 'ERROR' || message.includes('FAILED') || message.includes('exit code 1') || message.includes('Traceback')) {
      if (!mod.errorDetail.includes(message)) mod.errorDetail.push(message);
    }
    
    if (action === 'implementing' || action === 'fixing' || action === 'reviewing' || action === 're-reviewing') {
      mod.status = 'running';
    } else if (action === 'approved') {
      mod.status = 'approved';
    } else if (action === 'failed' || message.includes('FAILED to implement') || message.includes('ALL TIERS FAILED')) {
      mod.status = 'failed';
    }
  }

  // 2. Update Worker Telemetry
  let workerKey = entry.model;
  if (!workerKey) {
     if (message.includes('WORKER 1')) workerKey = 'minimax';
     else if (message.includes('WORKER 2')) workerKey = 'gemma';
     else if (message.includes('EXECUTOR') || message.includes('gemini-cli')) workerKey = 'gemini';
     else if (message.includes('SUPERVISOR') || message.includes('Claude') || message.includes('Codex')) workerKey = 'claude';
  }

  if (workerKey && state.workers[workerKey]) {
    const w = state.workers[workerKey];
    const cleanMsg = message.replace(/^\\[.*?\\]\\s*/, '').replace(/^(?:AUDIT|WORKER|EXECUTOR)[^:]*:\\s*/i, '');
    w.lastLog = cleanMsg;
    
    if (action === 'implementing' || action === 'fixing' || action === 'reviewing' || action === 're-reviewing' || action === 'analyzing') {
      w.status = 'running';
      if (moduleId) w.module = moduleId;
    } else if (action === 'approved' || action === 'failed' || message.includes('completed') || message.includes('FAILED')) {
      w.status = 'idle';
      w.module = null;
    }
  }
}

// Renderers
function setTerminalFilter(workerId) {
  state.terminalFilter = workerId;
  const badge = document.getElementById('terminalFilterBadge');
  if (workerId === 'all') {
    badge.classList.add('hidden');
  } else {
    badge.classList.remove('hidden');
    badge.textContent = `Filtered: ${state.workers[workerId].name}`;
  }
  renderWorkers();
  renderFeed();
}

function setPhaseFilter(phase) {
  state.selectedPhase = phase;
  renderModules();
}

function renderWorkers() {
  const container = document.getElementById('workersGrid');
  container.innerHTML = Object.values(state.workers).map(w => {
    const isRunning = w.status === 'running';
    const isSelected = state.terminalFilter === w.id;
    
    let borderClass = isSelected ? 'selected' : '';
    let statusUI = isRunning 
      ? `<div class="flex items-center gap-1.5"><div class="w-2 h-2 rounded-full bg-emerald-500 pulse-dot"></div><span class="text-xs font-bold text-emerald-600 uppercase tracking-wider">Active</span></div>`
      : `<div class="flex items-center gap-1.5"><div class="w-2 h-2 rounded-full bg-slate-300"></div><span class="text-xs font-bold text-slate-400 uppercase tracking-wider">Idle</span></div>`;
    
    let moduleUI = (isRunning && w.module) 
      ? `<div class="mt-2 text-xs font-mono bg-emerald-50 text-emerald-700 px-2 py-1 rounded border border-emerald-100 truncate">${w.module}</div>`
      : `<div class="mt-2 text-[10px] text-slate-400 font-mono truncate h-[22px] flex items-center">${w.lastLog || 'Waiting...'}</div>`;

    return `
      <div onclick="setTerminalFilter('${w.id}')" class="worker-card ${borderClass} bg-white rounded-xl border border-slate-200 p-4 shadow-sm flex flex-col h-full">
        <div class="flex justify-between items-start mb-1">
          <h3 class="font-bold text-slate-800 text-sm">${w.name}</h3>
          ${statusUI}
        </div>
        <div class="text-[10px] text-slate-500 font-bold uppercase tracking-wider">${w.role}</div>
        ${moduleUI}
      </div>
    `;
  }).join('');
}

function renderModules() {
  const container = document.getElementById('moduleList');
  const modules = [...state.modules.values()]
    .filter(m => state.selectedPhase === 'all' || m.phase === state.selectedPhase)
    .sort((a, b) => {
      if (a.status === 'running' && b.status !== 'running') return -1;
      if (b.status === 'running' && a.status !== 'running') return 1;
      if (a.status === 'failed' && b.status !== 'failed') return -1;
      if (b.status === 'failed' && a.status !== 'failed') return 1;
      return Number(a.phase.replace(/\\D/g, '')) - Number(b.phase.replace(/\\D/g, ''));
    });

  container.innerHTML = modules.map(m => {
    let style = "bg-white border-slate-200";
    let icon = "schema";
    let iconColor = "text-slate-400 bg-slate-50 border-slate-100";
    let statusText = "PENDING";
    let statusClass = "text-slate-400";
    
    if (m.status === 'running') {
      style = "bg-white border-emerald-200 shadow-md ring-1 ring-emerald-500/20";
      icon = "autorenew";
      iconColor = "text-emerald-600 bg-emerald-50 border-emerald-100";
      statusText = "RUNNING";
      statusClass = "text-emerald-600";
    } else if (m.status === 'approved') {
      icon = "check_circle";
      iconColor = "text-green-600 bg-green-50 border-green-100";
      statusText = "APPROVED";
      statusClass = "text-green-600";
    } else if (m.status === 'failed') {
      style = "bg-red-50/30 border-red-200";
      icon = "error";
      iconColor = "text-red-600 bg-red-50 border-red-100";
      statusText = "FAILED";
      statusClass = "text-red-600";
    }

    const errorView = (m.status === 'failed' && m.errorDetail.length > 0) 
      ? `<div class="mt-3 p-2 bg-red-50 rounded border border-red-100 text-[10px] font-mono text-red-700 max-h-24 overflow-y-auto">${m.errorDetail[m.errorDetail.length-1]}</div>` 
      : '';

    return `
      <div class="rounded-xl border p-4 transition-all duration-200 relative overflow-hidden flex flex-col ${style}">
        ${m.status === 'running' ? '<div class="absolute bottom-0 left-0 w-full h-1 bg-gradient-to-r from-emerald-400 via-teal-300 to-emerald-400 bg-sweep"></div>' : ''}
        <div class="flex items-start gap-3">
          <div class="w-10 h-10 rounded flex justify-center items-center border shrink-0 ${iconColor}">
            <span class="material-symbols-outlined text-[18px]">${icon}</span>
          </div>
          <div class="flex-1 min-w-0">
            <h4 class="font-bold text-slate-800 text-sm truncate">${m.label}</h4>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-[10px] font-mono text-slate-500 bg-slate-100 px-1.5 py-0.5 rounded border border-slate-200">${m.id}</span>
              <span class="text-[10px] font-bold ${statusClass} tracking-wider">${statusText}</span>
            </div>
          </div>
        </div>
        ${errorView}
      </div>
    `;
  }).join('');
}

function renderFeed() {
  const container = document.getElementById('chatFeed');
  let html = '';
  
  // Filter and show last 100
  const filtered = state.logs.filter(entry => {
    if (state.terminalFilter === 'all') return true;
    let wk = entry.model;
    if (!wk) {
       const msg = entry.message || '';
       if (msg.includes('WORKER 1')) wk = 'minimax';
       else if (msg.includes('WORKER 2')) wk = 'gemma';
       else if (msg.includes('EXECUTOR') || msg.includes('gemini-cli')) wk = 'gemini';
       else if (msg.includes('SUPERVISOR') || msg.includes('Claude') || msg.includes('Codex')) wk = 'claude';
    }
    return wk === state.terminalFilter;
  }).slice(-100);

  filtered.forEach(entry => {
    let color = 'text-slate-600';
    if (entry.level === 'WARN') color = 'text-amber-600';
    if (entry.level === 'ERROR') color = 'text-red-600 font-bold';
    
    let prefix = '';
    if (entry.model) {
       const w = state.workers[entry.model];
       if (w) prefix = `<span class="text-emerald-600 font-bold">[${w.name}]</span> `;
    }

    html += `<div class="mb-1.5 ${color}"><span class="text-slate-400 select-none mr-2">[${entry.timestamp.split(' ')[1] || entry.timestamp}]</span>${prefix}${escapeHtml(entry.message)}</div>`;
  });

  const isAtBottom = container.scrollHeight - container.scrollTop <= container.clientHeight + 20;
  container.innerHTML = html;
  if (isAtBottom || !state.feedInitialized) {
     container.scrollTop = container.scrollHeight;
     state.feedInitialized = true;
  }
}

function renderStats() {
  const total = Object.keys(MODULE_PHASE_MAP).length;
  const done = state.stats.approved || 0;
  const failed = state.stats.failed || 0;
  const pct = total > 0 ? Math.round((done / total) * 100) : 0;

  document.getElementById('statsPct').textContent = pct + '%';
  document.getElementById('statsRatio').textContent = `${done} / ${total} Approved`;
  document.getElementById('statsFailedCount').textContent = `${failed} Failed`;
  document.getElementById('statsBar').style.width = pct + '%';
  
  // System Banner
  const badge = document.getElementById('systemStatusBadge');
  const text = document.getElementById('systemStatusText');
  const dot = badge.querySelector('div');
  
  if (state.stats.builderActive || state.stats.running > 0) {
    badge.className = "flex items-center gap-2 px-4 py-1.5 rounded-full bg-emerald-50 border border-emerald-200 text-emerald-700 font-bold text-sm tracking-wide shadow-sm";
    dot.className = "w-2.5 h-2.5 rounded-full bg-emerald-500 pulse-dot";
    text.textContent = "BUILDER ACTIVE";
  } else {
    badge.className = "flex items-center gap-2 px-4 py-1.5 rounded-full bg-red-50 border border-red-200 text-red-700 font-bold text-sm tracking-wide shadow-sm";
    dot.className = "w-2.5 h-2.5 rounded-full bg-red-500";
    text.textContent = "BUILDER OFFLINE";
  }

  // Phase dropdown options
  if (document.getElementById('phaseSelector').options.length === 1) {
    const sel = document.getElementById('phaseSelector');
    [...state.phases].sort((a,b)=>Number(a.replace(/\\D/g,''))-Number(b.replace(/\\D/g,''))).forEach(p => {
      const opt = document.createElement('option');
      opt.value = p; opt.textContent = p; sel.appendChild(opt);
    });
  }
}

function renderFullLog() {
  const c = document.getElementById('fullLogContainer');
  const term = document.getElementById('logSearch').value.toLowerCase();
  const lines = term ? state.logs : state.logs.slice(-2000);
  
  let html = '';
  lines.forEach(entry => {
    const str = `[${entry.timestamp}] [${entry.level}] ${entry.message}`;
    if (term && !str.toLowerCase().includes(term)) return;
    let cl = 'text-slate-700';
    if(entry.level==='WARN') cl='text-amber-700 bg-amber-50';
    if(entry.level==='ERROR') cl='text-red-700 bg-red-50 font-bold border-l-2 border-red-500 pl-2';
    html += `<div class="py-0.5 ${cl}">${escapeHtml(str)}</div>`;
  });
  c.innerHTML = html;
  c.scrollTop = c.scrollHeight;
}

function escapeHtml(v) { return String(v||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

function fetchStats() {
  fetch('/api/stats').then(r=>r.json()).then(data => {
    state.stats = data;
    const h = Math.floor(data.elapsedSeconds / 3600).toString().padStart(2, '0');
    const m = Math.floor((data.elapsedSeconds % 3600) / 60).toString().padStart(2, '0');
    const s = (data.elapsedSeconds % 60).toString().padStart(2, '0');
    document.getElementById('elapsedTime').textContent = `${h}:${m}:${s}`;
    
    // Auto-update modules from stats if missed by logs
    if (data.completed) data.completed.forEach(id => { if (state.modules.has(id) && state.modules.get(id).status!=='running') state.modules.get(id).status='approved'; });
    if (data.failed) data.failed.forEach(id => { if (state.modules.has(id) && state.modules.get(id).status!=='running' && state.modules.get(id).status!=='approved') state.modules.get(id).status='failed'; });
    
    renderStats();
    renderModules();
  }).catch(console.error);
}

function connectEvents() {
  const es = new EventSource('/events');
  es.onmessage = e => {
    const p = JSON.parse(e.data);
    if (p.type === 'log') {
      state.logs.push(p.data);
      if (state.logs.length > 5000) state.logs.shift();
      applyLog(p.data);
      renderWorkers();
      renderModules();
      renderFeed();
    }
    if (p.type === 'state') fetchStats();
  };
}

function controlBuilder(action) {
  const fb = document.getElementById('controlFeedback');
  fb.textContent = `Sending ${action}...`; fb.className="text-xs text-center font-mono mt-2 text-slate-600 block";
  fetch('/api/control', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({action}) })
    .then(r=>r.json()).then(res => {
      fb.textContent = res.error ? `Error: ${res.error}` : `Success: ${res.message}`;
      fb.className = res.error ? "text-xs text-center font-mono mt-2 text-red-600 block" : "text-xs text-center font-mono mt-2 text-emerald-600 block";
      setTimeout(()=>fb.classList.add('hidden'), 3000);
      fetchStats();
    });
}

// Boot
renderWorkers();
setInterval(fetchStats, 2000);
fetchStats();
connectEvents();
</script>
</body>
</html>
"""

with open("D:\\EMI APP\\monitor\\public\\index.html", "w", encoding="utf-8") as f:
    f.write(html_content)
