import { useQuery } from '@tanstack/react-query'
import {
  Smartphone,
  AlertTriangle,
  Link2,
  CheckCircle,
  XCircle,
  TrendingUp,
  TrendingDown,
  Users,
  Loader2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import { formatCurrency } from '@/lib/utils'
import { PieChart, Pie, Cell, ResponsiveContainer, BarChart, Bar, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'

interface DashboardStats {
  totalDevices: number
  activeDevices: number
  partiallyLockedDevices: number
  fullyLockedDevices: number
  overdueDevices: number
  overdue3Days: number
  overdue7Days: number
  devicesInDecoupleWindow: number
  totalRevenue: number
  collectedEMI: number
  pendingEMI: number
  thisMonthRevenue: number
  lastMonthRevenue: number
  revenueChange: number
}

interface LockStateDistribution {
  state: string
  count: number
  percentage: number
}

export function DashboardPage() {
  const { data: stats, isLoading: statsLoading } = useQuery<DashboardStats>({
    queryKey: ['dashboard-stats'],
    queryFn: () => api.get('/api/admin/dashboard/stats'),
  })

  const { data: lockDistribution, isLoading: distLoading } = useQuery<LockStateDistribution[]>({
    queryKey: ['lock-distribution'],
    queryFn: () => api.get('/api/admin/dashboard/lock-distribution'),
  })

  const { data: recentAlerts, isLoading: alertsLoading } = useQuery<{
    alerts: Array<{
      id: string
      type: string
      severity: string
      deviceImei: string
      userName: string
      description: string
      createdAt: string
    }>
  }>({
    queryKey: ['recent-alerts'],
    queryFn: () => api.get('/api/admin/dashboard/recent-alerts'),
  })

  if (statsLoading || distLoading || alertsLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    )
  }

  if (!stats || !lockDistribution) {
    return <div className="text-muted-foreground">Failed to load dashboard data</div>
  }

  const COLORS = ['#22c55e', '#eab308', '#ef4444', '#8b5cf6', '#6b7280']

  const revenueChangePositive = stats.revenueChange >= 0

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <p className="text-muted-foreground">System overview and key metrics</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Total Devices</CardTitle>
            <Smartphone className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.totalDevices.toLocaleString()}</div>
            <p className="text-xs text-muted-foreground">
              {stats.activeDevices} active
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Overdue Devices</CardTitle>
            <AlertTriangle className="h-4 w-4 text-destructive" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold text-destructive">{stats.overdueDevices}</div>
            <p className="text-xs text-muted-foreground">
              {stats.overdue3Days} 3+ days, {stats.overdue7Days} 7+ days
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">Decouple Window</CardTitle>
            <Link2 className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{stats.devicesInDecoupleWindow}</div>
            <p className="text-xs text-muted-foreground">Pending admin action</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
            <CardTitle className="text-sm font-medium">EMI Collected</CardTitle>
            <TrendingUp className="h-4 w-4 text-muted-foreground" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{formatCurrency(stats.collectedEMI)}</div>
            <p className="text-xs text-muted-foreground">
              of {formatCurrency(stats.totalRevenue)} total
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Revenue Overview</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground">This Month</p>
                <p className="text-2xl font-bold">{formatCurrency(stats.thisMonthRevenue)}</p>
              </div>
              <div className="flex items-center gap-2">
                {revenueChangePositive ? (
                  <TrendingUp className="h-5 w-5 text-green-500" />
                ) : (
                  <TrendingDown className="h-5 w-5 text-red-500" />
                )}
                <span className={`text-sm font-medium ${revenueChangePositive ? 'text-green-500' : 'text-red-500'}`}>
                  {Math.abs(stats.revenueChange).toFixed(1)}%
                </span>
              </div>
            </div>
            <div className="space-y-2">
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Collected</span>
                <span className="font-medium">{formatCurrency(stats.collectedEMI)}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-muted-foreground">Pending</span>
                <span className="font-medium">{formatCurrency(stats.pendingEMI)}</span>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Lock State Distribution</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="h-[200px]">
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={lockDistribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={80}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="state"
                  >
                    {lockDistribution.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <div className="grid grid-cols-2 gap-2 mt-4">
              {lockDistribution.map((item, index) => (
                <div key={item.state} className="flex items-center gap-2 text-xs">
                  <div
                    className="w-3 h-3 rounded-full"
                    style={{ backgroundColor: COLORS[index % COLORS.length] }}
                  />
                  <span className="text-muted-foreground">{item.state}</span>
                  <span className="font-medium ml-auto">{item.count}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Device Lock Status</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={[
                  { name: 'Active', count: stats.activeDevices, fill: '#22c55e' },
                  { name: 'Partial Lock', count: stats.partiallyLockedDevices, fill: '#eab308' },
                  { name: 'Full Lock', count: stats.fullyLockedDevices, fill: '#ef4444' },
                ]}
                layout="vertical"
              >
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis type="number" />
                <YAxis type="category" dataKey="name" width={100} />
                <Tooltip />
                <Bar dataKey="count" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-destructive" />
            Recent Alerts
          </CardTitle>
        </CardHeader>
        <CardContent>
          {!recentAlerts || recentAlerts.alerts.length === 0 ? (
            <p className="text-muted-foreground text-center py-8">No recent alerts</p>
          ) : (
            <div className="space-y-4">
              {recentAlerts.alerts.slice(0, 5).map((alert) => (
                <div
                  key={alert.id}
                  className="flex items-start gap-4 p-3 rounded-lg border"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <Badge
                        variant={
                          alert.severity === 'CRITICAL' || alert.severity === 'HIGH'
                            ? 'destructive'
                            : alert.severity === 'MEDIUM'
                            ? 'warning'
                            : 'secondary'
                        }
                      >
                        {alert.type.replace(/_/g, ' ')}
                      </Badge>
                    </div>
                    <p className="text-sm font-medium">{alert.description}</p>
                    <p className="text-xs text-muted-foreground">
                      {alert.userName} • {alert.deviceImei}
                    </p>
                  </div>
                  <span className="text-xs text-muted-foreground">
                    {new Date(alert.createdAt).toLocaleString()}
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}