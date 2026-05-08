import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  MapPin,
  Users,
  Key,
  Store,
  X,
  BarChart3,
  ChevronRight,
  Calendar,
} from 'lucide-react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
} from 'recharts';
import api from '@/api/axios';
import BangladeshMap from '@/components/admin/BangladeshMap';
import {
  PageHeader,
  BentoPanel,
  MetricTile,
  LoadingState,
  ErrorState,
  EmptyState,
} from '@/components/admin/Bento';
import { Button } from '@/components/ui/button';
import type {
  DistrictSummary,
  DistrictReseller,
  ResellerStatsData,
} from '@/types';

/* ─── Page ──────────────────────────────────────────────────────────────────── */

export default function Districts() {
  const [selectedDistrict, setSelectedDistrict] = useState<string | null>(null);
  const [statsResellerId, setStatsResellerId] = useState<string | null>(null);

  // District summary — always loaded (drives map colors)
  const summaryQ = useQuery<DistrictSummary[]>({
    queryKey: ['district-summary'],
    queryFn: async () => {
      const res = await api.get('/admin/districts/summary');
      return res.data?.data ?? [];
    },
  });

  // Resellers for selected district
  const resellersQ = useQuery<DistrictReseller[]>({
    queryKey: ['district-resellers', selectedDistrict],
    queryFn: async () => {
      const res = await api.get(`/admin/districts/${selectedDistrict}/resellers`);
      return res.data?.data ?? [];
    },
    enabled: !!selectedDistrict,
  });

  const handleDistrictClick = (d: string) =>
    setSelectedDistrict(prev => (prev === d ? null : d));

  return (
    <div className="space-y-6">
      <PageHeader
        title="Districts & Resellers"
        description="Geographic overview of the distribution network across Bangladesh."
      />

      <div className="grid gap-6 lg:grid-cols-5">
        {/* ─── Left: Map ──────────────────────────────── */}
        <BentoPanel className="lg:col-span-3">
          <h2 className="mb-4 flex items-center gap-2 text-sm font-semibold text-emerald-900">
            <MapPin className="h-4 w-4" />
            Bangladesh District Map
          </h2>

          {summaryQ.isLoading && <LoadingState title="Loading map data…" rows={6} />}
          {summaryQ.isError && (
            <ErrorState onRetry={() => summaryQ.refetch()} />
          )}
          {summaryQ.data && (
            <BangladeshMap
              districtData={summaryQ.data}
              selectedDistrict={selectedDistrict}
              onDistrictClick={handleDistrictClick}
            />
          )}
        </BentoPanel>

        {/* ─── Right: Reseller list ───────────────────── */}
        <BentoPanel className="lg:col-span-2">
          {!selectedDistrict ? (
            <EmptyState
              title="Select a district"
              description="Click any district on the map to see its resellers."
              icon={MapPin}
            />
          ) : (
            <>
              <div className="mb-4 flex items-center justify-between">
                <h2 className="text-lg font-semibold text-emerald-950">
                  {selectedDistrict}
                </h2>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setSelectedDistrict(null)}
                  className="text-muted-foreground"
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>

              {resellersQ.isLoading && <LoadingState title="Loading resellers…" rows={3} />}
              {resellersQ.isError && (
                <ErrorState onRetry={() => resellersQ.refetch()} />
              )}
              {resellersQ.data?.length === 0 && (
                <EmptyState
                  title="No resellers"
                  description={`No resellers registered in ${selectedDistrict} yet.`}
                  icon={Users}
                />
              )}

              <div className="space-y-3">
                {resellersQ.data?.map(r => (
                  <div
                    key={r.id}
                    className="group rounded-lg border border-emerald-100 bg-white/70 p-4 transition hover:border-emerald-300 hover:shadow-md"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="truncate font-medium text-emerald-950">{r.name}</p>
                          <StatusBadge status={r.status} />
                        </div>
                        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
                          <span className="flex items-center gap-1">
                            <Key className="h-3 w-3" />
                            {r.keys_distributed} keys
                          </span>
                          <span className="flex items-center gap-1">
                            <Store className="h-3 w-3" />
                            {r.dealer_count} dealers
                          </span>
                        </div>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="shrink-0 text-emerald-700 opacity-0 group-hover:opacity-100"
                        onClick={() => setStatsResellerId(r.id)}
                      >
                        Stats
                        <ChevronRight className="ml-1 h-4 w-4" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}
        </BentoPanel>
      </div>

      {/* ─── Stats Drawer ─────────────────────────────── */}
      {statsResellerId && (
        <ResellerStatsDrawer
          resellerId={statsResellerId}
          onClose={() => setStatsResellerId(null)}
        />
      )}
    </div>
  );
}

/* ─── Status Badge ──────────────────────────────────────────────────────────── */

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    active: 'bg-emerald-100 text-emerald-800',
    approved: 'bg-emerald-100 text-emerald-800',
    pending: 'bg-amber-100 text-amber-800',
    suspended: 'bg-red-100 text-red-800',
  };
  const key = status.toLowerCase();
  return (
    <span
      className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${
        colors[key] || 'bg-slate-100 text-slate-700'
      }`}
    >
      {key}
    </span>
  );
}

/* ─── Reseller Stats Drawer ─────────────────────────────────────────────────── */

function ResellerStatsDrawer({
  resellerId,
  onClose,
}: {
  resellerId: string;
  onClose: () => void;
}) {
  const [chartRange, setChartRange] = useState<'6' | '12'>('6');

  const statsQ = useQuery<ResellerStatsData>({
    queryKey: ['reseller-stats', resellerId],
    queryFn: async () => {
      const res = await api.get(`/admin/resellers/${resellerId}/stats`);
      return res.data?.data;
    },
    enabled: !!resellerId,
  });

  const chartData = statsQ.data
    ? (chartRange === '6' ? statsQ.data.monthly : statsQ.data.yearly).map(m => ({
        month: formatMonth(m.month),
        keys: m.keys_distributed,
      }))
    : [];

  const totalKeys = statsQ.data?.yearly.reduce((s, m) => s + m.keys_distributed, 0) ?? 0;
  const activeDealers = statsQ.data?.dealers.length ?? 0;
  const monthlyAvg = statsQ.data?.yearly.length
    ? Math.round(totalKeys / statsQ.data.yearly.length)
    : 0;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-40 bg-black/20 backdrop-blur-sm"
        onClick={onClose}
      />

      {/* Drawer */}
      <aside className="fixed inset-y-0 right-0 z-50 flex w-full max-w-lg flex-col overflow-y-auto border-l border-emerald-100 bg-white/95 shadow-2xl backdrop-blur-xl sm:w-[480px]">
        {/* Header */}
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-emerald-100 bg-white/90 px-6 py-4 backdrop-blur">
          <div className="min-w-0">
            {statsQ.data ? (
              <>
                <h2 className="truncate text-lg font-semibold text-emerald-950">
                  {statsQ.data.reseller.name}
                </h2>
                <p className="text-xs text-muted-foreground">
                  {statsQ.data.reseller.district ?? 'Unknown'} ·{' '}
                  <StatusBadge status={statsQ.data.reseller.status ?? ''} />
                </p>
              </>
            ) : (
              <div className="h-8 w-40 animate-pulse rounded bg-emerald-100" />
            )}
          </div>
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="h-5 w-5" />
          </Button>
        </div>

        <div className="space-y-6 p-6">
          {statsQ.isLoading && <LoadingState title="Loading stats…" rows={5} />}
          {statsQ.isError && <ErrorState onRetry={() => statsQ.refetch()} />}

          {statsQ.data && (
            <>
              {/* ─── Metric tiles ─── */}
              <div className="grid grid-cols-3 gap-3">
                <MetricTile
                  title="Total Keys"
                  value={totalKeys}
                  icon={Key}
                  tone="emerald"
                />
                <MetricTile
                  title="Dealers"
                  value={activeDealers}
                  icon={Store}
                  tone="sky"
                />
                <MetricTile
                  title="Monthly Avg"
                  value={monthlyAvg}
                  icon={BarChart3}
                  tone="amber"
                />
              </div>

              {/* ─── Chart ─── */}
              <BentoPanel>
                <div className="mb-4 flex items-center justify-between">
                  <h3 className="flex items-center gap-2 text-sm font-semibold text-emerald-900">
                    <Calendar className="h-4 w-4" />
                    Key Distribution
                  </h3>
                  <div className="flex rounded-lg border border-emerald-200 text-xs">
                    {(['6', '12'] as const).map(range => (
                      <button
                        key={range}
                        onClick={() => setChartRange(range)}
                        className={`px-3 py-1 transition ${
                          chartRange === range
                            ? 'bg-emerald-600 text-white'
                            : 'text-emerald-700 hover:bg-emerald-50'
                        } ${range === '6' ? 'rounded-l-md' : 'rounded-r-md'}`}
                      >
                        {range}M
                      </button>
                    ))}
                  </div>
                </div>

                {chartData.length === 0 ? (
                  <p className="py-8 text-center text-sm text-muted-foreground">
                    No distribution data yet.
                  </p>
                ) : (
                  <ResponsiveContainer width="100%" height={220}>
                    <BarChart data={chartData}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#d1fae5" />
                      <XAxis
                        dataKey="month"
                        tick={{ fontSize: 11, fill: '#6b7280' }}
                        axisLine={false}
                        tickLine={false}
                      />
                      <YAxis
                        tick={{ fontSize: 11, fill: '#6b7280' }}
                        axisLine={false}
                        tickLine={false}
                        allowDecimals={false}
                      />
                      <RechartsTooltip
                        contentStyle={{
                          borderRadius: '8px',
                          border: '1px solid #a7f3d0',
                          fontSize: 12,
                        }}
                      />
                      <Bar
                        dataKey="keys"
                        name="Keys Distributed"
                        fill="#10b981"
                        radius={[4, 4, 0, 0]}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                )}
              </BentoPanel>

              {/* ─── Dealers table ─── */}
              <BentoPanel>
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold text-emerald-900">
                  <Store className="h-4 w-4" />
                  Dealers ({statsQ.data.dealers.length})
                </h3>

                {statsQ.data.dealers.length === 0 ? (
                  <p className="py-6 text-center text-sm text-muted-foreground">
                    No dealers under this reseller.
                  </p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="border-b border-emerald-100 text-left text-xs font-medium text-muted-foreground">
                          <th className="pb-2 pr-3">Dealer</th>
                          <th className="pb-2 pr-3 text-right">Keys</th>
                          <th className="pb-2 pr-3 text-right">Devices</th>
                          <th className="pb-2 text-right">Last Active</th>
                        </tr>
                      </thead>
                      <tbody>
                        {statsQ.data.dealers.map(d => (
                          <tr
                            key={d.id}
                            className="border-b border-emerald-50 last:border-0"
                          >
                            <td className="py-2.5 pr-3">
                              <p className="font-medium text-emerald-950">{d.name}</p>
                              {d.phone && (
                                <p className="text-xs text-muted-foreground">{d.phone}</p>
                              )}
                            </td>
                            <td className="py-2.5 pr-3 text-right tabular-nums">
                              {d.keys_consumed}
                            </td>
                            <td className="py-2.5 pr-3 text-right tabular-nums">
                              {d.devices_bound}
                            </td>
                            <td className="py-2.5 text-right text-xs text-muted-foreground">
                              {d.last_active
                                ? new Date(d.last_active).toLocaleDateString()
                                : '—'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </BentoPanel>
            </>
          )}
        </div>
      </aside>
    </>
  );
}

/* ─── Helpers ───────────────────────────────────────────────────────────────── */

function formatMonth(yyyymm: string): string {
  const [year, month] = yyyymm.split('-');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return `${months[parseInt(month, 10) - 1]} '${year.slice(-2)}`;
}
