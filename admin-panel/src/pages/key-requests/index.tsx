import React from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { CheckCircle, Clock, Key, XCircle } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { KeyRequest } from '@/types';
import { useToast } from '@/hooks/use-toast';

const KeyRequests: React.FC = () => {
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['key-requests'],
    queryFn: async () => {
      const { data } = await api.get('/admin/key-requests');
      return normalizeList<KeyRequest>(data.data ?? data);
    },
  });

  const resolveMutation = useMutation({
    mutationFn: async ({ id, status, quantity }: { id: string; status: 'APPROVED' | 'REJECTED'; quantity?: number }) => {
      if (status === 'APPROVED') return api.post(`/admin/key-requests/${id}/approve`, { quantity });
      return api.post(`/admin/key-requests/${id}/reject`, { rejectionReason: 'Rejected from admin panel prototype' });
    },
    onSuccess: () => {
      toast({ title: 'Request processed', description: 'Key request status updated' });
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Request failed', description: err.response?.data?.error || 'Could not process request', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading key approval queue" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Key requests could not be loaded" />;

  const requests = Array.isArray(query.data) ? query.data : [];
  const pendingCount = requests.filter(request => request.status === 'PENDING' || (request as any).status === 'pending').length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Key Approval Queue"
        description="Review reseller key requests and enforce controlled activation-key release."
        action={<Badge className="bg-emerald-600">{pendingCount} Pending</Badge>}
      />

      {requests.length === 0 ? (
        <EmptyState title="No key requests are waiting" description="Reseller key requests will appear here for approval or rejection." icon={Key} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Reseller</TableHead>
                  <TableHead>Quantity</TableHead>
                  <TableHead>Justification</TableHead>
                  <TableHead>Requested</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map(request => {
                  const pending = request.status === 'PENDING' || (request as any).status === 'pending';
                  return (
                    <TableRow key={request.id}>
                      <TableCell className="font-mono text-xs">{request.resellerId || (request as any).reseller_id}</TableCell>
                      <TableCell>{request.quantity} keys</TableCell>
                      <TableCell className="max-w-xs truncate">{request.justification || 'No justification provided'}</TableCell>
                      <TableCell>{request.createdAt ? new Date(request.createdAt).toLocaleString() : 'Unknown'}</TableCell>
                      <TableCell className="text-right">
                        {pending ? (
                          <div className="flex justify-end gap-2">
                            <Button variant="outline" size="sm" className="border-emerald-200 text-emerald-700" onClick={() => resolveMutation.mutate({ id: request.id, status: 'APPROVED', quantity: request.quantity })}>
                              <CheckCircle className="mr-1 h-4 w-4" /> Approve
                            </Button>
                            <Button variant="outline" size="sm" className="border-red-200 text-red-700" onClick={() => resolveMutation.mutate({ id: request.id, status: 'REJECTED' })}>
                              <XCircle className="mr-1 h-4 w-4" /> Reject
                            </Button>
                          </div>
                        ) : (
                          <Badge variant="outline"><Clock className="mr-1 h-3 w-3" /> {request.status}</Badge>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {requests.map(request => (
              <BentoPanel key={request.id}>
                <div className="flex items-center justify-between gap-3">
                  <p className="font-semibold text-emerald-950">{request.quantity} keys</p>
                  <Badge variant="outline">{request.status}</Badge>
                </div>
                <p className="mt-2 truncate text-sm text-muted-foreground">{request.justification || 'No justification provided'}</p>
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Button variant="outline" onClick={() => resolveMutation.mutate({ id: request.id, status: 'APPROVED', quantity: request.quantity })}>Approve</Button>
                  <Button variant="outline" className="border-red-200 text-red-700" onClick={() => resolveMutation.mutate({ id: request.id, status: 'REJECTED' })}>Reject</Button>
                </div>
              </BentoPanel>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default KeyRequests;
