import { useState } from 'react';
import { useDecouplingDevices, useExecuteDecoupling } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatCurrency, formatDate, getDaysOverdue } from '@/lib/utils';
import { Unplug, AlertTriangle, CheckCircle, Clock, AlertCircle } from 'lucide-react';

export function DecouplingPage() {
  const [page, setPage] = useState(1);
  const [selectedDeviceId, setSelectedDeviceId] = useState<string | null>(null);

  const limit = 20;
  const { data, isLoading, error } = useDecouplingDevices({ page, limit });
  const executeDecoupling = useExecuteDecoupling();
  const { open: open2FA } = useTwoFactorStore();

  const handleExecuteDecoupling = (deviceId: string) => {
    setSelectedDeviceId(deviceId);
    open2FA({
      actionDescription: 'Execute device decoupling - this action cannot be undone',
      onSuccess: () => {
        executeDecoupling.mutate(
          { deviceId, code: '' },
          {
            onSuccess: () => {
              setSelectedDeviceId(null);
            },
          }
        );
      },
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Decoupling</h1>
        <p className="text-muted-foreground">Devices in the 5-day verification window awaiting admin decoupling</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Unplug className="h-5 w-5" />
            Pending Decoupling Devices
          </CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load decoupling queue</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>IMEI</TableHead>
                      <TableHead>User</TableHead>
                      <TableHead>Dealer</TableHead>
                      <TableHead>Paid Amount</TableHead>
                      <TableHead>Final Payment Date</TableHead>
                      <TableHead>Days in Window</TableHead>
                      <TableHead>Fraud Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((device) => (
                      <TableRow key={device.id}>
                        <TableCell className="font-mono text-sm">{device.imei}</TableCell>
                        <TableCell>
                          <div>
                            <p className="font-medium">{device.userName}</p>
                            <p className="text-sm text-muted-foreground">{device.userPhone}</p>
                          </div>
                        </TableCell>
                        <TableCell>{device.dealerName}</TableCell>
                        <TableCell>
                          <div>
                            <p className="font-medium">{formatCurrency(device.paidAmount)}</p>
                            <p className="text-xs text-muted-foreground">of {formatCurrency(device.totalAmount)}</p>
                          </div>
                        </TableCell>
                        <TableCell>{formatDate(device.finalPaymentDate)}</TableCell>
                        <TableCell>
                          <Badge variant={device.daysInWindow >= 4 ? 'destructive' : device.daysInWindow >= 2 ? 'warning' : 'secondary'}>
                            {device.daysInWindow} days
                          </Badge>
                        </TableCell>
                        <TableCell>
                          {device.fraudFlagged ? (
                            <div className="flex items-center gap-1 text-orange-500">
                              <AlertCircle className="h-4 w-4" />
                              <span className="text-sm">Flagged: {device.fraudReason}</span>
                            </div>
                          ) : (
                            <div className="flex items-center gap-1 text-green-600">
                              <CheckCircle className="h-4 w-4" />
                              <span className="text-sm">No fraud</span>
                            </div>
                          )}
                        </TableCell>
                        <TableCell>
                          <Button
                            size="sm"
                            variant="default"
                            onClick={() => handleExecuteDecoupling(device.id)}
                            disabled={executeDecoupling.isPending}
                          >
                            <Unplug className="mr-2 h-4 w-4" />
                            Decouple
                          </Button>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} devices
                </p>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>
                    Previous
                  </Button>
                  <span className="flex items-center px-3 text-sm">Page {page} of {data.totalPages}</span>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))} disabled={page === data.totalPages}>
                    Next
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <Unplug className="h-12 w-12 mb-4" />
              <p>No devices pending decoupling</p>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>How Decoupling Works</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4 text-sm">
          <div className="flex gap-4 p-4 bg-muted rounded-lg">
            <div className="flex items-center justify-center h-8 w-8 rounded-full bg-primary text-primary-foreground font-medium">1</div>
            <div>
              <p className="font-medium">Final Payment Confirmed</p>
              <p className="text-muted-foreground">Customer makes final payment, dealer verifies</p>
            </div>
          </div>
          <div className="flex gap-4 p-4 bg-muted rounded-lg">
            <div className="flex items-center justify-center h-8 w-8 rounded-full bg-primary text-primary-foreground font-medium">2</div>
            <div>
              <p className="font-medium">5-Day Verification Window</p>
              <p className="text-muted-foreground">Dealer can flag fraud during this window. Cannot block decoupling after day 5.</p>
            </div>
          </div>
          <div className="flex gap-4 p-4 bg-muted rounded-lg">
            <div className="flex items-center justify-center h-8 w-8 rounded-full bg-primary text-primary-foreground font-medium">3</div>
            <div>
              <p className="font-medium">Admin Executes Decoupling</p>
              <p className="text-muted-foreground">Admin confirms with 2FA. Server generates signed RTOC command.</p>
            </div>
          </div>
          <div className="flex gap-4 p-4 bg-muted rounded-lg">
            <div className="flex items-center justify-center h-8 w-8 rounded-full bg-primary text-primary-foreground font-medium">4</div>
            <div>
              <p className="font-medium">Device Receives RTOC via FCM</p>
              <p className="text-muted-foreground">App clears policies, removes Device Owner, uninstalls itself, device reboots clean.</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}