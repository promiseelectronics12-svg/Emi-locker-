import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { ExternalLink, Filter, Search, Smartphone } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { Device } from '@/types';

const lockBadgeVariant = (state?: string) => {
  if (state === 'FULL_LOCK') return 'destructive';
  if (state === 'UNLOCKED' || state === 'NONE') return 'success';
  return 'outline';
};

const Devices: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [filterState, setFilterState] = useState('ALL');

  const query = useQuery({
    queryKey: ['devices', searchTerm, filterState],
    queryFn: async () => {
      const { data } = await api.get('/admin/devices', {
        params: {
          search: searchTerm || undefined,
          status: filterState === 'ALL' ? undefined : filterState,
        },
      });
      return normalizeList<Device>(data.data ?? data);
    },
  });

  if (query.isLoading) return <LoadingState title="Loading devices" rows={6} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Devices could not be loaded" />;

  const devices = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Device Management"
        description="Track bound phones, lock state, dealer ownership, and EMI health."
        action={<Button variant="outline" className="bg-white/70">Export CSV</Button>}
      />

      <BentoPanel className="grid gap-3 md:grid-cols-[1fr_220px]">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search IMEI, model, owner, or phone..."
            className="bg-white/70 pl-10"
            value={searchTerm}
            onChange={event => setSearchTerm(event.target.value)}
          />
        </div>
        <Select value={filterState} onValueChange={setFilterState}>
          <SelectTrigger className="bg-white/70">
            <Filter className="mr-2 h-4 w-4" />
            <SelectValue placeholder="Filter by state" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="ALL">All States</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="locked">Locked</SelectItem>
            <SelectItem value="pending_decouple">Pending Decouple</SelectItem>
            <SelectItem value="decoupled">Decoupled</SelectItem>
          </SelectContent>
        </Select>
      </BentoPanel>

      {devices.length === 0 ? (
        <EmptyState
          title="No device has ever been bound or used."
          description="After a dealer enrolls a customer phone, it will appear here with lock state, dealer assignment, and EMI status."
          icon={Smartphone}
        />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>IMEI</TableHead>
                  <TableHead>Model</TableHead>
                  <TableHead>State</TableHead>
                  <TableHead>Dealer</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {devices.map(device => (
                  <TableRow key={device.id}>
                    <TableCell className="font-mono">{device.imei || 'Not captured'}</TableCell>
                    <TableCell>{device.model || 'Unknown model'}</TableCell>
                    <TableCell>
                      <Badge variant={lockBadgeVariant(device.lockState || (device as any).lock_level)}>
                        {device.lockState || (device as any).lock_level || 'NONE'}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-xs">{device.dealerId || (device as any).dealer_id || 'Unassigned'}</TableCell>
                    <TableCell>
                      {device.isOverdue ? (
                        <Badge variant="destructive">Overdue {device.overdueDays || 0}d</Badge>
                      ) : (
                        <Badge variant="outline" className="border-emerald-200 text-emerald-700">On Track</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button asChild variant="ghost" size="sm">
                        <Link to={`/devices/${device.id}`}>
                          Details <ExternalLink className="ml-2 h-3.5 w-3.5" />
                        </Link>
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {devices.map(device => (
              <BentoPanel key={device.id}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="truncate font-mono text-sm text-emerald-950">{device.imei || 'No IMEI'}</p>
                    <p className="mt-1 text-sm text-muted-foreground">{device.model || 'Unknown model'}</p>
                  </div>
                  <Badge variant={lockBadgeVariant(device.lockState || (device as any).lock_level)}>
                    {device.lockState || (device as any).lock_level || 'NONE'}
                  </Badge>
                </div>
                <Button asChild className="mt-4 w-full">
                  <Link to={`/devices/${device.id}`}>Open device</Link>
                </Button>
              </BentoPanel>
            ))}
          </div>
        </>
      )}
    </div>
  );
};

export default Devices;
