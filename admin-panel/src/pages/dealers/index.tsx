import React, { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { AlertTriangle, MoreVertical, Search, Store } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { useToast } from '@/hooks/use-toast';

interface Dealer {
  id: string;
  name: string;
  email: string;
  phone: string;
  status: string;
  reseller_name: string | null;
  device_count: number;
  created_at: string;
}

interface SuspendTarget { id: string; name: string; type: 'dealer' | 'reseller' }

const statusVariant = (s: string) =>
  s === 'active' ? 'success' : s === 'suspended' ? 'destructive' : 'outline';

function SuspendConfirmDialog({
  target,
  onConfirm,
  onClose,
  loading,
}: {
  target: SuspendTarget | null;
  onConfirm: () => void;
  onClose: () => void;
  loading: boolean;
}) {
  const [typed, setTyped] = useState('');
  const correct = typed.trim().toUpperCase() === 'SUSPEND';

  return (
    <Dialog open={!!target} onOpenChange={open => { if (!open) { setTyped(''); onClose(); } }}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-red-600">
            <AlertTriangle className="h-5 w-5" /> Suspend {target?.type}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            You are about to suspend <span className="font-bold">{target?.name}</span>. This will immediately block their access. This action can be reversed.
          </div>
          <div className="space-y-2">
            <p className="text-sm text-slate-600">Type <span className="font-mono font-bold text-slate-800">SUSPEND</span> to confirm:</p>
            <Input
              value={typed}
              onChange={e => setTyped(e.target.value)}
              placeholder="SUSPEND"
              className="font-mono uppercase"
              autoFocus
              onKeyDown={e => e.key === 'Enter' && correct && onConfirm()}
            />
          </div>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => { setTyped(''); onClose(); }} disabled={loading}>Cancel</Button>
          <Button
            variant="destructive"
            onClick={() => { onConfirm(); setTyped(''); }}
            disabled={!correct || loading}
          >
            {loading ? 'Suspending…' : 'Confirm suspend'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

const Dealers: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [suspendTarget, setSuspendTarget] = useState<SuspendTarget | null>(null);
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['dealers', searchTerm, statusFilter],
    queryFn: async () => {
      const { data } = await api.get('/admin/dealers', {
        params: { search: searchTerm || undefined, status: statusFilter === 'ALL' ? undefined : statusFilter },
      });
      return normalizeList<Dealer>(data.data ?? data);
    },
  });

  const statusMutation = useMutation({
    mutationFn: async ({ id, action }: { id: string; action: 'suspend' | 'activate' }) => {
      if (action === 'suspend') return api.post(`/admin/dealers/${id}/suspend`, { reason: 'Suspended by admin' });
      return api.post(`/admin/dealers/${id}/activate`);
    },
    onSuccess: (_, { action }) => {
      toast({ title: `Dealer ${action}d`, description: 'Status updated' });
      setSuspendTarget(null);
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Update failed', description: err.response?.data?.error || 'Could not update', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading dealer network" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Dealers could not be loaded" />;

  const dealers = Array.isArray(query.data) ? query.data : [];

  function DealerMenu({ dealer }: { dealer: Dealer }) {
    return (
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" size="icon" className="h-8 w-8">
            <MoreVertical className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {dealer.status !== 'active' && (
            <DropdownMenuItem onClick={() => statusMutation.mutate({ id: dealer.id, action: 'activate' })}>
              Activate
            </DropdownMenuItem>
          )}
          {dealer.status !== 'suspended' && (
            <>
              {dealer.status === 'active' && <DropdownMenuSeparator />}
              <DropdownMenuItem
                className="text-red-600 focus:text-red-600"
                onClick={() => setSuspendTarget({ id: dealer.id, name: dealer.name || 'Dealer', type: 'dealer' })}
              >
                Suspend…
              </DropdownMenuItem>
            </>
          )}
        </DropdownMenuContent>
      </DropdownMenu>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader title="Dealer Management" description="View and manage dealers across all reseller networks." />

      <BentoPanel className="grid gap-3 md:grid-cols-[1fr_180px]">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder="Search by name, email, or phone..." className="bg-white/70 pl-10" value={searchTerm} onChange={e => setSearchTerm(e.target.value)} />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="bg-white/70"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All Statuses</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="suspended">Suspended</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
          </SelectContent>
        </Select>
      </BentoPanel>

      {dealers.length === 0 ? (
        <EmptyState title="No dealers found" description="Dealers are created by resellers through the reseller portal." icon={Store} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Contact</TableHead>
                  <TableHead>Reseller</TableHead>
                  <TableHead>Devices</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {dealers.map(dealer => (
                  <TableRow key={dealer.id}>
                    <TableCell className="font-medium">{dealer.name || 'Unnamed'}</TableCell>
                    <TableCell>
                      <div className="text-sm">{dealer.phone || '—'}</div>
                      <div className="text-xs text-muted-foreground">{dealer.email || '—'}</div>
                    </TableCell>
                    <TableCell className="text-sm text-muted-foreground">{dealer.reseller_name || 'Unassigned'}</TableCell>
                    <TableCell>{dealer.device_count ?? 0}</TableCell>
                    <TableCell><Badge variant={statusVariant(dealer.status)}>{dealer.status}</Badge></TableCell>
                    <TableCell><DealerMenu dealer={dealer} /></TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {dealers.map(dealer => (
              <BentoPanel key={dealer.id}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium text-emerald-950">{dealer.name || 'Unnamed'}</p>
                    <p className="text-sm text-muted-foreground">{dealer.phone || '—'}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant={statusVariant(dealer.status)}>{dealer.status}</Badge>
                    <DealerMenu dealer={dealer} />
                  </div>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">Reseller: {dealer.reseller_name || 'Unassigned'} · Devices: {dealer.device_count ?? 0}</p>
              </BentoPanel>
            ))}
          </div>
        </>
      )}

      <SuspendConfirmDialog
        target={suspendTarget}
        onConfirm={() => suspendTarget && statusMutation.mutate({ id: suspendTarget.id, action: 'suspend' })}
        onClose={() => setSuspendTarget(null)}
        loading={statusMutation.isPending}
      />
    </div>
  );
};

export default Dealers;
