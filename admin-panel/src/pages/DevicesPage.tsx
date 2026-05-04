import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useDevices } from '@/hooks/useApi';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatCurrency, formatDate, getDaysOverdue, getOverdueStatus } from '@/lib/utils';
import { Search, Smartphone, AlertTriangle, ChevronLeft, ChevronRight } from 'lucide-react';
import type { LockState, DeviceState } from '@/types';

const lockStateColors: Record<LockState, string> = {
  UNLOCKED: 'success',
  PARTIAL_LOCK: 'warning',
  FULL_LOCK: 'destructive',
  KIOSK_MODE: 'destructive',
};

const overdueStatusColors = {
  NONE: 'success',
  MILD: 'warning',
  MODERATE: 'warning',
  SEVERE: 'destructive',
};

export function DevicesPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState('');
  const [state, setState] = useState<string>('');
  const [dealerId, setDealerId] = useState<string>('');
  const [overdue, setOverdue] = useState<string>('');

  const limit = 20;
  const { data, isLoading, error } = useDevices({
    page,
    limit,
    search: search || undefined,
    state: state || undefined,
    dealerId: dealerId || undefined,
    overdue: overdue === 'true' ? true : overdue === 'false' ? false : undefined,
  });

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Devices</h1>
        <p className="text-muted-foreground">Manage and monitor all enrolled devices</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Device List</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-col gap-4 mb-6">
            <form onSubmit={handleSearch} className="flex gap-4">
              <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                <Input
                  placeholder="Search by IMEI, user name, or phone..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-10"
                />
              </div>
              <Button type="submit">Search</Button>
            </form>

            <div className="flex flex-wrap gap-2">
              <Select value={state} onValueChange={(v) => { setState(v); setPage(1); }}>
                <SelectTrigger className="w-[180px]">
                  <SelectValue placeholder="Filter by state" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="">All States</SelectItem>
                  <SelectItem value="ENROLLED">Enrolled</SelectItem>
                  <SelectItem value="EMI_ACTIVE">EMI Active</SelectItem>
                  <SelectItem value="FINAL_PAYMENT_RECEIVED">Final Payment Received</SelectItem>
                  <SelectItem value="PENDING_ADMIN_DECOUPLE">Pending Decouple</SelectItem>
                  <SelectItem value="DEVICE_DECOUPLED">Decoupled</SelectItem>
                  <SelectItem value="SUSPENDED">Suspended</SelectItem>
                  <SelectItem value="FLAGGED_FRAUD">Flagged Fraud</SelectItem>
                </SelectContent>
              </Select>

              <Select value={overdue} onValueChange={(v) => { setOverdue(v); setPage(1); }}>
                <SelectTrigger className="w-[160px]">
                  <SelectValue placeholder="Overdue status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="">All</SelectItem>
                  <SelectItem value="true">Overdue</SelectItem>
                  <SelectItem value="false">Not Overdue</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load devices</p>
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
                      <TableHead>Lock State</TableHead>
                      <TableHead>EMI Status</TableHead>
                      <TableHead>Next Payment</TableHead>
                      <TableHead>Overdue</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((device) => {
                      const overdueDays = getDaysOverdue(device.nextPaymentDate);
                      const overdueStatus = getOverdueStatus(overdueDays);
                      return (
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
                            <Badge variant={lockStateColors[device.lockState] as any}>
                              {device.lockState.replace('_', ' ')}
                            </Badge>
                          </TableCell>
                          <TableCell>
                            <div>
                              <p className="text-sm">{formatCurrency(device.monthlyPayment)}/mo</p>
                              <p className="text-xs text-muted-foreground">
                                {device.paidAmount.toLocaleString()} / {device.totalEmiAmount.toLocaleString()}
                              </p>
                            </div>
                          </TableCell>
                          <TableCell>
                            {device.nextPaymentDate ? (
                              <span className="text-sm">{formatDate(device.nextPaymentDate)}</span>
                            ) : (
                              <span className="text-muted-foreground text-sm">N/A</span>
                            )}
                          </TableCell>
                          <TableCell>
                            {device.isOverdue ? (
                              <div className="flex items-center gap-1">
                                <AlertTriangle className="h-4 w-4 text-destructive" />
                                <Badge variant={overdueStatusColors[overdueStatus] as any}>
                                  {overdueDays} days
                                </Badge>
                              </div>
                            ) : (
                              <Badge variant="success">On Track</Badge>
                            )}
                          </TableCell>
                          <TableCell>
                            <Button asChild variant="ghost" size="sm">
                              <Link to={`/devices/${device.id}`}>View</Link>
                            </Button>
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} devices
                </p>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                    disabled={page === 1}
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <span className="flex items-center px-3 text-sm">
                    Page {page} of {data.totalPages}
                  </span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))}
                    disabled={page === data.totalPages}
                  >
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <Smartphone className="h-12 w-12 mb-4" />
              <p>No devices found</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}