import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2, Link2, AlertTriangle, CheckCircle, Clock } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { api } from '@/lib/api'
import { formatCurrency, formatDate } from '@/lib/utils'
import { useTwoFactorStore } from '@/store/twoFactorStore'
import type { DecoupleEligibleDevice } from '@/types'

export function DecouplingPage() {
  const [page, setPage] = useState(1)
  const [pageSize] = useState(20)
  const [selectedDevice, setSelectedDevice] = useState<DecoupleEligibleDevice | null>(null)
  const [isConfirmModalOpen, setIsConfirmModalOpen] = useState(false)

  const queryClient = useQueryClient()
  const openTwoFactorModal = useTwoFactorStore((state) => state.openModal)

  const { data, isLoading } = useQuery<{
    devices: DecoupleEligibleDevice[]
    total: number
    page: number
    pageSize: number
    totalPages: number
  }>({
    queryKey: ['decoupling-devices', page, pageSize],
    queryFn: () => api.get('/api/admin/decoupling', { page, pageSize }),
  })

  const decoupleMutation = useMutation({
    mutationFn: (deviceId: string) =>
      api.post(`/api/admin/devices/${deviceId}/decouple`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['decoupling-devices'] })
      setIsConfirmModalOpen(false)
      setSelectedDevice(null)
    },
  })

  const handleExecuteDecouple = (device: DecoupleEligibleDevice) => {
    setSelectedDevice(device)
    setIsConfirmModalOpen(true)
  }

  const handleConfirmDecouple = () => {
    if (!selectedDevice) return

    openTwoFactorModal({
      action: `Execute Decoupling for device ${selectedDevice.imei}`,
      resourceId: selectedDevice.id,
      onSuccess: () => {
        decoupleMutation.mutate(selectedDevice.id)
      },
    })
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Decoupling Queue</h1>
        <p className="text-muted-foreground">
          Devices in 5-day window pending admin decoupling action
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Link2 className="h-5 w-5" />
            Devices Pending Decoupling
            {data?.total ? (
              <Badge variant="warning" className="ml-2">
                {data.total}
              </Badge>
            ) : null}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <Loader2 className="h-8 w-8 animate-spin text-primary" />
            </div>
          ) : !data || data.devices.length === 0 ? (
            <div className="text-center py-8">
              <CheckCircle className="h-12 w-12 text-green-500 mx-auto mb-4" />
              <p className="text-lg font-medium">No devices pending decoupling</p>
              <p className="text-muted-foreground">
                All devices are either in active EMI or have been decoupled
              </p>
            </div>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>IMEI</TableHead>
                    <TableHead>User</TableHead>
                    <TableHead>Device</TableHead>
                    <TableHead>Dealer</TableHead>
                    <TableHead>Final Payment</TableHead>
                    <TableHead>Window Ends</TableHead>
                    <TableHead>Days Left</TableHead>
                    <TableHead>Payment Status</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.devices.map((device) => (
                    <TableRow key={device.id}>
                      <TableCell className="font-mono">{device.imei}</TableCell>
                      <TableCell>
                        <div>
                          <p className="font-medium">{device.userName}</p>
                          <p className="text-sm text-muted-foreground">{device.userPhone}</p>
                        </div>
                      </TableCell>
                      <TableCell>{device.deviceModel}</TableCell>
                      <TableCell className="text-sm">{device.dealerName}</TableCell>
                      <TableCell className="text-sm">{formatDate(device.finalPaymentDate)}</TableCell>
                      <TableCell className="text-sm">{formatDate(device.windowEndDate)}</TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          {device.daysRemaining <= 1 ? (
                            <Badge variant="destructive">
                              <AlertTriangle className="h-3 w-3 mr-1" />
                              {device.daysRemaining}d
                            </Badge>
                          ) : device.daysRemaining <= 2 ? (
                            <Badge variant="warning">
                              <Clock className="h-3 w-3 mr-1" />
                              {device.daysRemaining}d
                            </Badge>
                          ) : (
                            <Badge variant="secondary">{device.daysRemaining}d</Badge>
                          )}
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="space-y-1">
                          <p className="text-sm font-medium text-green-600">
                            {formatCurrency(device.totalAmountPaid)} paid
                          </p>
                          <p className="text-sm text-muted-foreground">
                            {formatCurrency(device.remainingAmount)} remaining
                          </p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-2">
                          {device.fraudFlagged && (
                            <Badge variant="destructive" className="mb-2">
                              <AlertTriangle className="h-3 w-3 mr-1" />
                              Fraud Flagged
                            </Badge>
                          )}
                          <Button
                            size="sm"
                            onClick={() => handleExecuteDecouple(device)}
                            disabled={decoupleMutation.isPending}
                          >
                            Execute Decoupling
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              <div className="flex items-center justify-between pt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * pageSize + 1} to {Math.min(page * pageSize, data.total)} of {data.total} devices
                </p>
                <div className="flex gap-2">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                    disabled={page === 1}
                  >
                    Previous
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))}
                    disabled={page === data.totalPages}
                  >
                    Next
                  </Button>
                </div>
              </div>
            </>
          )}
        </CardContent>
      </Card>

      <Dialog open={isConfirmModalOpen} onOpenChange={setIsConfirmModalOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-destructive" />
              Confirm Decoupling
            </DialogTitle>
            <DialogDescription>
              This action will permanently release the device from EMI control. This action cannot be undone.
            </DialogDescription>
          </DialogHeader>

          {selectedDevice && (
            <div className="space-y-4">
              <div className="rounded-lg border p-4 space-y-2">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">IMEI:</span>
                  <span className="font-mono">{selectedDevice.imei}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">User:</span>
                  <span>{selectedDevice.userName}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Device:</span>
                  <span>{selectedDevice.deviceModel}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Total Paid:</span>
                  <span className="text-green-600 font-medium">
                    {formatCurrency(selectedDevice.totalAmountPaid)}
                  </span>
                </div>
              </div>

              <div className="bg-yellow-500/10 border border-yellow-500/20 rounded-lg p-4">
                <p className="text-sm text-yellow-700 dark:text-yellow-400">
                  <strong>Warning:</strong> Once decoupled, the device will be fully released and cannot be re locked through this system.
                </p>
              </div>

              <div className="bg-muted rounded-lg p-4">
                <p className="text-sm font-medium mb-2">What happens next:</p>
                <ol className="text-sm text-muted-foreground space-y-1 list-decimal list-inside">
                  <li>Server generates a signed Decouple Command with RTOC</li>
                  <li>Command sent to device via FCM</li>
                  <li>Device clears all lock policies and MDM</li>
                  <li>Device reboots as a clean normal Android phone</li>
                  <li>Device marked as DECOUPLED in audit log</li>
                </ol>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setIsConfirmModalOpen(false)
                setSelectedDevice(null)
              }}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              onClick={handleConfirmDecouple}
              disabled={decoupleMutation.isPending}
            >
              {decoupleMutation.isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Processing...
                </>
              ) : (
                'Execute Decoupling'
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}