import React, { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { AlertTriangle, Timer, Unlink } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { DecouplingRequest } from '@/types';
import { TwoFactorModal } from '@/components/TwoFactorModal';
import { useToast } from '@/hooks/use-toast';

const Decoupling: React.FC = () => {
  const { toast } = useToast();
  const [isTwoFactorOpen, setIsTwoFactorOpen] = useState(false);
  const [pendingDecoupleId, setPendingDecoupleId] = useState<string | null>(null);

  const query = useQuery({
    queryKey: ['decoupling-queue'],
    queryFn: async () => {
      const { data } = await api.get('/admin/decoupling/pending');
      return normalizeList<DecouplingRequest>(data.data ?? data);
    },
  });

  const decoupleMutation = useMutation({
    mutationFn: async ({ id, code }: { id: string; code: string }) => api.post(`/admin/decoupling/execute/${id}`, { twoFactorCode: code }),
    onSuccess: () => {
      toast({ title: 'Device decoupled', description: 'Decouple command sent successfully' });
      setIsTwoFactorOpen(false);
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Decouple failed', description: err.response?.data?.message || 'Authentication failed', variant: 'destructive' });
      setIsTwoFactorOpen(false);
    },
  });

  if (query.isLoading) return <LoadingState title="Loading decoupling queue" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Decoupling queue could not be loaded" />;

  const queue = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Decoupling Management"
        description="Review devices in the payment-cleared release window before final MDM removal."
        action={<Badge className="bg-emerald-600">Queue Size: {queue.length}</Badge>}
      />

      <BentoPanel tone="warning" className="flex gap-3">
        <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-amber-700" />
        <p className="text-sm text-amber-900/78">
          Devices flagged for fraud must be manually reviewed before final decoupling. Execution permanently releases the device from management.
        </p>
      </BentoPanel>

      {queue.length === 0 ? (
        <EmptyState title="No devices are waiting for decoupling" description="Payment-cleared devices in the verification window will appear here." icon={Unlink} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Device ID</TableHead>
                  <TableHead>Payment Confirmed</TableHead>
                  <TableHead>Dealer Flag</TableHead>
                  <TableHead>Window Expires</TableHead>
                  <TableHead className="text-right">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {queue.map(req => (
                  <TableRow key={req.id || req.deviceId}>
                    <TableCell className="font-mono text-xs">{req.deviceId}</TableCell>
                    <TableCell>{req.paymentConfirmedAt ? new Date(req.paymentConfirmedAt).toLocaleDateString() : 'Not recorded'}</TableCell>
                    <TableCell>
                      {req.dealerFlaggedFraud ? <Badge variant="destructive">Fraud Flagged</Badge> : <Badge variant="success">Clean</Badge>}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <Timer className="h-4 w-4 text-muted-foreground" />
                        {req.windowExpiresAt ? new Date(req.windowExpiresAt).toLocaleString() : 'Not scheduled'}
                      </div>
                    </TableCell>
                    <TableCell className="text-right">
                      <Button onClick={() => { setPendingDecoupleId(req.id || req.deviceId); setIsTwoFactorOpen(true); }}>
                        <Unlink className="mr-2 h-4 w-4" /> Execute
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {queue.map(req => (
              <BentoPanel key={req.id || req.deviceId}>
                <div className="flex items-start justify-between gap-3">
                  <p className="font-mono text-xs text-emerald-950">{req.deviceId}</p>
                  {req.dealerFlaggedFraud ? <Badge variant="destructive">Fraud</Badge> : <Badge variant="success">Clean</Badge>}
                </div>
                <p className="mt-3 text-sm text-muted-foreground">Expires: {req.windowExpiresAt ? new Date(req.windowExpiresAt).toLocaleString() : 'Not scheduled'}</p>
                <Button className="mt-4 w-full" onClick={() => { setPendingDecoupleId(req.id || req.deviceId); setIsTwoFactorOpen(true); }}>Execute decoupling</Button>
              </BentoPanel>
            ))}
          </div>
        </>
      )}

      <TwoFactorModal
        isOpen={isTwoFactorOpen}
        onClose={() => setIsTwoFactorOpen(false)}
        onConfirm={code => pendingDecoupleId && decoupleMutation.mutate({ id: pendingDecoupleId, code })}
        title="Confirm Device Decoupling"
        description="Executing decoupling permanently removes MDM control and releases the device."
      />
    </div>
  );
};

export default Decoupling;
