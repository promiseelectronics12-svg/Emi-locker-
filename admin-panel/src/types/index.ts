export type LockState =
  | 'ACTIVE'
  | 'PARTIAL_LOCK'
  | 'FULL_LOCK'
  | 'KIOSK_MODE'
  | 'DEVICE_DECOUPLED'
  | 'PERMANENTLY_LOCKED'

export type DeviceState =
  | 'PENDING_KEY_ACTIVATION'
  | 'EMI_ACTIVE'
  | 'FINAL_PAYMENT_RECEIVED'
  | 'DEALER_NOTIFIED'
  | 'PENDING_ADMIN_DECOUPLE'
  | 'SUSPECTED_FRAUD'
  | 'SUSPECTED_SALE'
  | 'OVERDUE_3'
  | 'OVERDUE_7'

export interface Device {
  id: string
  imei: string
  dealerId: string
  dealerName: string
  resellerId: string
  resellerName: string
  userId: string
  userName: string
  userPhone: string
  lockState: LockState
  deviceState: DeviceState
  deviceModel: string
  deviceManufacturer: string
  enrollmentDate: string
  emiStartDate: string
  totalEMIAmount: number
  monthlyEMIAmount: number
  totalMonths: number
  paidEMICount: number
  remainingEMICount: number
  nextEMIDueDate: string
  isOverdue: boolean
  overdueDays: number
  currentLatitude?: number
  currentLongitude?: number
  lastLocationUpdate?: string
  isDecoupleEligible: boolean
  decoupleWindowStart?: string
  decoupleWindowEnd?: string
  fraudFlagged: boolean
  fraudFlagReason?: string
  createdAt: string
  updatedAt: string
}

export interface DeviceListResponse {
  devices: Device[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface DeviceLocationHistory {
  id: string
  deviceId: string
  latitude: number
  longitude: number
  timestamp: string
  source: 'GPS' | 'NETWORK' | 'CELL'
  accuracy: number
}

export interface AuditLogEntry {
  id: string
  deviceId?: string
  userId?: string
  adminId?: string
  action: string
  details: Record<string, unknown>
  ipAddress?: string
  userAgent?: string
  timestamp: string
}

export interface AuditLogResponse {
  entries: AuditLogEntry[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface Reseller {
  id: string
  name: string
  email: string
  phone: string
  companyName: string
  monthlyQuota: number
  usedQuota: number
  remainingQuota: number
  status: 'PENDING' | 'ACTIVE' | 'SUSPENDED'
  lastKeyRequestAt?: string
  keyRequestCount24h: number
  createdAt: string
  updatedAt: string
}

export interface ResellerListResponse {
  resellers: Reseller[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface KeyRequest {
  id: string
  resellerId: string
  resellerName: string
  quantity: number
  justification: string
  status: 'PENDING' | 'APPROVED' | 'REJECTED'
  adminNotes?: string
  processedAt?: string
  processedBy?: string
  createdAt: string
}

export interface KeyRequestListResponse {
  requests: KeyRequest[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface DecoupleEligibleDevice {
  id: string
  imei: string
  userName: string
  userPhone: string
  dealerName: string
  deviceModel: string
  finalPaymentDate: string
  windowEndDate: string
  daysRemaining: number
  fraudFlagged: boolean
  totalAmountPaid: number
  remainingAmount: number
}

export interface SecurityEvent {
  id: string
  type: 'SIM_CHANGE' | 'USB_TAMPER' | 'ROOT_DETECTED' | 'PLAY_INTEGRITY_FAIL' | 'EXCESSIVE_FAILED_ATTEMPTS' | 'ANOMALY_DETECTED'
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL'
  deviceId: string
  deviceImei: string
  userName: string
  userPhone: string
  dealerName: string
  description: string
  rawData?: Record<string, unknown>
  resolved: boolean
  resolvedAt?: string
  resolvedBy?: string
  resolutionNotes?: string
  createdAt: string
}

export interface SecurityEventListResponse {
  events: SecurityEvent[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface NEIRQueueItem {
  id: string
  deviceId: string
  imei: string
  userName: string
  userPhone: string
  dealerName: string
  deviceModel: string
  reason: 'OVERDUE_14' | 'CONFIRMED_FRAUD' | 'DECEASED_USER' | 'ADMIN_REQUEST'
  totalOverdueEMIs: number
  totalOverdueAmount: number
  status: 'PENDING_REVIEW' | 'SUBMITTED' | 'REJECTED' | 'EXPORTED'
  adminNotes?: string
  createdAt: string
  updatedAt: string
}

export interface NEIRQueueResponse {
  items: NEIRQueueItem[]
  total: number
  page: number
  pageSize: number
  totalPages: number
}

export interface DashboardStats {
  totalDevices: number
  activeDevices: number
  partiallyLockedDevices: number
  fullyLockedDevices: number
  overdueDevices: number
  overdue3Days: number
  overdue7Days: number
  devicesInDecoupleWindow: number
  totalRevenue: number
  collectedEMI: number
  pendingEMI: number
  thisMonthRevenue: number
  lastMonthRevenue: number
  revenueChange: number
}

export interface LockStateDistribution {
  state: LockState
  count: number
  percentage: number
}

export interface TwoFactorVerification {
  code: string
  action: string
  resourceId?: string
}