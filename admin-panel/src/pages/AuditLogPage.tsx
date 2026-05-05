import { useState } from 'react';
import { useAuditLog } from '@/hooks/useApi';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime } from '@/lib/utils';
import { FileText, AlertTriangle, ChevronLeft, ChevronRight } from 'lucide-react';
import type { AuditAction } from '@/types';

const actionColors: Record<AuditAction, string> = {
  DEVICE_LOCK: 'destructive',
  DEVICE_UNLOCK: 'success',
  DEVICE_DECOUPLE: 'info',
  DEVICE_SUSPEND: 'destructive',
  RESELLER_APPROVE: 'success',
  RESELLER_SUSPEND: 'destructive',
  KEY_REQUEST_APPROVE: 'success',
  KEY_REQUEST_REJECT: 'destructive',
  NEIR_REPORT: 'warning',
  'SECURITY_EVENT_RESOLVE': 'success',
  '2FA_VERIFY': 'secondary',
};

export function AuditLogPage() {
  const [page, setPage] = useState(1);
  const [action, setAction] = useState<string>('');
  const [targetType, setTargetType] = useState<string>('');
  const [startDate, setStartDate] = useState<string>('');
  const [endDate, setEndDate] = useState<string>('');
  const [adminId, setAdminId] = useState<string>('');

  const limit = 10;
  const { data, isLoading, error } = useAuditLog({
    page,
    limit,
    action: action || undefined,
    targetType: targetType || undefined,
    startDate: startDate || undefined,
    endDate: endDate || undefined,
    adminId: adminId || undefined,
  });

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Audit Log</h1>
        <p className="text-muted-foreground">Immutable record of all administrative actions</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5" />
            All Actions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSearch} className="flex flex-wrap gap-4 mb-6">
            <Input
              placeholder="Admin ID"
              value={adminId}
              onChange={(e) => setAdminId(e.target.value)}
              className="w-[200px]"
            />
            <Select value={action} onValueChange={(v) => { setAction(v); setPage(1); }}>
              <SelectTrigger className="w-[200px]">
                <SelectValue placeholder="Action type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="">All Actions</SelectItem>
                <SelectItem value="DEVICE_LOCK">Device Lock</SelectItem>
                <SelectItem value="DEVICE_UNLOCK">Device Unlock</SelectItem>
                <SelectItem value="DEVICE_DECOUPLE">Device Decouple</SelectItem>
                <SelectItem value="DEVICE_SUSPEND">Device Suspend</SelectItem>
                <SelectItem value="RESELLER_APPROVE">Reseller Approve</SelectItem>
                <SelectItem value="RESELLER_SUSPEND">Reseller Suspend</SelectItem>
                <SelectItem value="KEY_REQUEST_APPROVE">Key Request Approve</SelectItem>
                <SelectItem value="KEY_REQUEST_REJECT">Key Request Reject</SelectItem>
                <SelectItem value="NEIR_REPORT">NEIR Report</SelectItem>
                <SelectItem value="SECURITY_EVENT_RESOLVE">Security Event Resolve</SelectItem>
                <SelectItem value="2FA_VERIFY">2FA Verify</SelectItem>
              </SelectContent>
            </Select>
            <Select value={targetType} onValueChange={(v) => { setTargetType(v); setPage(1); }}>
              <SelectTrigger className="w-[160px]">
                <SelectValue placeholder="Target type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="">All Types</SelectItem>
                <SelectItem value="DEVICE">Device</SelectItem>
                <SelectItem value="RESELLER">Reseller</SelectItem>
                <SelectItem value="KEY_REQUEST">Key Request</SelectItem>
                <SelectItem value="USER">User</SelectItem>
                <SelectItem value="SYSTEM">System</SelectItem>
              </SelectContent>
            </Select>
            <Input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-[160px]"
            />
            <Input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-[160px]"
            />
            <Button type="submit">Filter</Button>
          </form>

          {isLoading ? (
            <div className="rounded-xl border border-border/50 overflow-hidden bg-card">
              <Table>
                <TableHeader>
                  <TableRow className="bg-muted/30">
                    <TableHead className="w-[150px]">Timestamp</TableHead>
                    <TableHead className="w-[150px]">Admin</TableHead>
                    <TableHead className="w-[120px]">Action</TableHead>
                    <TableHead className="w-[150px]">Target</TableHead>
                    <TableHead>Details</TableHead>
                    <TableHead className="w-[120px]">IP Address</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {Array.from({ length: 10 }).map((_, i) => (
                    <TableRow key={i}>
                      <TableCell><div className="skeleton h-4 w-24"></div></TableCell>
                      <TableCell>
                        <div className="space-y-2">
                          <div className="skeleton h-4 w-20"></div>
                          <div className="skeleton h-3 w-16"></div>
                        </div>
                      </TableCell>
                      <TableCell><div className="skeleton h-6 w-24 rounded-full"></div></TableCell>
                      <TableCell>
                        <div className="space-y-2">
                          <div className="skeleton h-4 w-16"></div>
                          <div className="skeleton h-3 w-24"></div>
                        </div>
                      </TableCell>
                      <TableCell><div className="skeleton h-4 w-full max-w-[250px]"></div></TableCell>
                      <TableCell><div className="skeleton h-4 w-24"></div></TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load audit log</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="bento-card overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow className="bg-muted/30 hover:bg-muted/30">
                      <TableHead className="font-semibold">Timestamp</TableHead>
                      <TableHead className="font-semibold">Admin</TableHead>
                      <TableHead className="font-semibold">Action</TableHead>
                      <TableHead className="font-semibold">Target</TableHead>
                      <TableHead className="font-semibold">Details</TableHead>
                      <TableHead className="font-semibold">IP Address</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((entry, index) => (
                      <TableRow key={entry.id} className="animate-in fade-in slide-in-from-bottom-2 duration-500" style={{ animationDelay: `${index * 50}ms` }}>
                        <TableCell className="whitespace-nowrap font-mono text-sm">
                          {formatDateTime(entry.timestamp)}
                        </TableCell>
                        <TableCell>
                          <div>
                            <p className="font-medium">{entry.adminName}</p>
                            <p className="text-xs text-muted-foreground">{entry.adminId}</p>
                          </div>
                        </TableCell>
                        <TableCell>
                          <Badge variant={actionColors[entry.action] as any}>
                            {entry.action.replace(/_/g, ' ')}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div>
                            <p className="text-sm">{entry.targetType}</p>
                            {entry.targetId && (
                              <p className="text-xs text-muted-foreground font-mono">{entry.targetId}</p>
                            )}
                          </div>
                        </TableCell>
                        <TableCell className="max-w-xs truncate">
                          <span className="text-sm text-muted-foreground">
                            {JSON.stringify(entry.details)}
                          </span>
                        </TableCell>
                        <TableCell className="font-mono text-sm">{entry.ipAddress}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} entries
                </p>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <span className="flex items-center px-3 text-sm">Page {page} of {data.totalPages}</span>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))} disabled={page === data.totalPages}>
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <FileText className="h-12 w-12 mb-4" />
              <p>No audit entries found</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}