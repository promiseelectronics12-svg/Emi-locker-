import React from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { CheckCircle, ShieldAlert } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { SecurityEvent } from '@/types';
import { useToast } from '@/hooks/use-toast';

const severityVariant = (severity?: string) => {
  const normalized = String(severity || '').toUpperCase();
  if (normalized === 'CRITICAL' || normalized === 'HIGH') return 'destructive';
  if (normalized === 'MEDIUM' || normalized === 'WARNING') return 'warning';
  return 'outline';
};

const SecurityEvents: React.FC = () => {
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['security-events'],
    queryFn: async () => {
      const { data } = await api.get('/admin/security-events');
      return normalizeList<SecurityEvent>(data.data ?? data);
    },
  });

  const resolveMutation = useMutation({
    mutationFn: async (id: string) => api.patch(`/admin/security-events/${id}`, { status: 'RESOLVED' }),
    onSuccess: () => {
      toast({ title: 'Event resolved', description: 'Security event marked as resolved' });
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Resolve failed', description: err.response?.data?.error || 'Could not resolve event', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading security events" rows={6} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Security events could not be loaded" />;

  const events = Array.isArray(query.data) ? query.data : [];
  const activeCount = events.filter(event => event.status === 'OPEN' || !(event as any).resolved).length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Security Monitoring"
        description="Inspect authentication, policy, and device-integrity signals that require admin awareness."
        action={<Badge variant={activeCount > 0 ? 'destructive' : 'success'}>Active Alerts: {activeCount}</Badge>}
      />

      {events.length === 0 ? (
        <EmptyState title="No security events are active" description="When suspicious activity is detected, it will appear here with severity and resolution controls." icon={ShieldAlert} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Timestamp</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead>Severity</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead className="text-right">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {events.map((event: any) => {
                  const resolved = event.status === 'RESOLVED' || event.resolved;
                  return (
                    <TableRow key={event.id} className={resolved ? 'opacity-60' : ''}>
                      <TableCell className="text-xs font-mono">{event.timestamp || event.created_at || 'Unknown'}</TableCell>
                      <TableCell className="font-medium">{event.type || event.event_type}</TableCell>
                      <TableCell><Badge variant={severityVariant(event.severity)}>{event.severity || 'LOW'}</Badge></TableCell>
                      <TableCell className="max-w-md truncate text-sm">{event.description || event.metadata?.error || event.metadata?.path || 'No description'}</TableCell>
                      <TableCell className="text-right">
                        {!resolved ? (
                          <Button variant="outline" size="sm" className="border-emerald-200 text-emerald-700" onClick={() => resolveMutation.mutate(event.id)}>
                            <CheckCircle className="mr-1 h-4 w-4" /> Resolve
                          </Button>
                        ) : (
                          <Badge variant="success">Resolved</Badge>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {events.map((event: any) => {
              const resolved = event.status === 'RESOLVED' || event.resolved;
              return (
                <BentoPanel key={event.id}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-medium text-emerald-950">{event.type || event.event_type}</p>
                      <p className="text-xs text-muted-foreground">{event.timestamp || event.created_at || 'Unknown'}</p>
                    </div>
                    <Badge variant={severityVariant(event.severity)}>{event.severity || 'LOW'}</Badge>
                  </div>
                  <p className="mt-3 text-sm text-muted-foreground">{event.description || event.metadata?.error || 'No description'}</p>
                  {!resolved ? <Button className="mt-4 w-full" variant="outline" onClick={() => resolveMutation.mutate(event.id)}>Resolve</Button> : null}
                </BentoPanel>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
};

export default SecurityEvents;
