import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Activity, Clock, DollarSign, ShieldAlert, Smartphone, Users } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, MetricTile, PageHeader } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import api from '@/api/axios';
import { formatCurrency, formatDate } from '@/lib/utils';

const Dashboard: React.FC = () => {
  const {
    data: stats,
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: async () => {
      const { data } = await api.get('/admin/dashboard');
      return data.data ?? data;
    },
  });

  if (isLoading) return <LoadingState title="Loading dashboard intelligence" rows={5} />;
  if (isError) return <ErrorState onRetry={() => refetch()} title="Dashboard could not be loaded" />;

  const recentEvents = Array.isArray(stats?.recentEvents) ? stats.recentEvents : [];
  const totalDevices = Number(stats?.totalDevices || 0);
  const lockedCount = Number(stats?.lockedCount || 0);
  const unlockedCount = Math.max(totalDevices - lockedCount, 0);

  return (
    <div className="space-y-6">
      <PageHeader
        title="System Overview"
        description="Live operational snapshot for device binding, reseller activity, EMI risk, and security monitoring."
        action={<Badge className="bg-emerald-600">Prototype online</Badge>}
      />

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <MetricTile title="Total Devices" value={totalDevices} icon={Smartphone} helper="Bound or enrolled inventory" tone="emerald" />
        <MetricTile title="Overdue Count" value={stats?.overdueCount || 0} icon={Clock} helper="Accounts requiring attention" tone="amber" />
        <MetricTile title="Monthly Revenue" value={formatCurrency(Number(stats?.monthlyRevenue || stats?.revenue || 0))} icon={DollarSign} helper="Confirmed in the last 30 days" tone="sky" />
        <MetricTile title="Security Alerts" value={stats?.activeAlerts || 0} icon={ShieldAlert} helper="Events seen in the last 7 days" tone="rose" />
      </div>

      <div className="grid gap-4 xl:grid-cols-[1.1fr_0.9fr]">
        <BentoPanel>
          <div className="flex items-center justify-between gap-4">
            <div>
              <h2 className="text-lg font-semibold text-emerald-950">Device Lock Distribution</h2>
              <p className="text-sm text-muted-foreground">Empty-friendly readout for lock-state coverage.</p>
            </div>
            <Activity className="h-5 w-5 text-emerald-700" />
          </div>
          {totalDevices === 0 ? (
            <EmptyState
              title="No device has ever been bound or used."
              description="Once dealers or resellers enroll phones, this panel will show unlocked, locked, and decoupled distribution."
              icon={Smartphone}
            />
          ) : (
            <div className="mt-6 grid gap-3">
              {[
                { label: 'Unlocked', value: unlockedCount, className: 'bg-emerald-500' },
                { label: 'Locked', value: lockedCount, className: 'bg-red-500' },
              ].map(item => (
                <div key={item.label}>
                  <div className="mb-2 flex items-center justify-between text-sm">
                    <span>{item.label}</span>
                    <span className="font-medium">{item.value}</span>
                  </div>
                  <div className="h-3 rounded-lg bg-emerald-50">
                    <div
                      className={`h-full rounded-lg ${item.className}`}
                      style={{ width: `${Math.max((item.value / totalDevices) * 100, 4)}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </BentoPanel>

        <BentoPanel>
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-lg font-semibold text-emerald-950">Recent Security Events</h2>
              <p className="text-sm text-muted-foreground">Latest authentication or device-risk signals.</p>
            </div>
            <ShieldAlert className="h-5 w-5 text-red-600" />
          </div>
          {recentEvents.length === 0 ? (
            <EmptyState title="No security events yet" description="The alert stream is quiet." icon={ShieldAlert} />
          ) : (
            <div className="mt-5 space-y-3">
              {recentEvents.map((event: any) => (
                <div key={event.id} className="rounded-lg border border-white/70 bg-white/70 p-3">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-emerald-950">{event.type || event.event_type}</p>
                      <p className="text-xs text-muted-foreground">{event.timestamp ? formatDate(event.timestamp) : 'No timestamp'}</p>
                    </div>
                    <Badge variant={String(event.severity).toUpperCase() === 'CRITICAL' ? 'destructive' : 'outline'}>
                      {event.severity || 'INFO'}
                    </Badge>
                  </div>
                </div>
              ))}
            </div>
          )}
        </BentoPanel>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <BentoPanel tone="emerald">
          <Users className="h-5 w-5 text-emerald-700" />
          <p className="mt-4 text-sm text-muted-foreground">Active resellers</p>
          <p className="mt-1 text-2xl font-semibold text-emerald-950">{stats?.activeResellers || 0}</p>
        </BentoPanel>
        <BentoPanel tone="warning">
          <Clock className="h-5 w-5 text-amber-700" />
          <p className="mt-4 text-sm text-muted-foreground">Pending decoupling</p>
          <p className="mt-1 text-2xl font-semibold text-emerald-950">{stats?.decouplingPending || 0}</p>
        </BentoPanel>
        <BentoPanel>
          <Activity className="h-5 w-5 text-sky-700" />
          <p className="mt-4 text-sm text-muted-foreground">Total users</p>
          <p className="mt-1 text-2xl font-semibold text-emerald-950">{stats?.totalUsers || 0}</p>
        </BentoPanel>
      </div>
    </div>
  );
};

export default Dashboard;
