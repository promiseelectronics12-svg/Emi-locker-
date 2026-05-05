import React from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { AlertCircle, FileText, Radio } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { useToast } from '@/hooks/use-toast';

const NeirQueue: React.FC = () => {
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['neir-queue'],
    queryFn: async () => {
      const { data } = await api.get('/admin/neir-queue');
      return normalizeList<any>(data.data ?? data);
    },
  });

  const reportMutation = useMutation({
    mutationFn: async (imei: string) => api.post('/admin/neir-queue/report', { imei }),
    onSuccess: () => {
      toast({ title: 'Reported', description: 'IMEI has been flagged for BTRC reporting' });
      query.refetch();
    },
    onError: () => {
      toast({ title: 'Error', description: 'Failed to report to NEIR', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading NEIR queue" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="NEIR queue could not be loaded" />;

  const queue = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="BTRC NEIR Reporting"
        description="Queue suspicious or fraud-confirmed IMEIs for regulatory reporting."
        action={<Button variant="outline" className="bg-white/70"><FileText className="mr-2 h-4 w-4" /> Export NEIR Excel</Button>}
      />

      {queue.length === 0 ? (
        <EmptyState title="No IMEIs are queued for NEIR" description="Devices confirmed for fraud or regulatory reporting will appear here." icon={Radio} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Device IMEI</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead>Flagged Date</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {queue.map(item => (
                  <TableRow key={item.id}>
                    <TableCell className="font-mono">{item.imei}</TableCell>
                    <TableCell><Badge variant="destructive">{item.reason}</Badge></TableCell>
                    <TableCell>{item.timestamp || item.created_at || 'Unknown'}</TableCell>
                    <TableCell><Badge variant="outline">{item.status || 'pending'}</Badge></TableCell>
                    <TableCell className="text-right">
                      <Button variant="outline" className="border-red-200 text-red-700" onClick={() => reportMutation.mutate(item.imei)} disabled={item.status === 'submitted'}>
                        <AlertCircle className="mr-1 h-4 w-4" /> Report
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {queue.map(item => (
              <BentoPanel key={item.id}>
                <div className="flex items-start justify-between gap-3">
                  <p className="font-mono text-sm text-emerald-950">{item.imei}</p>
                  <Badge variant="outline">{item.status || 'pending'}</Badge>
                </div>
                <p className="mt-3 text-sm text-muted-foreground">{item.reason}</p>
                <Button className="mt-4 w-full" variant="outline" onClick={() => reportMutation.mutate(item.imei)}>Report to BTRC</Button>
              </BentoPanel>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default NeirQueue;
