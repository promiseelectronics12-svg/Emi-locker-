import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useDevice, useDeviceAuditLog, useDeviceEmiSchedule, useDeviceLocationHistory, useLockDevice, useUnlockDevice, useSuspendDevice } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Separator } from '@/components/ui/separator';
import { formatCurrency, formatDate, formatDateTime, getDaysOverdue, getOverdueStatus } from '@/lib/utils';
import { 
  ArrowLeft, 
  AlertTriangle, 
  Lock, 
  Unlock, 
  Pause, 
  MapPin, 
  Calendar,
  Activity,
  Shield
} from 'lucide-react';
import type { LockState } from '@/types';

const lockStateColors: Record<LockState, string> = {
  UNLOCKED: 'success',
  PARTIAL_LOCK: 'warning',
  FULL_LOCK: 'destructive',
  KIOSK_MODE: 'destructive',
};

export function DeviceDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { open: open2FA } = useTwoFactorStore();
  
  const [activeTab, setActiveTab] = useState('info');

  const { data: device, isLoading, error } = useDevice(id!);
  const { data: auditLog } = useDeviceAuditLog(id!, { limit: 10 });
  const { data: emiSchedule } = useDeviceEmiSchedule(id!);
  const { data: locationHistory } = useDeviceLocationHistory(id!, { limit: 20 });

  const lockDevice = useLockDevice();
  const unlockDevice = useUnlockDevice();
  const suspendDevice = useSuspendDevice();

  const handleLock = () => {
    open2FA({
      actionDescription: 'Lock this device',
      onSuccess: () => {
        if (id) lockDevice.mutate({ deviceId: id, code: '' });
      },
    });
  };

  const handleUnlock = () => {
    open2FA({
      actionDescription: 'Unlock this device',
      onSuccess: () => {
        if (id) unlockDevice.mutate({ deviceId: id, code: '' });
      },
    });
  };

  const handleSuspend = () => {
    open2FA({
      actionDescription: 'Suspend this device',
      onSuccess: () => {
        if (id) suspendDevice.mutate({ deviceId: id, reason: 'Admin action', code: '' });
      },
    });
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  if (error || !device) {
    return (
      <div className="flex flex-col items-center justify-center h-96 text-muted-foreground">
        <AlertTriangle className="h-12 w-12 mb-4" />
        <p>Failed to load device</p>
        <Button variant="ghost" onClick={() => navigate('/devices')}>
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Devices
        </Button>
      </div>
    );
  }

  const overdueDays = getDaysOverdue(device.nextPaymentDate);
  const overdueStatus = getOverdueStatus(overdueDays);

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Button variant="ghost" onClick={() => navigate('/devices')}>
          <ArrowLeft className="mr-2 h-4 w-4" />
        </Button>
        <div className="flex-1">
          <h1 className="text-3xl font-bold tracking-tight">Device Details</h1>
          <p className="text-muted-foreground font-mono">{device.imei}</p>
        </div>
        <div className="flex gap-2">
          {device.lockState === 'UNLOCKED' ? (
            <Button variant="destructive" onClick={handleLock}>
              <Lock className="mr-2 h-4 w-4" />
              Lock Device
            </Button>
          ) : (
            <Button variant="default" onClick={handleUnlock}>
              <Unlock className="mr-2 h-4 w-4" />
              Unlock Device
            </Button>
          )}
          <Button variant="outline" onClick={handleSuspend}>
            <Pause className="mr-2 h-4 w-4" />
            Suspend
          </Button>
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Device Information</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Status</p>
                <Badge variant={lockStateColors[device.lockState] as any} className="mt-1">
                  {device.lockState.replace('_', ' ')}
                </Badge>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Device State</p>
                <p className="font-medium mt-1">{device.deviceState.replace(/_/g, ' ')}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">User</p>
                <p className="font-medium">{device.userName}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Phone</p>
                <p className="font-medium">{device.userPhone}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Dealer</p>
                <p className="font-medium">{device.dealerName}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Location</p>
                <p className="font-medium">{device.city || 'N/A'}</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>EMI Information</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground">Total Amount</p>
                <p className="text-2xl font-bold">{formatCurrency(device.totalEmiAmount)}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Paid Amount</p>
                <p className="text-2xl font-bold text-green-600">{formatCurrency(device.paidAmount)}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Remaining</p>
                <p className="text-2xl font-bold">{formatCurrency(device.remainingAmount)}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Monthly Payment</p>
                <p className="text-2xl font-bold">{formatCurrency(device.monthlyPayment)}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Next Payment</p>
                <p className="font-medium">{device.nextPaymentDate ? formatDate(device.nextPaymentDate) : 'N/A'}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Enrolled</p>
                <p className="font-medium">{formatDate(device.enrollmentDate)}</p>
              </div>
            </div>

            {device.isOverdue && (
              <div className="flex items-center gap-2 p-3 bg-destructive/10 rounded-lg border border-destructive/20">
                <AlertTriangle className="h-5 w-5 text-destructive" />
                <div>
                  <p className="font-medium text-destructive">{overdueDays} days overdue</p>
                  <p className="text-sm text-muted-foreground">
                    Status: {overdueStatus}
                  </p>
                </div>
              </div>
            )}

            {device.hasFraudFlag && (
              <div className="flex items-center gap-2 p-3 bg-orange-500/10 rounded-lg border border-orange-500/20">
                <Shield className="h-5 w-5 text-orange-500" />
                <div>
                  <p className="font-medium text-orange-500">Fraud Flag Active</p>
                  <p className="text-sm text-muted-foreground">{device.fraudFlagReason}</p>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="info">EMI Schedule</TabsTrigger>
          <TabsTrigger value="location">Location History</TabsTrigger>
          <TabsTrigger value="audit">Audit Log</TabsTrigger>
        </TabsList>

        <TabsContent value="info" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>EMI Payment Schedule</CardTitle>
            </CardHeader>
            <CardContent>
              {emiSchedule?.schedules && emiSchedule.schedules.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>#</TableHead>
                      <TableHead>Due Date</TableHead>
                      <TableHead>Amount</TableHead>
                      <TableHead>Paid Date</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(emiSchedule.schedules as any[]).map((schedule) => (
                      <TableRow key={schedule.id}>
                        <TableCell>{schedule.sequenceNumber}</TableCell>
                        <TableCell>{formatDate(schedule.dueDate)}</TableCell>
                        <TableCell>{formatCurrency(schedule.amount)}</TableCell>
                        <TableCell>{schedule.paidDate ? formatDate(schedule.paidDate) : '-'}</TableCell>
                        <TableCell>
                          <Badge variant={
                            schedule.status === 'PAID' ? 'success' :
                            schedule.status === 'OVERDUE' ? 'destructive' :
                            schedule.status === 'MISSED' ? 'destructive' : 'secondary'
                          }>
                            {schedule.status}
                          </Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                <p className="text-muted-foreground text-center py-8">No schedule available</p>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="location" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Location History</CardTitle>
            </CardHeader>
            <CardContent>
              {locationHistory?.locations && locationHistory.locations.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Date/Time</TableHead>
                      <TableHead>City</TableHead>
                      <TableHead>Country</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(locationHistory.locations as any[]).map((location: any, index: number) => (
                      <TableRow key={index}>
                        <TableCell>{formatDateTime(location.timestamp)}</TableCell>
                        <TableCell>{location.city || 'Unknown'}</TableCell>
                        <TableCell>{location.country || 'Unknown'}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                <p className="text-muted-foreground text-center py-8">No location history available</p>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="audit" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Audit Log</CardTitle>
            </CardHeader>
            <CardContent>
              {auditLog?.data && auditLog.data.length > 0 ? (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Timestamp</TableHead>
                      <TableHead>Action</TableHead>
                      <TableHead>Admin</TableHead>
                      <TableHead>Details</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {auditLog.data.map((entry) => (
                      <TableRow key={entry.id}>
                        <TableCell className="whitespace-nowrap">{formatDateTime(entry.timestamp)}</TableCell>
                        <TableCell>
                          <Badge variant="secondary">{entry.action.replace(/_/g, ' ')}</Badge>
                        </TableCell>
                        <TableCell>{entry.adminName}</TableCell>
                        <TableCell className="max-w-xs truncate">
                          {JSON.stringify(entry.details)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ) : (
                <p className="text-muted-foreground text-center py-8">No audit entries</p>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}