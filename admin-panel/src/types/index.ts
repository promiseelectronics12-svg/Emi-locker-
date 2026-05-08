export interface Device {
  id: string;
  imei: string;
  model: string;
  lockState: 'UNLOCKED' | 'PARTIAL_LOCK' | 'FULL_LOCK' | 'DECOUPLED';
  dealerId: string;
  resellerId: string;
  emiScheduleId: string;
  isOverdue: boolean;
  overdueDays: number;
  lastLocation: {
    lat: number;
    lng: number;
    timestamp: string;
  };
  createdAt: string;
}

export interface Reseller {
  id: string;
  name: string;
  email: string;
  status: 'APPROVED' | 'SUSPENDED' | 'PENDING';
  monthlyQuota: number;
  usedQuota: number;
  activatedKeys?: number;
}

export interface KeyRequest {
  id: string;
  resellerId: string;
  quantity: number;
  justification: string;
  status: 'PENDING' | 'APPROVED' | 'REJECTED';
  createdAt: string;
}

export interface AuditLog {
  id: string;
  adminId: string;
  action: string;
  targetId: string;
  details: string;
  timestamp: string;
  ipAddress: string;
}

export interface SecurityEvent {
  id: string;
  deviceId: string;
  type: 'SIM_CHANGE' | 'USB_TAMPER' | 'ADB_ATTEMPT' | 'PLAY_INTEGRITY_FAIL';
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  status: 'OPEN' | 'RESOLVED';
  description: string;
  timestamp: string;
}

export interface DecouplingRequest {
  id: string;
  deviceId: string;
  paymentConfirmedAt: string;
  dealerFlaggedFraud: boolean;
  windowExpiresAt: string;
  status: 'PENDING_ADMIN' | 'EXECUTED';
}

export interface User {
  id: string;
  email: string;
  role: 'SUPER_ADMIN' | 'AUDITOR';
  twoFactorEnabled: boolean;
}
