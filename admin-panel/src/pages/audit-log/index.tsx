import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { FileText, Search } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Input } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { AuditLog } from '@/types';

const AuditLogPage: React.FC = () => {
  const [searchTerm, setSearchTerm] = React.useState('');

  const query = useQuery({
    queryKey: ['audit-logs', searchTerm],
    queryFn: async () => {
      const { data } = await api.get('/admin/audit-log', { params: { search: searchTerm || undefined } });
      return normalizeList<AuditLog>(data.data ?? data);
    },
  });

  if (query.isLoading) return <LoadingState title="Loading audit log" rows={6} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Audit log could not be loaded" />;

  const logs = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader title="Immutable Audit Log" description="Operational record of admin actions, command decisions, and security-sensitive events." />

      <BentoPanel>
        <div className="relative max-w-xl">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input placeholder="Search logs..." className="bg-white/70 pl-10" value={searchTerm} onChange={event => setSearchTerm(event.target.value)} />
        </div>
      </BentoPanel>

      {logs.length === 0 ? (
        <EmptyState title="No audit records are available" description="Admin actions will be written here once sensitive operations begin." icon={FileText} />
      ) : (
        <BentoPanel className="p-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Timestamp</TableHead>
                <TableHead>Actor</TableHead>
                <TableHead>Action</TableHead>
                <TableHead>Target</TableHead>
                <TableHead>Details</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {logs.map((log: any) => (
                <TableRow key={log.id}>
                  <TableCell className="text-xs font-mono">{log.timestamp || log.created_at || 'Unknown'}</TableCell>
                  <TableCell>{log.adminId || log.actor || log.actor_name || 'System'}</TableCell>
                  <TableCell className="font-medium">{log.action}</TableCell>
                  <TableCell className="font-mono text-xs">{log.targetId || log.target_id || log.device_id || 'None'}</TableCell>
                  <TableCell className="max-w-md truncate text-sm text-muted-foreground">{log.details || JSON.stringify(log.metadata || {})}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </BentoPanel>
      )}
    </div>
  );
};

export default AuditLogPage;
