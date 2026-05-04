# EMI Locker Backend

Node.js + Express API for the EMI Locker Platform - a comprehensive device management and EMI tracking system.

## Overview

This is the backend API service that handles:
- Device enrollment and management via Android Management API
- EMI agreement processing and payment tracking
- Dealer and reseller management
- Admin panel operations
- BTRC NEIR integration for IMEI verification

## Setup

```bash
# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Configure .env with real credentials before deploy

# Run database migrations
npm run migrate

# Seed initial data (optional)
npm run seed

# Start development server
npm run dev

# Start production server
npm start
```

## Environment Variables

All environment variables are documented in `.env.example`. Key variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `API_BASE_URL` | API base URL | `http://localhost:3000` |
| `DATABASE_URL` | PostgreSQL connection string | - |
| `JWT_SECRET` | JWT signing secret | - |
| `JWT_EXPIRES_IN` | Token expiration | `7d` |
| `BCRYPT_ROUNDS` | Password hash rounds | `12` |

**IMPORTANT**: Generate strong random values for `JWT_SECRET`, `ENCRYPTION_KEY`, and `DEVICE_TOKEN_SECRET` before production deployment.

## Project Structure

```
backend/
├── src/
│   ├── config/         # Environment and application configuration
│   ├── controllers/    # Route handlers
│   ├── middleware/     # Express middleware (auth, validation, errors)
│   ├── models/         # Database models and queries
│   ├── routes/         # API route definitions
│   ├── services/       # Business logic services
│   └── utils/          # Utility functions
├── scripts/            # Migration and deployment scripts
├── tests/              # Test files
├── package.json
└── .env.example
```

## Security

- All API endpoints require authentication unless explicitly marked public
- Input validation using express-validator on all endpoints
- Rate limiting enabled (100 requests per 15 minutes per IP)
- Helmet.js for security headers
- CORS configured for allowed origins only
- Passwords hashed with bcrypt (12 rounds)
- JWT tokens with configurable expiration
- All secrets must come from environment variables - never hardcode

## API Versioning

All endpoints are prefixed with `/api/v1`.

## Testing

```bash
npm test              # Run all tests with coverage
npm run test:watch    # Run tests in watch mode
npm run lint          # Lint code
npm run lint:fix      # Auto-fix linting issues
```

## Deployment

1. Generate strong secrets for all encryption keys
2. Configure production database
3. Set `NODE_ENV=production`
4. Use process manager (PM2) for production
5. Configure reverse proxy (nginx) for HTTPS