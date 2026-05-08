import React, { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { Search, ShieldCheck, UserPlus, Users } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { Reseller } from '@/types';
import { useToast } from '@/hooks/use-toast';

const Resellers: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['resellers', searchTerm],
    queryFn: async () => {
      const { data } = await api.get('/admin/resellers', { params: { search: searchTerm || undefined } });
      return normalizeList<Reseller>(data.data ?? data);
    },
  });

  const statusMutation = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: 'APPROVED' | 'SUSPENDED' }) => {
      if (status === 'APPROVED') return api.post(`/admin/resellers/${id}/approve`);
      return api.post(`/admin/resellers/${id}/suspend`, { reason: 'Suspended from admin panel prototype' });
    },
    onSuccess: () => {
      toast({ title: 'Reseller updated', description: 'Status changed successfully' });
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Update failed', description: err.response?.data?.error || 'Could not update reseller', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading reseller network" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Resellers could not be loaded" />;

  const resellers = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reseller Management"
        description="Approve, suspend, and inspect reseller key quotas across the dealer network."
        action={<Button><UserPlus className="mr-2 h-4 w-4" /> Invite Reseller</Button>}
      />

      <BentoPanel>
        <div className="relative max-w-xl">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search resellers by name or email..."
            className="bg-white/70 pl-10"
            value={searchTerm}
            onChange={event => setSearchTerm(event.target.value)}
          />
        </div>
      </BentoPanel>

      {resellers.length === 0 ? (
        <EmptyState title="No resellers are waiting in the network" description="New reseller applications and approved partners will appear here." icon={Users} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Quota</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {resellers.map(reseller => (
                  <TableRow key={reseller.id}>
                    <TableCell className="font-medium">{reseller.name || 'Unnamed reseller'}</TableCell>
                    <TableCell>{reseller.email}</TableCell>
                    <TableCell>
                      <div className="font-medium">{reseller.usedQuota ?? 0} / {reseller.monthlyQuota ?? 0}</div>
                      <div className="text-xs text-muted-foreground">
                        Activated history: {(reseller as any).activatedKeys ?? 0}
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge variant={reseller.status === 'APPROVED' || (reseller as any).status === 'active' ? 'success' : 'outline'}>
                        {reseller.status || (reseller as any).status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-2">
                        <Button variant="outline" size="sm" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'APPROVED' })}>
                          <ShieldCheck className="mr-1 h-4 w-4" /> Approve
                        </Button>
                        <Button variant="destructive" size="sm" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'SUSPENDED' })}>
                          Suspend
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {resellers.map(reseller => (
              <BentoPanel key={reseller.id}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium text-emerald-950">{reseller.name || 'Unnamed reseller'}</p>
                    <p className="truncate text-sm text-muted-foreground">{reseller.email}</p>
                  </div>
                  <Badge variant="outline">{reseller.status || (reseller as any).status}</Badge>
                </div>
                <p className="mt-4 text-sm text-muted-foreground">Quota: {reseller.usedQuota ?? 0} / {reseller.monthlyQuota ?? 0}</p>
                <p className="text-xs text-muted-foreground">Activated history: {(reseller as any).activatedKeys ?? 0}</p>
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Button variant="outline" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'APPROVED' })}>Approve</Button>
                  <Button variant="destructive" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'SUSPENDED' })}>Suspend</Button>
                </div>
              </BentoPanel>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default Resellers;
