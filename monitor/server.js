'use strict';
const express = require('express');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

// ── Determine if the builder is currently active ───────────────────────────
// Strategy: check if build_log.md was modified in the last 5 minutes.
// This is reliable regardless of WMI or execution policy.
function isBuilderProcessAlive() {
  try {
    const logPath = path.join(PROJECT_DIR, 'build_log.md');
    const stat = fs.statSync(logPath);
    const ageMs = Date.now() - stat.mtimeMs;
    return ageMs < 300000; // active if log was written within last 5 minutes
  } catch (_) {
    return false;
  }
}

const app = express();
const PORT = 8080;
const PROJECT_DIR = path.resolve(__dirname, '..');

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── SSE client registry ────────────────────────────────────────────────────
let clients = [];
function broadcast(type, data) {
  const payload = `data: ${JSON.stringify({ type, data })}\n\n`;
  clients.forEach(c => { try { c.res.write(payload); } catch (_) {} });
}

// ── SSE Chat Registry ──────────────────────────────────────────────────────
let chatClients = [];
function broadcastChat(role, message, type = 'chunk') {
  const payload = `data: ${JSON.stringify({ role, message, type })}\n\n`;
  chatClients.forEach(c => { try { c.res.write(payload); } catch (_) {} });
}

app.get('/chat-stream', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.flushHeaders();

  const client = { res, id: Date.now() };
  chatClients.push(client);
  req.on('close', () => { chatClients = chatClients.filter(c => c.id !== client.id); });
});

