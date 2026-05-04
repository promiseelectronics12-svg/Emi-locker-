import { useState } from 'react';
import { useSecurityEvents, useResolveSecurityEvent } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { formatDateTime } from '@/lib/utils';
import { Shield, AlertTriangle, CheckCircle, ChevronLeft, ChevronRight } from 'lucide-react';
import type { SecurityEventSeverity } from '@/types';

const severityColors: Record<SecurityEventSeverity, string> = {
  LOW: 'secondary',
  MEDIUM: 'warning',
  HIGH: 'destructive',
  CRITICAL: 'destructive',
};

const eventTypeLabels: Record<string, string> = {
  SIM_CHANGE: 'SIM Change',
  USB_TAMPER: 'USB Tamper',
  ADB_DETECTED: 'ADB Detected',
  UNINSTALL_ATTEMPT: 'Uninstall Attempt',
  KIOSK_BREACH: 'Kiosk Breach',
  PLAY_INTEGRITY_FAILURE: 'Play Integrity Failure',
};

export function SecurityEventsPage() {
  const [page, setPage] = useState(1);
  const [severity, setSeverity] = useState<string>('');
  const [resolved, setResolved] = useState<string>('');
  const [selectedEvent, setSelectedEvent] = useState<string | null>(null);
  const [resolution, setResolution] = useState<string>('');

  const limit = 20;
  const { data, isLoading, error } = useSecurityEvents({
    page,
    limit,
    severity: severity || undefined,
    resolved: resolved === 'true' ? true : resolved === 'false' ? false : undefined,
  });

  const resolveEvent = useResolveSecurityEvent();
  const { open: open2FA } = useTwoFactorStore();

  const handleOpenResolve = (eventId: string) => {
    setSelectedEvent(eventId);
    setResolution('');
  };

  const handleResolve = () => {
    if (!selectedEvent || !resolution) return;
    open2FA({
      actionDescription: 'Resolve this security event',
      onSuccess: () => {
        resolveEvent.mutate(
          { eventId: selectedEvent, resolution },
          {
            onSuccess: () => {
              setSelectedEvent(null);
              setResolution('');
            },
          }
        );
      },
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Security Events</h1>
        <p className="text-muted-foreground">Monitor fraud alerts and anomaly detections</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Shield className="h-5 w-5" />
            Security Event Log
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2 mb-6">
            <Select value={severity} onValueChange={(v) => { setSeverity(v); setPage(1); }}>
              <SelectTrigger className="w-[160px]">
                <SelectValue placeholder="Severity" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="">All Severity</SelectItem>
                <SelectItem value="LOW">Low</SelectItem>
                <SelectItem value="MEDIUM">Medium</SelectItem>
                <SelectItem value="HIGH">High</SelectItem>
                <SelectItem value="CRITICAL">Critical</SelectItem>
              </SelectContent>
            </Select>
            <Select value={resolved} onValueChange={(v) => { setResolved(v); setPage(1); }}>
              <SelectTrigger className="w-[160px]">
                <SelectValue placeholder="Status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="">All Status</SelectItem>
                <SelectItem value="false">Active</SelectItem>
                <SelectItem value="true">Resolved</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load security events</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Timestamp</TableHead>
                      <TableHead>Device</TableHead>
                      <TableHead>User</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead>Severity</TableHead>
                      <TableHead>Description</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((event) => (
                      <TableRow key={event.id}>
                        <TableCell className="whitespace-nowrap text-sm">{formatDateTime(event.createdAt)}</TableCell>
                        <TableCell>
                          <div>
                            <p className="font-mono text-sm">{event.imei}</p>
                            <p className="text-xs text-muted-foreground">{event.dealerName}</p>
                          </div>
                        </TableCell>
                        <TableCell>{event.userName}</TableCell>
                        <TableCell>
                          <Badge variant="secondary">{eventTypeLabels[event.eventType] || event.eventType}</Badge>
                        </TableCell>
                        <TableCell>
                          <Badge variant={severityColors[event.severity] as any}>
                            {event.severity}
                          </Badge>
                        </TableCell>
                        <TableCell className="max-w-xs truncate text-sm text-muted-foreground">
                          {event.description}
                        </TableCell>
                        <TableCell>
                          {event.resolvedAt ? (
                            <div className="flex items-center gap-1 text-green-600">
                              <CheckCircle className="h-4 w-4" />
                              <span className="text-sm">Resolved</span>
                            </div>
                          ) : (
                            <div className="flex items-center gap-1 text-destructive">
                              <AlertTriangle className="h-4 w-4" />
                              <span className="text-sm">Active</span>
                            </div>
                          )}
                        </TableCell>
                        <TableCell>
                          {!event.resolvedAt && (
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => handleOpenResolve(event.id)}
                            >
                              Resolve
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} events
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
              <Shield className="h-12 w-12 mb-4" />
              <p>No security events found</p>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!selectedEvent} onOpenChange={() => { setSelectedEvent(null); setResolution(''); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Resolve Security Event</DialogTitle>
            <DialogDescription>Document the resolution for this security event</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="resolution">Resolution Notes</Label>
              <Input
                id="resolution"
                value={resolution}
                onChange={(e) => setResolution(e.target.value)}
                placeholder="Describe how this event was resolved..."
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setSelectedEvent(null); setResolution(''); }}>
              Cancel
            </Button>
            <Button onClick={handleResolve} disabled={!resolution || resolveEvent.isPending}>
              Resolve Event
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}