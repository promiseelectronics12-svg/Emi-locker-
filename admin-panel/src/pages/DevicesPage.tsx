import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Search, Filter, Loader2, ChevronLeft, ChevronRight, X } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { api } from '@/lib/api'
import { formatCurrency, formatDate } from '@/lib/utils'
import type { Device, DeviceState, LockState } from '@/types'

const lockStateColors: Record<LockState, string> = {
  ACTIVE: 'success',
  PARTIAL_LOCK: 'warning',
  FULL_LOCK: 'destructive',
  KIOSK_MODE: 'destructive',
  DEVICE_DECOUPLED: 'secondary',
  PERMANENTLY_LOCKED: 'destructive',
}

const deviceStateColors: Record<DeviceState, string> = {
  PENDING_KEY_ACTIVATION: 'secondary',
  EMI_ACTIVE: 'success',
  FINAL_PAYMENT_RECEIVED: 'info',
  DEALER_NOTIFIED: 'warning',
  PENDING_ADMIN_DECOUPLE: 'info',
  SUSPECTED_FRAUD: 'destructive',
  SUSPECTED_SALE: 'warning',
  OVERDUE_3: 'warning',
  OVERDUE_7: 'destructive',
}

export function DevicesPage() {
  const [search, setSearch] = useState('')
  const [stateFilter, setStateFilter] = useState<string>('')
  const [overdueFilter, setOverdueFilter] = useState<string>('')
  const [dealerFilter, setDealerFilter] = useState<string>('')
  const [page, setPage] = useState(1)
  const [pageSize] = useState(20)

  const { data, isLoading } = useQuery<{
    devices: Device[]
    total: number
    page: number
    pageSize: number
    totalPages: number
  }>({
    queryKey: ['devices', page, pageSize, search, stateFilter, overdueFilter, dealerFilter],
    queryFn: () =>
      api.get('/api/admin/devices', {
        page,
        pageSize,
        search: search || undefined,
        state: stateFilter || undefined,
        overdue: overdueFilter || undefined,
        dealerId: dealerFilter || undefined,
      }),
  })

  const handleClearFilters = () => {
    setSearch('')
    setStateFilter('')
    setOverdueFilter('')
    setDealerFilter('')
    setPage(1)
  }

  const hasActiveFilters = search || stateFilter || overdueFilter || dealerFilter

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Devices</h1>
        <p className="text-muted-foreground">Manage all enrolled devices</p>
      </div>

      <Card>
        <CardHeader className="pb-4">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search by IMEI, user name, or phone..."
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value)
                  setPage(1)
                }}
                className="pl-9"
              />
            </div>

            <div className="flex flex-wrap gap-2">
              <Select
                value={stateFilter}
                onValueChange={(value) => {
                  setStateFilter(value === 'all' ? '' : value)
                  setPage(1)
                }}
              >
                <SelectTrigger className="w-[180px]">
                  <Filter className="h-4 w-4 mr-2" />
                  <SelectValue placeholder="Lock State" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All States</SelectItem>
                  <SelectItem value="ACTIVE">Active</SelectItem>
                  <SelectItem value="PARTIAL_LOCK">Partial Lock</SelectItem>
                  <SelectItem value="FULL_LOCK">Full Lock</SelectItem>
                  <SelectItem value="KIOSK_MODE">Kiosk Mode</SelectItem>
                  <SelectItem value="DEVICE_DECOUPLED">Decoupled</SelectItem>
                </SelectContent>
              </Select>

              <Select
                value={overdueFilter}
                onValueChange={(value) => {
                  setOverdueFilter(value === 'all' ? '' : value)
                  setPage(1)
                }}
              >
                <SelectTrigger className="w-[180px]">
                  <SelectValue placeholder="Overdue Status" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All</SelectItem>
                  <SelectItem value="yes">Overdue Only</SelectItem>
                  <SelectItem value="no">Not Overdue</SelectItem>
                </SelectContent>
              </Select>

              <Input
                placeholder="Dealer ID"
                value={dealerFilter}
                onChange={(e) => {
                  setDealerFilter(e.target.value)
                  setPage(1)
                }}
                className="w-[140px]"
              />

              {hasActiveFilters && (
                <Button variant="ghost" onClick={handleClearFilters}>
                  <X className="h-4 w-4" />
                </Button>
              )}
            </div>
          </div>
        </CardHeader>

        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <Loader2 className="h-8 w-8 animate-spin text-primary" />
            </div>
          ) : !data ? (
            <div className="text-center py-8 text-muted-foreground">Failed to load devices</div>
          ) : data.devices.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No devices found</div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left py-3 px-4 font-medium">IMEI</th>
                      <th className="text-left py-3 px-4 font-medium">User</th>
                      <th className="text-left py-3 px-4 font-medium">Device</th>
                      <th className="text-left py-3 px-4 font-medium">Dealer</th>
                      <th className="text-left py-3 px-4 font-medium">EMI Status</th>
                      <th className="text-left py-3 px-4 font-medium">Lock State</th>
                      <th className="text-left py-3 px-4 font-medium">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.devices.map((device) => (
                      <tr key={device.id} className="border-b hover:bg-muted/50">
                        <td className="py-3 px-4 font-mono text-sm">{device.imei}</td>
                        <td className="py-3 px-4">
                          <div>
                            <p className="font-medium">{device.userName}</p>
                            <p className="text-sm text-muted-foreground">{device.userPhone}</p>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <div>
                            <p className="font-medium">{device.deviceModel}</p>
                            <p className="text-sm text-muted-foreground">{device.deviceManufacturer}</p>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-sm">{device.dealerName}</td>
                        <td className="py-3 px-4">
                          <div className="space-y-1">
                            <p className="text-sm">
                              {device.paidEMICount}/{device.totalMonths} paid
                            </p>
                            <p className="text-sm text-muted-foreground">
                              {formatCurrency(device.monthlyEMIAmount)}/mo
                            </p>
                            {device.isOverdue && (
                              <Badge variant="destructive" className="text-xs">
                                {device.overdueDays} days overdue
                              </Badge>
                            )}
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <div className="space-y-1">
                            <Badge variant={lockStateColors[device.lockState] as 'default' | 'secondary' | 'destructive' | 'outline' | 'success' | 'warning' | 'info'}>
                              {device.lockState.replace(/_/g, ' ')}
                            </Badge>
                            <Badge variant={deviceStateColors[device.deviceState] as 'default' | 'secondary' | 'destructive' | 'outline' | 'success' | 'warning' | 'info'}>
                              {device.deviceState.replace(/_/g, ' ')}
                            </Badge>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <Button asChild size="sm" variant="outline">
                            <Link to={`/devices/${device.id}`}>View Details</Link>
                          </Button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="flex items-center justify-between pt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * pageSize + 1} to {Math.min(page * pageSize, data.total)} of {data.total} devices
                </p>
                <div className="flex items-center gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                    disabled={page === 1}
                  >
                    <ChevronLeft className="h-4 w-4" />
                  </Button>
                  <span className="text-sm">
                    Page {page} of {data.totalPages}
                  </span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))}
                    disabled={page === data.totalPages}
                  >
                    <ChevronRight className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  )
}