import React, { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { Search, Store } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
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

const statusVariant = (s: string) =>
  s === 'active' ? 'success' : s === 'suspended' ? 'destructive' : 'outline';

const Dealers: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['dealers', searchTerm, statusFilter],
    queryFn: async () => {
      const { data } = await api.get('/admin/dealers', {
        params: {
          search: searchTerm || undefined,
          status: statusFilter === 'ALL' ? undefined : statusFilter,
        },
      });
      return normalizeList<Dealer>(data.data ?? data);
    },
  });

  const statusMutation = useMutation({
    mutationFn: async ({ id, action, reason }: { id: string; action: 'suspend' | 'activate'; reason?: string }) => {
      if (action === 'suspend') return api.post(`/admin/dealers/${id}/suspend`, { reason: reason || 'Suspended from admin panel' });
      return api.post(`/admin/dealers/${id}/activate`);
    },
    onSuccess: (_, { action }) => {
      toast({ title: `Dealer ${action}d`, description: 'Status updated successfully' });
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Update failed', description: err.response?.data?.error || 'Could not update dealer', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading dealer network" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Dealers could not be loaded" />;

  const dealers = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Dealer Management"
        description="View and manage dealers across all reseller networks. Suspend or reinstate accounts."
      />

      <BentoPanel className="grid gap-3 md:grid-cols-[1fr_180px]">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search by name, email, or phone..."
            className="bg-white/70 pl-10"
            value={searchTerm}
            onChange={e => setSearchTerm(e.target.value)}
          />
        </div>
        <Select value={statusFilter} onValueChange={setStatusFilter}>
          <SelectTrigger className="bg-white/70">
            <SelectValue placeholder="Status" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All Statuses</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="suspended">Suspended</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
          </SelectContent>
        </Select>
      </BentoPanel>

      {dealers.length === 0 ? (
        <EmptyState
          title="No dealers found"
          description="Dealers are created by resellers through the reseller portal. They will appear here once registered."
          icon={Store}
        />
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
                  <TableHead className="text-right">Actions</TableHead>
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
                    <TableCell>
                      <Badge variant={statusVariant(dealer.status)}>{dealer.status}</Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex justify-end gap-2">
                        {dealer.status !== 'active' && (
                          <Button
                            variant="outline"
                            size="sm"
                            onClick={() => statusMutation.mutate({ id: dealer.id, action: 'activate' })}
                          >
                            Activate
                          </Button>
                        )}
                        {dealer.status !== 'suspended' && (
                          <Button
                            variant="destructive"
                            size="sm"
                            onClick={() => statusMutation.mutate({ id: dealer.id, action: 'suspend' })}
                          >
                            Suspend
                          </Button>
                        )}
                      </div>
                    </TableCell>
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
                  <Badge variant={statusVariant(dealer.status)}>{dealer.status}</Badge>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">Reseller: {dealer.reseller_name || 'Unassigned'}</p>
                <p className="text-xs text-muted-foreground">Devices: {dealer.device_count ?? 0}</p>
                <div className="mt-4 grid grid-cols-2 gap-2">
                  {dealer.status !== 'active' && (
                    <Button variant="outline" onClick={() => statusMutation.mutate({ id: dealer.id, action: 'activate' })}>
                      Activate
                    </Button>
                  )}
                  {dealer.status !== 'suspended' && (
                    <Button variant="destructive" onClick={() => statusMutation.mutate({ id: dealer.id, action: 'suspend' })}>
                      Suspend
                    </Button>
                  )}
                </div>
              </BentoPanel>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default Dealers;
