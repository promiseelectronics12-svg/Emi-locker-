import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  Loader2,
  Lock,
  Unlock,
  AlertTriangle,
  MapPin,
  Calendar,
  History,
  Shield,
  Smartphone,
  User,
  Phone,
  Building,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { api } from '@/lib/api'
import { formatCurrency, formatDate, formatDateOnly } from '@/lib/utils'
import { useTwoFactorStore } from '@/store/twoFactorStore'
import type { Device, DeviceLocationHistory, AuditLogEntry, LockState } from '@/types'
import { DeviceLocationMap } from '@/components/DeviceLocationMap'

const lockStateColors: Record<LockState, string> = {
  ACTIVE: 'success',
  PARTIAL_LOCK: 'warning',
  FULL_LOCK: 'destructive',
  KIOSK_MODE: 'destructive',
  DEVICE_DECOUPLED: 'secondary',
  PERMANENTLY_LOCKED: 'destructive',
}

export function DeviceDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const openTwoFactorModal = useTwoFactorStore((state) => state.openModal)

  const { data: device, isLoading: deviceLoading } = useQuery<Device>({
    queryKey: ['device', id],
    queryFn: () => api.get(`/api/admin/devices/${id}`),
    enabled: !!id,
  })

  const { data: locationHistory, isLoading: locationLoading } = useQuery<{
    history: DeviceLocationHistory[]
  }>({
    queryKey: ['device-location', id],
    queryFn: () => api.get(`/api/admin/devices/${id}/location`),
    enabled: !!id,
  })

  const { data: auditLog, isLoading: auditLoading } = useQuery<{
    entries: AuditLogEntry[]
    total: number
  }>({
    queryKey: ['device-audit', id],
    queryFn: () => api.get(`/api/admin/devices/${id}/audit`),
    enabled: !!id,
  })

  const { data: emiSchedule } = useQuery<{
    schedule: Array<{
      emiNumber: number
      dueDate: string
      amount: number
      status: 'PENDING' | 'PAID' | 'OVERDUE' | 'MISSED'
      paidAt?: string
    }>
    totalPaid: number
    totalPending: number
  }>({
    queryKey: ['device-emi-schedule', id],
    queryFn: () => api.get(`/api/admin/devices/${id}/emi-schedule`),
    enabled: !!id,
  })

  const lockMutation = useMutation({
    mutationFn: (lockType: 'PARTIAL_LOCK' | 'FULL_LOCK') =>
      api.post(`/api/admin/devices/${id}/lock`, { lockType }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device', id] })
    },
  })

  const unlockMutation = useMutation({
    mutationFn: () => api.post(`/api/admin/devices/${id}/unlock`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['device', id] })
    },
  })

  const pullLocationMutation = useMutation({
    mutationFn: () => api.post(`/api/location/${id}/pull`, { reason: 'admin_request' }),
    onSuccess: () => {
      setTimeout(() => {
        queryClient.invalidateQueries({ queryKey: ['device-location', id] })
      }, 5000)
    },
  })

  const handleLock = (lockType: 'PARTIAL_LOCK' | 'FULL_LOCK') => {
    openTwoFactorModal({
      action: `Lock device to ${lockType === 'PARTIAL_LOCK' ? 'Partial' : 'Full'} Lock`,
      resourceId: id,
      onSuccess: () => {
        lockMutation.mutate(lockType)
      },
    })
  }

  const handleUnlock = () => {
    openTwoFactorModal({
      action: 'Unlock device',
      resourceId: id,
      onSuccess: () => {
        unlockMutation.mutate()
      },
    })
  }

  if (deviceLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    )
  }

  if (!device) {
    return (
      <div className="text-center py-8">
        <p className="text-muted-foreground">Device not found</p>
        <Button variant="outline" onClick={() => navigate('/devices')} className="mt-4">
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Devices
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="ghost" onClick={() => navigate('/devices')}>
          <ArrowLeft className="h-4 w-4" />
        </Button>
        <div className="flex-1">
          <h1 className="text-3xl font-bold">{device.deviceModel}</h1>
          <p className="text-muted-foreground font-mono">{device.imei}</p>
        </div>
        <div className="flex gap-2">
          {device.lockState !== 'DEVICE_DECOUPLED' && device.lockState !== 'PERMANENTLY_LOCKED' && (
            <>
              {device.lockState === 'ACTIVE' && (
                <>
                  <Button
                    variant="outline"
                    onClick={() => handleLock('PARTIAL_LOCK')}
                    disabled={lockMutation.isPending}
                  >
                    <Lock className="mr-2 h-4 w-4" />
                    Partial Lock
                  </Button>
                  <Button
                    variant="destructive"
                    onClick={() => handleLock('FULL_LOCK')}
                    disabled={lockMutation.isPending}
                  >
                    <Lock className="mr-2 h-4 w-4" />
                    Full Lock
                  </Button>
                </>
              )}
              {(device.lockState === 'PARTIAL_LOCK' || device.lockState === 'FULL_LOCK' || device.lockState === 'KIOSK_MODE') && (
                <Button
                  variant="default"
                  onClick={handleUnlock}
                  disabled={unlockMutation.isPending}
                >
                  <Unlock className="mr-2 h-4 w-4" />
                  Unlock
                </Button>
              )}
            </>
          )}
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Smartphone className="h-5 w-5" />
              Device Information
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Manufacturer</p>
                <p className="font-medium">{device.deviceManufacturer}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Model</p>
                <p className="font-medium">{device.deviceModel}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">IMEI</p>
                <p className="font-mono">{device.imei}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Enrollment Date</p>
                <p className="font-medium">{formatDateOnly(device.enrollmentDate)}</p>
              </div>
            </div>

            <Separator />

            <div className="flex gap-2">
              <Badge variant={lockStateColors[device.lockState] as 'default' | 'secondary' | 'destructive' | 'outline' | 'success' | 'warning' | 'info'}>
                {device.lockState.replace(/_/g, ' ')}
              </Badge>
              {device.isOverdue && (
                <Badge variant="destructive">
                  <AlertTriangle className="h-3 w-3 mr-1" />
                  {device.overdueDays} Days Overdue
                </Badge>
              )}
              {device.fraudFlagged && (
                <Badge variant="destructive">Fraud Flagged</Badge>
              )}
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <User className="h-5 w-5" />
              User Information
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Name</p>
                <p className="font-medium">{device.userName}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Phone</p>
                <p className="font-medium flex items-center gap-2">
                  <Phone className="h-4 w-4" />
                  {device.userPhone}
                </p>
              </div>
            </div>

            <Separator />

            <div>
              <p className="text-sm text-muted-foreground mb-2">Dealer</p>
              <div className="flex items-center gap-2">
                <Building className="h-4 w-4 text-muted-foreground" />
                <span className="font-medium">{device.dealerName}</span>
              </div>
              <p className="text-sm text-muted-foreground">Reseller: {device.resellerName}</p>
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Calendar className="h-5 w-5" />
            EMI Schedule
          </CardTitle>
        </CardHeader>
        <CardContent>
          {emiSchedule ? (
            <div className="space-y-4">
              <div className="grid grid-cols-3 gap-4">
                <div className="p-4 bg-muted rounded-lg">
                  <p className="text-sm text-muted-foreground">Total Amount</p>
                  <p className="text-xl font-bold">{formatCurrency(device.totalEMIAmount)}</p>
                </div>
                <div className="p-4 bg-green-500/10 rounded-lg">
                  <p className="text-sm text-muted-foreground">Paid</p>
                  <p className="text-xl font-bold text-green-600">{formatCurrency(emiSchedule.totalPaid)}</p>
                </div>
                <div className="p-4 bg-yellow-500/10 rounded-lg">
                  <p className="text-sm text-muted-foreground">Pending</p>
                  <p className="text-xl font-bold text-yellow-600">{formatCurrency(emiSchedule.totalPending)}</p>
                </div>
              </div>

              <div className="space-y-2">
                {emiSchedule.schedule.map((emi) => (
                  <div
                    key={emi.emiNumber}
                    className={`flex items-center justify-between p-3 rounded-lg border ${
                      emi.status === 'OVERDUE' ? 'border-destructive bg-destructive/5' : ''
                    }`}
                  >
                    <div className="flex items-center gap-4">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold ${
                        emi.status === 'PAID' ? 'bg-green-500 text-white' :
                        emi.status === 'OVERDUE' ? 'bg-destructive text-white' :
                        'bg-muted'
                      }`}>
                        {emi.emiNumber}
                      </div>
                      <div>
                        <p className="font-medium">{formatDateOnly(emi.dueDate)}</p>
                        <p className="text-sm text-muted-foreground">{formatCurrency(emi.amount)}</p>
                      </div>
                    </div>
                    <Badge
                      variant={
                        emi.status === 'PAID' ? 'success' :
                        emi.status === 'OVERDUE' ? 'destructive' :
                        'secondary'
                      }
                    >
                      {emi.status}
                    </Badge>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <p className="text-muted-foreground">Failed to load EMI schedule</p>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <MapPin className="h-5 w-5 text-primary" />
              Device Location
            </div>
            <div className="flex items-center gap-2">
              <Button 
                variant="outline" 
                size="sm" 
                onClick={() => pullLocationMutation.mutate()}
                disabled={pullLocationMutation.isPending}
                className="gap-2"
              >
                {pullLocationMutation.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <MapPin className="h-4 w-4" />
                )}
                Pull Live Location
              </Button>
            </div>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {locationLoading ? (
            <div className="flex items-center justify-center h-[400px] bg-muted/20 rounded-md border border-dashed">
              <Loader2 className="h-8 w-8 animate-spin text-primary" />
            </div>
          ) : (
            <div className="space-y-4">
              <DeviceLocationMap 
                locations={locationHistory?.history || []}
                lastKnown={locationHistory?.last_known || null}
                isLoading={pullLocationMutation.isPending}
              />
              
              {locationHistory?.last_known && (
                <div className="flex items-center justify-between text-sm text-muted-foreground px-1">
                  <div>
                    <span className="font-medium text-foreground">Last updated: </span>
                    {formatDistanceToNow(new Date(locationHistory.last_known.timestamp), { addSuffix: true })}
                  </div>
                  <div className="flex items-center gap-4">
                    <span>Accuracy: {Math.round(locationHistory.last_known.accuracy)}m</span>
                    {locationHistory.last_known.battery_level && (
                      <span>Battery: {locationHistory.last_known.battery_level}%</span>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <History className="h-5 w-5" />
            Audit Log
          </CardTitle>
        </CardHeader>
        <CardContent>
          {auditLoading ? (
            <div className="flex items-center justify-center h-32">
              <Loader2 className="h-6 w-6 animate-spin text-primary" />
            </div>
          ) : !auditLog || auditLog.entries.length === 0 ? (
            <p className="text-muted-foreground text-center py-8">No audit log entries</p>
          ) : (
            <div className="space-y-2">
              {auditLog.entries.map((entry) => (
                <div key={entry.id} className="flex items-start gap-4 p-3 rounded-lg border">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <Badge variant="outline">{entry.action}</Badge>
                      {entry.adminId && (
                        <span className="text-xs text-muted-foreground">Admin ID: {entry.adminId}</span>
                      )}
                    </div>
                    <p className="text-sm mt-1">
                      {Object.entries(entry.details).map(([key, value]) => (
                        <span key={key} className="text-muted-foreground">
                          {key}: {String(value)} • 
                        </span>
                      ))}
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-sm">{formatDate(entry.timestamp)}</p>
                    {entry.ipAddress && (
                      <p className="text-xs text-muted-foreground">{entry.ipAddress}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}