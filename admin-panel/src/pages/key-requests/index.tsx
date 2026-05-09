import React, { useEffect, useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { CheckCircle, Clock, Diamond, Key, Star, XCircle } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { KeyRequest } from '@/types';
import { useToast } from '@/hooks/use-toast';
import { useAdminSSE } from '@/contexts/AdminSSEContext';

type Tier = 'standard' | 'premium' | 'vip';

interface PendingApproval {
  id: string;
  quantity: number;
  tier: Tier;
  resellerName: string;
}

const TIER_META: Record<Tier, { label: string; gradient: string; text: string; icon: React.ReactNode }> = {
  standard: { label: 'Standard', gradient: 'from-[#8E8E93] to-[#AEAEB2]', text: 'text-[#8E8E93]', icon: <Key className="h-4 w-4 text-white" /> },
  premium:  { label: 'Premium',  gradient: 'from-[#0A84FF] to-[#30B0C7]', text: 'text-[#0A84FF]', icon: <Star className="h-4 w-4 text-white" /> },
  vip:      { label: 'VIP',      gradient: 'from-[#BF5AF2] to-[#D97706]', text: 'text-[#BF5AF2]', icon: <Diamond className="h-4 w-4 text-white" /> },
};

function TierBadge({ tier }: { tier: Tier }) {
  const meta = TIER_META[tier] || TIER_META.standard;
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className={`inline-flex h-5 w-5 items-center justify-center rounded bg-gradient-to-br ${meta.gradient}`}>
        {meta.icon}
      </span>
      <span className={`text-sm font-bold ${meta.text}`}>{meta.label}</span>
    </span>
  );
}

const KeyRequests: React.FC = () => {
  const { toast } = useToast();
  const { subscribe } = useAdminSSE();
  const [pendingApproval, setPendingApproval] = useState<PendingApproval | null>(null);

  const query = useQuery({
    queryKey: ['key-requests'],
    queryFn: async () => {
      const { data } = await api.get('/admin/key-requests');
      return normalizeList<KeyRequest>(data.data ?? data);
    },
  });

  // Auto-refresh when a new key request arrives via SSE
  useEffect(() => {
    const unsub = subscribe('key_requested', () => query.refetch());
    return unsub;
  }, [subscribe]);

  const resolveMutation = useMutation({
    mutationFn: async ({ id, status, quantity }: { id: string; status: 'APPROVED' | 'REJECTED'; quantity?: number }) => {
      if (status === 'APPROVED') return api.post(`/admin/key-requests/${id}/approve`, { quantity });
      return api.post(`/admin/key-requests/${id}/reject`, { rejectionReason: 'Rejected from admin panel' });
    },
    onSuccess: () => {
      toast({ title: 'Request processed', description: 'Key request status updated' });
      setPendingApproval(null);
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Request failed', description: err.response?.data?.error || 'Could not process request', variant: 'destructive' });
    },
  });

  function openApprovalDialog(request: KeyRequest) {
    const raw = request as any;
    const tier = (['standard', 'premium', 'vip'].includes(raw.tier) ? raw.tier : 'standard') as Tier;
    setPendingApproval({
      id: raw.id || request.id,
      quantity: raw.quantity || request.quantity,
      tier,
      resellerName: raw.reseller_name || raw.resellerName || raw.reseller_id || request.id,
    });
  }

  if (query.isLoading) return <LoadingState title="Loading key approval queue" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Key requests could not be loaded" />;

  const requests = Array.isArray(query.data) ? query.data : [];
  const pendingCount = requests.filter(r => r.status === 'PENDING' || (r as any).status === 'pending').length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Key Approval Queue"
        description="Review reseller key requests. Tier is set by the reseller — approve or reject only."
        action={<Badge className="bg-emerald-600">{pendingCount} Pending</Badge>}
      />

      {requests.length === 0 ? (
        <EmptyState title="No key requests are waiting" description="Reseller key requests will appear here." icon={Key} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Reseller</TableHead>
                  <TableHead>Qty</TableHead>
                  <TableHead>Tier</TableHead>
                  <TableHead>Justification</TableHead>
                  <TableHead>Requested</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map(request => {
                  const raw = request as any;
                  const pending = raw.status === 'PENDING' || raw.status === 'pending';
                  const tier = (['standard', 'premium', 'vip'].includes(raw.tier) ? raw.tier : 'standard') as Tier;
                  return (
                    <TableRow key={request.id}>
                      <TableCell className="font-medium">{(request as any).reseller_name || (request as any).resellerId || '—'}</TableCell>
                      <TableCell className="font-bold">{request.quantity}</TableCell>
                      <TableCell><TierBadge tier={tier} /></TableCell>
                      <TableCell className="max-w-xs truncate text-sm">{request.justification || '—'}</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{request.createdAt ? new Date(request.createdAt).toLocaleString() : '—'}</TableCell>
                      <TableCell className="text-right">
                        {pending ? (
                          <div className="flex justify-end gap-2">
                            <Button variant="outline" size="sm" className="border-emerald-200 text-emerald-700" onClick={() => openApprovalDialog(request)}>
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
            {requests.map(request => {
              const raw2 = request as any;
              const tier = (['standard', 'premium', 'vip'].includes(raw2.tier) ? raw2.tier : 'standard') as Tier;
              return (
                <BentoPanel key={request.id}>
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="font-semibold">{request.quantity} keys</p>
                      <TierBadge tier={tier} />
                    </div>
                    <Badge variant="outline">{request.status}</Badge>
                  </div>
                  <p className="mt-2 truncate text-sm text-muted-foreground">{request.justification || '—'}</p>
                  <div className="mt-4 grid grid-cols-2 gap-2">
                    <Button variant="outline" onClick={() => openApprovalDialog(request)}>Approve</Button>
                    <Button variant="outline" className="border-red-200 text-red-700" onClick={() => resolveMutation.mutate({ id: request.id, status: 'REJECTED' })}>Reject</Button>
                  </div>
                </BentoPanel>
              );
            })}
          </div>
        </>
      )}

      {/* Approval confirmation — tier locked, admin cannot change it */}
      <Dialog open={!!pendingApproval} onOpenChange={open => { if (!open) setPendingApproval(null); }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle>Approve {pendingApproval?.quantity} keys</DialogTitle>
            <p className="text-sm text-muted-foreground">
              The reseller requested this tier. You cannot change it — only approve or reject.
            </p>
          </DialogHeader>
          {pendingApproval && (
            <div className="rounded-xl border bg-slate-50 p-4 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm text-slate-500">Quantity</span>
                <span className="font-bold">{pendingApproval.quantity} keys</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-slate-500">Tier</span>
                <TierBadge tier={pendingApproval.tier} />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-slate-500">Reseller</span>
                <span className="text-sm font-medium truncate max-w-[160px]">{pendingApproval.resellerName}</span>
              </div>
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setPendingApproval(null)} disabled={resolveMutation.isPending}>
              Cancel
            </Button>
            <Button
              className="bg-emerald-600 hover:bg-emerald-700"
              onClick={() => pendingApproval && resolveMutation.mutate({ id: pendingApproval.id, status: 'APPROVED', quantity: pendingApproval.quantity })}
              disabled={resolveMutation.isPending}
            >
              {resolveMutation.isPending ? 'Approving…' : 'Approve'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default KeyRequests;
