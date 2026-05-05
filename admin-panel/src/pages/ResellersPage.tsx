import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Search, Loader2, ChevronLeft, ChevronRight, X, Plus, Check, Ban } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Label } from '@/components/ui/label'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { api } from '@/lib/api'
import { formatDate } from '@/lib/utils'
import type { Reseller, ResellerListResponse } from '@/types'

const quotaSchema = z.object({
  monthlyQuota: z.number().min(1, 'Quota must be at least 1'),
})

type QuotaFormData = z.infer<typeof quotaSchema>

export function ResellersPage() {
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<string>('')
  const [page, setPage] = useState(1)
  const [pageSize] = useState(20)
  const [selectedReseller, setSelectedReseller] = useState<Reseller | null>(null)
  const [isQuotaModalOpen, setIsQuotaModalOpen] = useState(false)

  const queryClient = useQueryClient()

  const { data, isLoading } = useQuery<ResellerListResponse>({
    queryKey: ['resellers', page, pageSize, search, statusFilter],
    queryFn: () =>
      api.get('/api/admin/resellers', {
        page,
        pageSize,
        search: search || undefined,
        status: statusFilter || undefined,
      }),
  })

  const suspendMutation = useMutation({
    mutationFn: (resellerId: string) =>
      api.post(`/api/admin/resellers/${resellerId}/suspend`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['resellers'] })
    },
  })

  const activateMutation = useMutation({
    mutationFn: (resellerId: string) =>
      api.post(`/api/admin/resellers/${resellerId}/activate`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['resellers'] })
    },
  })

  const quotaForm = useForm<QuotaFormData>({
    resolver: zodResolver(quotaSchema),
  })

  const handleOpenQuotaModal = (reseller: Reseller) => {
    setSelectedReseller(reseller)
    quotaForm.setValue('monthlyQuota', reseller.monthlyQuota)
    setIsQuotaModalOpen(true)
  }

  const handleUpdateQuota = async (data: QuotaFormData) => {
    if (!selectedReseller) return

    await api.post(`/api/admin/resellers/${selectedReseller.id}/quota`, {
      monthlyQuota: data.monthlyQuota,
    })

    queryClient.invalidateQueries({ queryKey: ['resellers'] })
    setIsQuotaModalOpen(false)
    setSelectedReseller(null)
    quotaForm.reset()
  }

  const handleClearFilters = () => {
    setSearch('')
    setStatusFilter('')
    setPage(1)
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Resellers</h1>
        <p className="text-muted-foreground">Manage reseller accounts and quotas</p>
      </div>

      <Card>
        <CardHeader className="pb-4">
          <div className="flex flex-col md:flex-row gap-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Search by name, email, or company..."
                value={search}
                onChange={(e) => {
                  setSearch(e.target.value)
                  setPage(1)
                }}
                className="pl-9"
              />
            </div>

            <div className="flex gap-2">
              <Button
                variant={statusFilter === 'ACTIVE' ? 'default' : 'outline'}
                size="sm"
                onClick={() => {
                  setStatusFilter(statusFilter === 'ACTIVE' ? '' : 'ACTIVE')
                  setPage(1)
                }}
              >
                Active
              </Button>
              <Button
                variant={statusFilter === 'PENDING' ? 'default' : 'outline'}
                size="sm"
                onClick={() => {
                  setStatusFilter(statusFilter === 'PENDING' ? '' : 'PENDING')
                  setPage(1)
                }}
              >
                Pending
              </Button>
              <Button
                variant={statusFilter === 'SUSPENDED' ? 'default' : 'outline'}
                size="sm"
                onClick={() => {
                  setStatusFilter(statusFilter === 'SUSPENDED' ? '' : 'SUSPENDED')
                  setPage(1)
                }}
              >
                Suspended
              </Button>

              {(search || statusFilter) && (
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
            <div className="text-center py-8 text-muted-foreground">Failed to load resellers</div>
          ) : data.resellers.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No resellers found</div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="border-b">
                      <th className="text-left py-3 px-4 font-medium">Company</th>
                      <th className="text-left py-3 px-4 font-medium">Contact</th>
                      <th className="text-left py-3 px-4 font-medium">Quota</th>
                      <th className="text-left py-3 px-4 font-medium">Used (24h)</th>
                      <th className="text-left py-3 px-4 font-medium">Status</th>
                      <th className="text-left py-3 px-4 font-medium">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.resellers.map((reseller) => (
                      <tr key={reseller.id} className="border-b hover:bg-muted/50">
                        <td className="py-3 px-4">
                          <div>
                            <p className="font-medium">{reseller.companyName}</p>
                            <p className="text-sm text-muted-foreground">ID: {reseller.id}</p>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <div>
                            <p className="font-medium">{reseller.name}</p>
                            <p className="text-sm text-muted-foreground">{reseller.email}</p>
                            <p className="text-sm text-muted-foreground">{reseller.phone}</p>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <div className="space-y-1">
                            <div className="flex items-center gap-2">
                              <div className="w-24 h-2 bg-muted rounded-full overflow-hidden">
                                <div
                                  className="h-full bg-primary"
                                  style={{
                                    width: `${(reseller.usedQuota / reseller.monthlyQuota) * 100}%`,
                                  }}
                                />
                              </div>
                              <span className="text-sm">
                                {reseller.usedQuota}/{reseller.monthlyQuota}
                              </span>
                            </div>
                            <p className="text-xs text-muted-foreground">
                              {reseller.remainingQuota} remaining
                            </p>
                          </div>
                        </td>
                        <td className="py-3 px-4">
                          <span
                            className={`font-medium ${
                              reseller.keyRequestCount24h >= 3 ? 'text-destructive' : ''
                            }`}
                          >
                            {reseller.keyRequestCount24h}
                          </span>
                          {reseller.keyRequestCount24h >= 3 && (
                            <Badge variant="destructive" className="ml-2 text-xs">
                              High
                            </Badge>
                          )}
                        </td>
                        <td className="py-3 px-4">
                          <Badge
                            variant={
                              reseller.status === 'ACTIVE' ? 'success' :
                              reseller.status === 'PENDING' ? 'warning' :
                              'destructive'
                            }
                          >
                            {reseller.status}
                          </Badge>
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex gap-2">
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => handleOpenQuotaModal(reseller)}
                            >
                              Set Quota
                            </Button>
                            {reseller.status === 'ACTIVE' ? (
                              <Button
                                size="sm"
                                variant="destructive"
                                onClick={() => suspendMutation.mutate(reseller.id)}
                                disabled={suspendMutation.isPending}
                              >
                                <Ban className="h-4 w-4" />
                              </Button>
                            ) : reseller.status === 'SUSPENDED' ? (
                              <Button
                                size="sm"
                                variant="default"
                                onClick={() => activateMutation.mutate(reseller.id)}
                                disabled={activateMutation.isPending}
                              >
                                <Check className="h-4 w-4" />
                              </Button>
                            ) : null}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              <div className="flex items-center justify-between pt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * pageSize + 1} to {Math.min(page * pageSize, data.total)} of {data.total} resellers
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

      <Dialog open={isQuotaModalOpen} onOpenChange={setIsQuotaModalOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Set Monthly Quota</DialogTitle>
            <DialogDescription>
              Update the monthly key quota for {selectedReseller?.companyName}
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={quotaForm.handleSubmit(handleUpdateQuota)} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="monthlyQuota">Monthly Quota</Label>
              <Input
                id="monthlyQuota"
                type="number"
                min={1}
                {...quotaForm.register('monthlyQuota', { valueAsNumber: true })}
              />
              {quotaForm.formState.errors.monthlyQuota && (
                <p className="text-sm text-destructive">
                  {quotaForm.formState.errors.monthlyQuota.message}
                </p>
              )}
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setIsQuotaModalOpen(false)}
              >
                Cancel
              </Button>
              <Button type="submit">Save Changes</Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}