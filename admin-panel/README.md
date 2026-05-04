# EMI Locker Admin Panel

React-based admin dashboard for managing the EMI Locker platform - a comprehensive device management and EMI tracking system.

## Overview

The Admin Panel provides:
- Complete system administration and monitoring
- Dealer and reseller management
- Device enrollment oversight
- Payment tracking and reconciliation
- BTRC NEIR compliance reporting
- Analytics and reporting dashboard

## Setup

```bash
# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Configure .env with real credentials before deploy

# Start development server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VITE_API_BASE_URL` | Backend API URL | `http://localhost:3000` |
| `VITE_APP_ENV` | Environment | `development` |
| `VITE_FIREBASE_*` | Firebase configuration | - |

**IMPORTANT**: Update `VITE_API_BASE_URL` with the real domain before production deployment. Firebase configuration is required for push notifications and analytics.

## Project Structure

```
admin-panel/
├── src/
│   ├── components/    # Reusable UI components
│   ├── pages/        # Page components
│   ├── services/      # API services
│   ├── utils/         # Utility functions
│   ├── context/       # React context providers
│   └── hooks/         # Custom React hooks
├── public/
├── index.html
├── package.json
├── vite.config.ts
├── tailwind.config.js
└── .env.example
```

## Architecture

React 18 with TypeScript using:
- **Vite** for build tooling
- **Zustand** for state management
- **React Router** for navigation
- **React Hook Form + Zod** for form validation
- **Tailwind CSS** for styling
- **Recharts** for data visualization

## Features

### Dashboard
- System overview with key metrics
- Active devices count
- Payment collection summary
- Recent activity feed

### Device Management
- View all enrolled devices
- Device status monitoring
- Remote lock/unlock commands
- Factory reset initiation

### Dealer Management
- Create and manage dealer accounts
- Reseller network management
- Commission tracking
- Performance analytics

### Payment Oversight
- All transactions overview
- Payment reconciliation
- Overdue handling
- Receipt verification

### BTRC NEIR Integration
- IMEI verification status
- Fraud reporting interface
- Compliance monitoring

### Reports
- Sales reports
- Payment collection reports
- Device status reports
- Export to CSV/Excel

## Security

- All API calls use HTTPS
- JWT token authentication with refresh
- Role-based access control (Admin, Super Admin)
- Session management with timeout
- Audit logging for all actions

## Build Variants

| Variant | Command | Purpose |
|---------|---------|---------|
| Development | `npm run dev` | Local development |
| Production | `npm run build` | Production build |
| Preview | `npm run preview` | Preview production build |

## Important Notes

- Requires Node.js 18 or higher
- Uses React 18 with concurrent features
- TypeScript for type safety
- All environment variables must be set via .env file
- Never hardcode API URLs - use environment variables