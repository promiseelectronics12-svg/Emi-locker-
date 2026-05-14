/**
 * In-memory ring buffer of recent server errors.
 * Parses file:line from stack traces so they're clickable in the admin panel.
 * Max 100 entries — oldest dropped when full.
 */

const MAX_ERRORS = 100;

const _errors = [];

function parseOrigin(stack) {
  if (!stack) return null;
  const lines = stack.split('\n');
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    // Match: "at Foo (/abs/path/to/file.js:42:10)"
    const m = line.match(/\(([^)]+\.js):(\d+):(\d+)\)/) ||
              line.match(/at ([^:]+\.js):(\d+):(\d+)/);
    if (m) {
      return { file: m[1], line: parseInt(m[2], 10), col: parseInt(m[3], 10) };
    }
  }
  return null;
}

/**
 * Push an error into the ring buffer.
 * @param {Error} err
 * @param {{ method?: string, path?: string, userId?: string }} context
 */
function push(err, context = {}) {
  const entry = {
    id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
    timestamp: new Date().toISOString(),
    message: err.message,
    name: err.name || 'Error',
    code: err.code || null,
    status: err.status || err.statusCode || 500,
    origin: parseOrigin(err.stack),
    stack: process.env.NODE_ENV !== 'production' ? err.stack : undefined,
    context: {
      method: context.method || null,
      path: context.path || null,
      userId: context.userId || null,
    },
  };

  _errors.push(entry);
  if (_errors.length > MAX_ERRORS) {
    _errors.shift();
  }
}

/**
 * Return recent errors, newest first.
 * @param {number} [limit]
 */
function recent(limit = MAX_ERRORS) {
  return _errors.slice(-limit).reverse();
}

function clear() {
  _errors.length = 0;
}

module.exports = { push, recent, clear };