app.get('/api/stats', (req, res) => {
  try {
    const state = JSON.parse(fs.readFileSync(path.join(PROJECT_DIR, 'build_state.json'), 'utf8'));
    let elapsedSeconds = 0;
    if (state.started_at) {
      const end = state.paused_at ? new Date(state.paused_at) : new Date();
      elapsedSeconds = Math.max(0, Math.floor((end - new Date(state.started_at)) / 1000));
    }
    const buildComplete = fs.existsSync(path.join(PROJECT_DIR, 'BUILD_COMPLETE.flag'));
    // Check the actual OS process list — catches externally started builders
    const processAlive = !buildComplete && isBuilderProcessAlive();
    
    res.json({
      approved: (state.completed || []).length,
      failed: (state.failed || []).length,
      running: processAlive ? 1 : 0,
      elapsedSeconds,
      started_at: state.started_at,
      paused_at: state.paused_at,
      builderActive: processAlive,
      note: state.note
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Debug endpoint — exposes what isBuilderProcessAlive sees at runtime
app.get('/api/debug-builder', (req, res) => {
  try {
    const logPath = path.join(PROJECT_DIR, 'build_log.md');
    let mtime = null, ageMs = null, alive = false;
    try {
      const stat = fs.statSync(logPath);
      mtime = stat.mtime.toISOString();
      ageMs = Date.now() - stat.mtimeMs;
      alive = ageMs < 300000;
    } catch(e) {}
    res.json({ logPath, mtime, ageMs, alive, builderActive: isBuilderProcessAlive() });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

// ── Human Intervention Endpoints ───────────────────────────────────────────

app.get('/api/intervention-status', (req, res) => {
  try {
    const reqPath = path.join(PROJECT_DIR, 'review_request.json');
    if (fs.existsSync(reqPath)) {
      const stat = fs.statSync(reqPath);
      const ageSecs = Math.floor((Date.now() - stat.mtimeMs) / 1000);
      const raw = fs.readFileSync(reqPath, 'utf8');
      const data = JSON.parse(raw);
      return res.json({ active: true, ageSecs, module: data.module, instruction: data.instruction });
    }
    res.json({ active: false });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/supervisor-review', (req, res) => {
  try {
    const { status, score, issues } = req.body;
    const resPath = path.join(PROJECT_DIR, 'review_response.json');
    fs.writeFileSync(resPath, JSON.stringify({ status, score, issues }, null, 2), 'utf8');
    res.json({ success: true, message: 'Review submitted successfully.' });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/api/executor-override', (req, res) => {
  try {
    const { module, model } = req.body;
    const overridePath = path.join(PROJECT_DIR, 'executor_override.json');
    fs.writeFileSync(overridePath, JSON.stringify({ module, model, timestamp: new Date().toISOString() }), 'utf8');
    res.json({ success: true, message: `Rerouted module to ${model}` });
  } catch(e) {
    res.status(500).json({ error: e.message });
  }
});

app.get('/events', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.flushHeaders();

  // Send current snapshot immediately on connect
  sendSnapshot(res);

  const client = { res, id: Date.now() };
  clients.push(client);
  req.on('close', () => { clients = clients.filter(c => c.id !== client.id); });
});

// ── Snapshot on new connection ─────────────────────────────────────────────
function sendSnapshot(res) {
  // Send last 80 log lines
  try {
    const log = fs.readFileSync(path.join(PROJECT_DIR, 'build_log.md'), 'utf8');
    const lines = log.split('\n').filter(l => l.trim()).slice(-80);
    lines.forEach(line => {
      const parsed = parseLine(line);
      if (parsed) res.write(`data: ${JSON.stringify({ type: 'log', data: parsed })}\n\n`);
    });
  } catch (_) {}

  // Send current state
  try {
    const state = JSON.parse(fs.readFileSync(path.join(PROJECT_DIR, 'build_state.json'), 'utf8'));
    res.write(`data: ${JSON.stringify({ type: 'state', data: state })}\n\n`);
  } catch (_) {}

  // Send file tree
  res.write(`data: ${JSON.stringify({ type: 'filetree', data: buildFileTree() })}\n\n`);
}

// ── Log line parser with model attribution ─────────────────────────────────
// Real log formats (from autonomous_builder.py):
//   minimax: "[module] WORKER 1 (minimax-coding-plan/MiniMax-M2.7): Implementing..."
//   gemma:   "[module] WORKER 2 (ollama-cloud/gemma4:31b): Implementing..."
//   gemini:  "EXECUTOR (gemini-cli --yolo): Reviewing..."
//   claude:  "Supervisor : Claude (this context window)"  OR  "AUDIT (Claude)..."
const MODEL_PATTERNS = {
  // Gemma MUST come before minimax — both say "Implementing" so we match WORKER 2 first
  gemma:   /WORKER[^:]*\(.*gemma[^)]*\)|WORKER 2\b/i,
  minimax: /WORKER[^:]*\(.*minimax[^)]*\)|WORKER 1\b/i,
  gemini:  /EXECUTOR|Re-review:|PRD analysis|gemini-cli/i,
  // Match "Supervisor : Claude" (startup banner) and "AUDIT (Claude)" (runtime)
  claude:  /Supervisor\s*:\s*Claude|AUDIT\s*\(Claude\)|Claude.*audit|PRIMARY_SUPERVISOR/i,
  codex:   /AUDIT\s*\(Codex\)|Codex.*audit|SUPERVISOR.*Codex|SUPERVISOR_WATCH/i,
  mimo:    /AUDIT\s*\(Mimo\)|Mimo.*audit/i,
};

function detectModel(message) {
  if (MODEL_PATTERNS.mimo.test(message))    return 'mimo';
  if (MODEL_PATTERNS.gemma.test(message))   return 'gemma';    // before minimax
  if (MODEL_PATTERNS.minimax.test(message)) return 'minimax';
  if (MODEL_PATTERNS.gemini.test(message))  return 'gemini';
  if (MODEL_PATTERNS.claude.test(message))  return 'claude';
  if (MODEL_PATTERNS.codex.test(message))   return 'codex';
  return null;
}

function detectAction(message) {
  if (/Implementing/i.test(message))   return 'implementing';
  if (/Reviewing/i.test(message))      return 'reviewing';
  if (/Fix iteration|Fixing/i.test(message)) return 'fixing';
  if (/APPROVED/i.test(message))       return 'approved';
  if (/FAILED|NEEDS WORK|ALL TIERS FAILED/i.test(message)) return 'failed';
  if (/PRD analysis/i.test(message))   return 'analyzing';
  if (/Skipping/i.test(message))       return 'skipping';
  if (/MODULE:|Starting build process/i.test(message)) return 'started';
  if (/BUILD COMPLETE/i.test(message)) return 'complete';
  if (/Re-review/i.test(message))      return 're-reviewing';
  return 'info';
}

function extractModule(message) {
  // New parallel format:  [module-name] TIER 1: ...
  // Old sequential format: WORKER 1 (...): Fixing N issue(s) in module-name
  const newFmt = message.match(/^\[([a-z][a-z0-9-]+)\]/i);
  if (newFmt) return newFmt[1];
  const oldFix = message.match(/issue\(s\) in ([\w-]+)/i);
  if (oldFix) return oldFix[1];
  const m = message.match(/MODULE:\s*([\w-]+)|Implementing\s+([\w-]+)|Reviewing\s+([\w-]+)|APPROVED:\s*([\w-]+)|NEEDS WORK:\s*([\w-]+)|Skipping\s+([\w-]+)/i);
  if (m) return m[1] || m[2] || m[3] || m[4] || m[5] || m[6] || null;
  return null;
}

function extractScore(message) {
  const m = message.match(/score[=:]\s*(\d+)/i);
  return m ? parseInt(m[1]) : null;
}

function parseLine(line) {
  const match = line.match(/^\[([\d\- :]+)\]\s+\[(\w+)\]\s+(.*)/);
  if (!match) return null;
  const message = match[3];
  return {
    timestamp: match[1].trim(),
    level:     match[2],
    message,
    model:     detectModel(message),
    action:    detectAction(message),
    module:    extractModule(message),
    score:     extractScore(message),
  };
}

// ── File tree builder ──────────────────────────────────────────────────────
const IGNORE_DIRS = new Set(['node_modules', 'rtk', '.git', '__pycache__', 'monitor', '.opencode', '.claude']);
const PREVIEW_EXTS = new Set(['.dart', '.kt', '.html', '.tsx', '.jsx', '.js', '.ts', '.css', '.sql', '.json', '.py', '.md']);

function buildFileTree(dir = PROJECT_DIR, depth = 0) {
  if (depth > 10) return [];
  let entries = [];
  try {
    const items = fs.readdirSync(dir);
    for (const item of items) {
      if (item.startsWith('.') && depth === 0) continue;
      if (IGNORE_DIRS.has(item)) continue;
      const full = path.join(dir, item);
      const rel  = path.relative(PROJECT_DIR, full).replace(/\\/g, '/');
      try {
        const stat = fs.statSync(full);
        if (stat.isDirectory()) {
          const children = buildFileTree(full, depth + 1);
          if (children.length > 0) entries.push({ name: item, path: rel, type: 'dir', children });
        } else {
          const ext = path.extname(item).toLowerCase();
          entries.push({ name: item, path: rel, type: 'file', ext, previewable: PREVIEW_EXTS.has(ext), size: stat.size });
        }
      } catch (_) {}
    }
  } catch (_) {}
  return entries;
}

// ── File content endpoint ──────────────────────────────────────────────────
app.get('/file', (req, res) => {
  const rel = req.query.path;
  if (!rel) return res.status(400).send('Missing path');
  const abs = path.resolve(PROJECT_DIR, rel);
  if (!abs.startsWith(PROJECT_DIR)) return res.status(403).send('Forbidden');
  fs.readFile(abs, 'utf8', (err, data) => {
    if (err) return res.status(404).send('Not found');
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.send(data);
  });
});

// ── Builder Configuration & Control ──────────────────────────────────────────
let builderProcess = null;

app.get('/api/config', (req, res) => {
  try {
    const configPath = path.join(PROJECT_DIR, 'builder_config.json');
    if (!fs.existsSync(configPath)) {
      return res.json({
        executor_model: "minimax-coding-plan/MiniMax-M2.7",
        worker_model: "minimax-coding-plan/MiniMax-M2.5"
      });
    }
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    res.json(config);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/config', (req, res) => {
  try {
    const configPath = path.join(PROJECT_DIR, 'builder_config.json');
    const newConfig = req.body;
    fs.writeFileSync(configPath, JSON.stringify(newConfig, null, 2), 'utf8');
    res.json({ success: true, config: newConfig });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/control', (req, res) => {
  const { action } = req.body;
  if (action === 'stop') {
    if (builderProcess) {
      builderProcess.kill();
      builderProcess = null;
      return res.json({ success: true, message: 'Builder stopped' });
    }
    // Also try to kill any dangling python autonomous_builder.py processes
    spawn('powershell.exe', ['-Command', 'Get-CimInstance Win32_Process -Filter "Name=\'python.exe\' AND CommandLine LIKE \'%autonomous_builder.py%\'" | Stop-Process -Force -ErrorAction SilentlyContinue']);
    return res.json({ success: true, message: 'Kill signal sent' });
  }
  
  if (action === 'start' || action === 'resume') {
    if (builderProcess) return res.status(400).json({ error: 'Builder already running' });
    
    let args = ['autonomous_builder.py'];
    if (action === 'resume') {
      try {
        const state = JSON.parse(fs.readFileSync(path.join(PROJECT_DIR, 'build_state.json'), 'utf8'));
        if (state.resume_from) {
          args.push('--start-module', state.resume_from);
        }
      } catch (err) {}
    }
    
    builderProcess = spawn('python', args, { cwd: PROJECT_DIR, detached: true, stdio: 'ignore' });
    builderProcess.unref();
    
    builderProcess.on('exit', () => { builderProcess = null; });
    builderProcess.on('error', () => { builderProcess = null; });
    
    return res.json({ success: true, message: `Builder ${action} triggered` });
  }
  
  res.status(400).json({ error: 'Invalid action' });
});

// ── File tree endpoint ─────────────────────────────────────────────────────
app.get('/tree', (req, res) => {
  const targetDir = req.query.dir ? path.resolve(PROJECT_DIR, req.query.dir) : PROJECT_DIR;
  if (!targetDir.startsWith(PROJECT_DIR)) return res.status(403).send('Forbidden');
  try {
    if (!fs.existsSync(targetDir)) return res.json([]);
    res.json(buildFileTree(targetDir));
  } catch (err) {
    res.json([]);
  }
});

// ── Watchers ───────────────────────────────────────────────────────────────
// Log watcher
let lastLogSize = 0;
try { lastLogSize = fs.statSync(path.join(PROJECT_DIR, 'build_log.md')).size; } catch (_) {}

chokidar.watch(path.join(PROJECT_DIR, 'build_log.md'), { persistent: true })
  .on('change', () => {
    fs.stat(path.join(PROJECT_DIR, 'build_log.md'), (err, stats) => {
      if (err) return;

      // ── Truncation detection (builder restarted & rewrote the log) ──
      // If the file shrank, reset our read cursor and re-broadcast the
      // full snapshot so the live terminal doesn't go silent.
      if (stats.size < lastLogSize) {
        lastLogSize = 0;
        // Re-send full snapshot to every connected SSE client
        clients.forEach(c => { try { sendSnapshot(c.res); } catch (_) {} });
        return;
      }

      if (stats.size === lastLogSize) return; // no new content yet

      const stream = fs.createReadStream(path.join(PROJECT_DIR, 'build_log.md'), {
        encoding: 'utf8', start: lastLogSize, end: stats.size
      });
      stream.on('data', chunk => {
        chunk.split('\n').filter(l => l.trim()).forEach(line => {
          const parsed = parseLine(line);
          if (parsed) {
            broadcast('log', parsed);
            // Route actionable insights to the Chat Feed
            if (parsed.model) {
              const msg = parsed.message.replace(/^(?:AUDIT \([^)]+\):\s*|WORKER \([^)]+\):\s*|EXECUTOR \([^)]+\):\s*)/i, '');
              broadcastChat(parsed.model, msg, 'full');
            } else if (parsed.action === 'failed' || parsed.action === 'complete') {
              broadcastChat('system', parsed.message, 'full');
            }
          }
        });
      });
      lastLogSize = stats.size;
    });
  });

// State watcher
chokidar.watch(path.join(PROJECT_DIR, 'build_state.json'), { persistent: true })
  .on('change', () => {
    try {
      const state = JSON.parse(fs.readFileSync(path.join(PROJECT_DIR, 'build_state.json'), 'utf8'));
      broadcast('state', state);
    } catch (_) {}
  });

// File tree watcher
const watchIgnore = [/node_modules/, /rtk[\\\/]/, /\.git/, /__pycache__/, /monitor[\\\/]/, /\.opencode/];
chokidar.watch(PROJECT_DIR, { ignored: watchIgnore, persistent: true, ignoreInitial: true, depth: 6 })
  .on('add',    f => broadcast('file', { path: path.relative(PROJECT_DIR, f).replace(/\\/g, '/'), event: 'add' }))
  .on('change', f => broadcast('file', { path: path.relative(PROJECT_DIR, f).replace(/\\/g, '/'), event: 'change' }));

// Completion flag watcher
chokidar.watch(path.join(PROJECT_DIR, 'BUILD_COMPLETE.flag'), { persistent: true })
  .on('add', () => broadcast('build_complete', { timestamp: new Date().toISOString() }));

app.listen(PORT, () => console.log(`\n  EMI Monitor → http://localhost:${PORT}\n`));
