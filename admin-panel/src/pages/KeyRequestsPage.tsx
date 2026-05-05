import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Loader2, Check, X, AlertTriangle, Key } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
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
import { api } from '@/lib/api'
import { formatDate } from '@/lib/utils'
import { useTwoFactorStore } from '@/store/twoFactorStore'
import type { KeyRequest, KeyRequestListResponse } from '@/types'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const rejectSchema = z.object({
  adminNotes: z.string().min(10, 'Rejection reason must be at least 10 characters'),
})

type RejectFormData = z.infer<typeof rejectSchema>

export function KeyRequestsPage() {
  const [page, setPage] = useState(1)
  const [pageSize] = useState(20)
  const [selectedRequest, setSelectedRequest] = useState<KeyRequest | null>(null)
  const [isRejectModalOpen, setIsRejectModalOpen] = useState(false)

  const queryClient = useQueryClient()
  const openTwoFactorModal = useTwoFactorStore((state) => state.openModal)

  const { data, isLoading } = useQuery<KeyRequestListResponse>({
    queryKey: ['key-requests', page, pageSize],
    queryFn: () => api.get('/api/admin/key-requests', { page, pageSize }),
  })

  const rejectForm = useForm<RejectFormData>({
    resolver: zodResolver(rejectSchema),
  })

  const approveMutation = useMutation({
    mutationFn: (requestId: string) =>
      api.post(`/api/admin/key-requests/${requestId}/approve`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['key-requests'] })
    },
  })

  const rejectMutation = useMutation({
    mutationFn: ({ requestId, notes }: { requestId: string; notes: string }) =>
      api.post(`/api/admin/key-requests/${requestId}/reject`, { adminNotes: notes }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['key-requests'] })
    },
  })

  const handleApprove = (request: KeyRequest) => {
    openTwoFactorModal({
      action: `Approve key request for ${request.resellerName}`,
      resourceId: request.id,
      onSuccess: () => {
        approveMutation.mutate(request.id)
      },
    })
  }

  const handleReject = (request: KeyRequest) => {
    setSelectedRequest(request)
    setIsRejectModalOpen(true)
  }

  const handleConfirmReject = (data: RejectFormData) => {
    if (!selectedRequest) return

    openTwoFactorModal({
      action: `Reject key request for ${selectedRequest.resellerName}`,
      resourceId: selectedRequest.id,
      onSuccess: () => {
        rejectMutation.mutate({ requestId: selectedRequest.id, notes: data.adminNotes })
        setIsRejectModalOpen(false)
        setSelectedRequest(null)
        rejectForm.reset()
      },
    })
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Key Requests</h1>
        <p className="text-muted-foreground">Review and approve reseller key requests</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Key className="h-5 w-5" />
            Pending Requests
            {data?.total ? (
              <Badge variant="destructive" className="ml-2">
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
          ) : !data || data.requests.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">No pending requests</div>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Reseller</TableHead>
                    <TableHead>Quantity</TableHead>
                    <TableHead>Justification</TableHead>
                    <TableHead>Submitted</TableHead>
                    <TableHead>Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.requests.map((request) => (
                    <TableRow key={request.id}>
                      <TableCell>
                        <div>
                          <p className="font-medium">{request.resellerName}</p>
                          <p className="text-sm text-muted-foreground">ID: {request.resellerId}</p>
                        </div>
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline">{request.quantity} keys</Badge>
                      </TableCell>
                      <TableCell>
                        <p className="text-sm max-w-xs truncate">{request.justification}</p>
                      </TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {formatDate(request.createdAt)}
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-2">
                          <Button
                            size="sm"
                            onClick={() => handleApprove(request)}
                            disabled={approveMutation.isPending}
                          >
                            <Check className="h-4 w-4 mr-1" />
                            Approve
                          </Button>
                          <Button
                            size="sm"
                            variant="destructive"
                            onClick={() => handleReject(request)}
                            disabled={rejectMutation.isPending}
                          >
                            <X className="h-4 w-4" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              <div className="flex items-center justify-between pt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * pageSize + 1} to {Math.min(page * pageSize, data.total)} of {data.total} requests
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

      <Dialog open={isRejectModalOpen} onOpenChange={setIsRejectModalOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reject Key Request</DialogTitle>
            <DialogDescription>
              Provide a reason for rejecting this key request from {selectedRequest?.resellerName}
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={rejectForm.handleSubmit(handleConfirmReject)} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="adminNotes">Rejection Reason</Label>
              <Textarea
                id="adminNotes"
                placeholder="Explain why this request is being rejected..."
                {...rejectForm.register('adminNotes')}
              />
              {rejectForm.formState.errors.adminNotes && (
                <p className="text-sm text-destructive">
                  {rejectForm.formState.errors.adminNotes.message}
                </p>
              )}
            </div>

            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  setIsRejectModalOpen(false)
                  setSelectedRequest(null)
                  rejectForm.reset()
                }}
              >
                Cancel
              </Button>
              <Button type="submit" variant="destructive">
                Reject Request
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}