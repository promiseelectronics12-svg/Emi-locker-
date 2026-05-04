import { useDashboardStats } from '@/hooks/useApi';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { formatCurrency } from '@/lib/utils';
import { 
  Smartphone, 
  AlertTriangle, 
  DollarSign, 
  Users, 
  Key, 
  Unplug,
  Shield
} from 'lucide-react';
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend
} from 'recharts';

const COLORS = ['#22c55e', '#eab308', '#f97316', '#ef4444', '#8b5cf6'];

const LOCK_STATE_COLORS: Record<string, string> = {
  UNLOCKED: '#22c55e',
  PARTIAL_LOCK: '#eab308',
  FULL_LOCK: '#f97316',
  KIOSK_MODE: '#ef4444',
};

export function DashboardPage() {
  const { data: stats, isLoading, error } = useDashboardStats();

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  if (error || !stats) {
    return (
      <div className="flex flex-col items-center justify-center h-96 text-muted-foreground">
        <AlertTriangle className="h-12 w-12 mb-4" />
        <p>Failed to load dashboard data</p>
      </div>
    );
  }

  const lockStateData = Object.entries(stats.devicesByLockState).map(([state, count]) => ({
    name: state.replace('_', ' '),
    value: count,
    color: LOCK_STATE_COLORS[state] || COLORS[0],
  }));

  const deviceStateData = Object.entries(stats.devicesByState).map(([state, count]) => ({
    name: state.replace(/_/g, ' '),
    value: count,
  }));

  const statCards = [
    { title: 'Total Devices', value: stats.totalDevices, icon: Smartphone, color: 'text-blue-500' },
    { title: 'Overdue Devices', value: stats.overdueCount, icon: AlertTriangle, color: 'text-red-500' },
    { title: 'Total Revenue', value: formatCurrency(stats.totalRevenue), icon: DollarSign, color: 'text-green-500' },
    { title: 'Monthly Revenue', value: formatCurrency(stats.monthlyRevenue), icon: DollarSign, color: 'text-emerald-500' },
    { title: 'Active Resellers', value: stats.activeResellers, icon: Users, color: 'text-purple-500' },
    { title: 'Pending Key Requests', value: stats.pendingKeyRequests, icon: Key, color: 'text-amber-500' },
    { title: 'Pending Decoupling', value: stats.pendingDecoupling, icon: Unplug, color: 'text-orange-500' },
    { title: 'Active Security Events', value: stats.activeSecurityEvents, icon: Shield, color: 'text-red-600' },
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
        <p className="text-muted-foreground">System overview and key metrics</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        {statCards.map((stat) => (
          <Card key={stat.title}>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {stat.title}
              </CardTitle>
              <stat.icon className={`h-4 w-4 ${stat.color}`} />
            </CardHeader>
            <CardContent>
              <div className="text-2xl font-bold">{stat.value}</div>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="grid gap-6 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Devices by Lock State</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={lockStateData}
                    cx="50%"
                    cy="50%"
                    labelLine={false}
                    label={({ name, percent }) => `${name} ${(percent * 100).toFixed(0)}%`}
                    outerRadius={80}
                    fill="#8884d8"
                    dataKey="value"
                  >
                    {lockStateData.map((entry, index) => (
                      <Cell key={`cell-${index}`} fill={entry.color} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Devices by Status</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="h-80">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={deviceStateData} layout="vertical">
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis type="number" />
                  <YAxis type="category" dataKey="name" width={150} tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="value" fill="#6366f1" radius={[0, 4, 4, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Overdue Devices Alert</CardTitle>
        </CardHeader>
        <CardContent>
          {stats.overdueCount > 0 ? (
            <div className="flex items-center gap-4 p-4 bg-red-50 rounded-lg border border-red-200">
              <AlertTriangle className="h-8 w-8 text-red-600" />
              <div>
                <p className="font-medium text-red-900">
                  {stats.overdueCount} device(s) currently overdue
                </p>
                <p className="text-sm text-red-700">
                  Immediate attention may be required. Review devices in the Devices page.
                </p>
              </div>
              <Badge variant="destructive" className="ml-auto">
                {stats.overdueCount} Overdue
              </Badge>
            </div>
          ) : (
            <div className="flex items-center gap-4 p-4 bg-green-50 rounded-lg border border-green-200">
              <div className="h-8 w-8 rounded-full bg-green-500 flex items-center justify-center">
                <span className="text-white text-sm">✓</span>
              </div>
              <p className="text-green-900 font-medium">No overdue devices</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}