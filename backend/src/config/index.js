module.exports = {
  port: process.env.PORT || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  
  database: {
    url: process.env.DATABASE_URL || 'postgresql://localhost:5432/emilocker',
    pool: {
      min: 2,
      max: 10,
      idleTimeoutMillis: 30000
    }
  },
  
  jwt: {
    secret: process.env.JWT_SECRET || 'change-this-secret-in-production',
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d'
  },
  
  api: {
    baseUrl: process.env.API_BASE_URL || 'http://localhost:3000',
    adminBaseUrl: process.env.ADMIN_API_BASE_URL || 'http://localhost:3000'
  },
  
  redis: {
    url: process.env.REDIS_URL || null
  },
  
  rateLimit: {
    windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 900000,
    maxRequests: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100
  },
  
  logging: {
    level: process.env.LOG_LEVEL || 'info'
  }
};