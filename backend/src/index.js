require('dotenv').config();
require('express-async-errors');

// 1. Load environment config (fail fast if required vars missing)
const { validateEnvironment } = require('./config/envValidator');
validateEnvironment();

// 2. Connect PostgreSQL
const { pool } = require('./config/database');

// 3. Connect Redis
const redis = require('./config/redis');

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const logger = require('./utils/logger');
const errorHandler = require('./middleware/errorHandler');
const routes = require('./routes');

// Module Schedulers/Init
const { lockSchedulerService } = require('./modules/lock');
const { initLocationModule } = require('./modules/location');
const { initDecouplingModule } = require('./modules/decoupling');
const { initKeyCronJobs } = require('./modules/keys/keyScheduler');
const { initFraudCronJobs } = require('./modules/fraud');

const app = express();

// 4. Apply global middleware
app.use(helmet());
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map(o => o.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true
}));
app.use(express.json());
app.use(morgan('combined', { 
  stream: { 
    write: (message) => logger.info(message.trim()) 
  } 
}));

/**
 * 5. Health check endpoint: GET /health
 * Returns 200 OK only if DB and Redis are connected
 */
app.get('/health', async (req, res) => {
  let dbStatus = 'disconnected';
  let redisStatus = 'disconnected';

  let dbErrorMsg = null;

  try {
    await pool.query('SELECT 1');
    dbStatus = 'connected';
  } catch (err) {
    dbErrorMsg = err.message;
    logger.error('Health check database error:', err);
  }

  try {
    const pong = await redis.ping();
    if (pong === 'PONG') redisStatus = 'connected';
  } catch (err) {
    logger.error('Health check redis error:', err);
  }

  const isHealthy = dbStatus === 'connected' && redisStatus === 'connected';

  res.status(isHealthy ? 200 : 503).json({
    status: isHealthy ? 'ok' : 'error',
    timestamp: new Date().toISOString(),
    db: dbStatus,
    db_error: dbErrorMsg,
    redis: redisStatus
  });
});

// 6. Register all module routers under /api/v1/
app.use('/api/v1', routes);

// 7. Register error handler LAST
app.use(errorHandler);

// 8. Listen on PORT and start schedulers
const PORT = process.env.PORT || 3000;
let server;

const startServer = async () => {
  try {
    // Start Bull queue schedulers and other cron jobs
    lockSchedulerService.start();
    await initLocationModule();
    initDecouplingModule();
    initKeyCronJobs();
    initFraudCronJobs();
    
    logger.info('All module schedulers initialized');

    server = app.listen(PORT, () => {
      logger.info(`EMI Locker API running on port ${PORT} in ${process.env.NODE_ENV} mode`);
    });
  } catch (err) {
    logger.error('Failed to start server:', err);
    process.exit(1);
  }
};

startServer();

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  logger.info(`${signal} received. Shutting down gracefully...`);
  
  if (server) {
    server.close(async () => {
      try {
        await pool.end();
        await redis.quit();
        process.exit(0);
      } catch (err) {
        logger.error('Error during graceful shutdown:', err);
        process.exit(1);
      }
    });
  } else {
    process.exit(0);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = app;
