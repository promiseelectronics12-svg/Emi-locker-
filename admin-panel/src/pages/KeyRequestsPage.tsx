import { useState } from 'react';
import { useKeyRequests, useApproveKeyRequest, useRejectKeyRequest } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { formatDate, formatDateTime } from '@/lib/utils';
import { Key, AlertTriangle, Check, X, Clock } from 'lucide-react';
import type { KeyRequestStatus } from '@/types';

const statusColors: Record<KeyRequestStatus, string> = {
  PENDING: 'warning',
  APPROVED: 'success',
  REJECTED: 'destructive',
};

export function KeyRequestsPage() {
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<string>('');
  const [selectedRequest, setSelectedRequest] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState<string>('');

  const limit = 20;
  const { data, isLoading, error } = useKeyRequests({
    page,
    limit,
    status: status || undefined,
  });

  const approveRequest = useApproveKeyRequest();
  const rejectRequest = useRejectKeyRequest();
  const { open: open2FA } = useTwoFactorStore();

  const handleApprove = (requestId: string) => {
    open2FA({
      actionDescription: 'Approve this key request',
      onSuccess: () => {
        approveRequest.mutate(requestId);
      },
    });
  };

  const handleOpenReject = (requestId: string) => {
    setSelectedRequest(requestId);
  };

  const handleReject = () => {
    if (!selectedRequest || !rejectReason) return;
    open2FA({
      actionDescription: 'Reject this key request',
      onSuccess: () => {
        rejectRequest.mutate({ requestId: selectedRequest, reason: rejectReason });
        setSelectedRequest(null);
        setRejectReason('');
      },
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Key Requests</h1>
        <p className="text-muted-foreground">Review and manage activation key requests from resellers</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Request Queue</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex gap-2 mb-6">
            <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1); }}>
              <SelectTrigger className="w-[180px]">
                <SelectValue placeholder="Filter by status" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="">All Status</SelectItem>
                <SelectItem value="PENDING">Pending</SelectItem>
                <SelectItem value="APPROVED">Approved</SelectItem>
                <SelectItem value="REJECTED">Rejected</SelectItem>
              </SelectContent>
            </Select>
          </div>

          {isLoading ? (
            <div className="flex items-center justify-center h-64">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <AlertTriangle className="h-12 w-12 mb-4" />
              <p>Failed to load key requests</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Reseller</TableHead>
                      <TableHead>Quantity</TableHead>
                      <TableHead>Justification</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Requested</TableHead>
                      <TableHead>Reviewed</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((request) => (
                      <TableRow key={request.id}>
                        <TableCell className="font-medium">{request.resellerName}</TableCell>
                        <TableCell>
                          <div className="flex items-center gap-2">
                            <Key className="h-4 w-4 text-muted-foreground" />
                            <span className="font-mono">{request.quantity}</span>
                          </div>
                        </TableCell>
                        <TableCell className="max-w-xs truncate">{request.justification}</TableCell>
                        <TableCell>
                          <Badge variant={statusColors[request.status] as any}>
                            {request.status}
                          </Badge>
                        </TableCell>
                        <TableCell>{formatDateTime(request.createdAt)}</TableCell>
                        <TableCell>
                          {request.reviewedAt ? (
                            formatDateTime(request.reviewedAt)
                          ) : (
                            <span className="flex items-center gap-1 text-muted-foreground">
                              <Clock className="h-4 w-4" />
                              Pending
                            </span>
                          )}
                        </TableCell>
                        <TableCell>
                          {request.status === 'PENDING' && (
                            <div className="flex gap-2">
                              <Button 
                                size="sm" 
                                variant="default"
                                onClick={() => handleApprove(request.id)}
                                disabled={approveRequest.isPending}
                              >
                                <Check className="h-4 w-4" />
                              </Button>
                              <Button 
                                size="sm" 
                                variant="destructive"
                                onClick={() => handleOpenReject(request.id)}
                              >
                                <X className="h-4 w-4" />
                              </Button>
                            </div>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} requests
                </p>
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>
                    Previous
                  </Button>
                  <span className="flex items-center px-3 text-sm">Page {page} of {data.totalPages}</span>
                  <Button variant="outline" size="sm" onClick={() => setPage((p) => Math.min(data.totalPages, p + 1))} disabled={page === data.totalPages}>
                    Next
                  </Button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col items-center justify-center h-64 text-muted-foreground">
              <Key className="h-12 w-12 mb-4" />
              <p>No key requests found</p>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={!!selectedRequest} onOpenChange={() => { setSelectedRequest(null); setRejectReason(''); }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reject Key Request</DialogTitle>
            <DialogDescription>Provide a reason for rejecting this key request</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="reason">Reason</Label>
              <Input
                id="reason"
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                placeholder="Enter rejection reason"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => { setSelectedRequest(null); setRejectReason(''); }}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleReject} disabled={!rejectReason || rejectRequest.isPending}>
              Reject Request
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}