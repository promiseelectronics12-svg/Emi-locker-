import { useState } from 'react';
import { useResellers, useApproveReseller, useSuspendReseller, useUpdateResellerQuota } from '@/hooks/useApi';
import { useTwoFactorStore } from '@/stores/twoFactorStore';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { formatDate } from '@/lib/utils';
import { Users, AlertTriangle, Check, X, Settings } from 'lucide-react';
import type { ResellerStatus } from '@/types';

type ModalState = 
  | { type: 'none' }
  | { type: 'quota'; resellerId: string; currentQuota: number }
  | { type: 'suspend'; resellerId: string };

const statusColors: Record<ResellerStatus, string> = {
  PENDING: 'warning',
  APPROVED: 'success',
  SUSPENDED: 'destructive',
};

export function ResellersPage() {
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<string>('');
  const [modalState, setModalState] = useState<ModalState>({ type: 'none' });
  const [suspendReason, setSuspendReason] = useState<string>('');

  const limit = 20;
  const { data, isLoading, error } = useResellers({
    page,
    limit,
    status: status || undefined,
  });

  const approveReseller = useApproveReseller();
  const suspendReseller = useSuspendReseller();
  const updateQuota = useUpdateResellerQuota();
  const { open: open2FA } = useTwoFactorStore();

  const handleApprove = (resellerId: string) => {
    open2FA({
      actionDescription: 'Approve this reseller',
      onSuccess: () => {
        approveReseller.mutate(resellerId);
      },
    });
  };

  const handleOpenSuspend = (resellerId: string) => {
    setModalState({ type: 'suspend', resellerId });
  };

  const handleSuspend = () => {
    if (modalState.type !== 'suspend' || !suspendReason) return;
    open2FA({
      actionDescription: 'Suspend this reseller',
      onSuccess: () => {
        suspendReseller.mutate({ resellerId: modalState.resellerId, reason: suspendReason });
        setModalState({ type: 'none' });
        setSuspendReason('');
      },
    });
  };

  const handleOpenQuota = (resellerId: string, currentQuota: number) => {
    setModalState({ type: 'quota', resellerId, currentQuota });
  };

  const handleUpdateQuota = () => {
    if (modalState.type !== 'quota') return;
    open2FA({
      actionDescription: 'Update reseller quota',
      onSuccess: () => {
        updateQuota.mutate({ resellerId: modalState.resellerId, quota: modalState.currentQuota });
        setModalState({ type: 'none' });
      },
    });
  };

  const closeModal = () => {
    setModalState({ type: 'none' });
    setSuspendReason('');
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Resellers</h1>
        <p className="text-muted-foreground">Manage reseller accounts and quotas</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Reseller List</CardTitle>
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
                <SelectItem value="SUSPENDED">Suspended</SelectItem>
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
              <p>Failed to load resellers</p>
            </div>
          ) : data && data.data.length > 0 ? (
            <>
              <div className="rounded-md border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Name</TableHead>
                      <TableHead>Email</TableHead>
                      <TableHead>Phone</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Quota</TableHead>
                      <TableHead>Dealers</TableHead>
                      <TableHead>Created</TableHead>
                      <TableHead></TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.data.map((reseller) => (
                      <TableRow key={reseller.id}>
                        <TableCell className="font-medium">{reseller.name}</TableCell>
                        <TableCell>{reseller.email}</TableCell>
                        <TableCell>{reseller.phone}</TableCell>
                        <TableCell>
                          <Badge variant={statusColors[reseller.status] as any}>
                            {reseller.status}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-2">
                            <span>{reseller.usedQuota} / {reseller.monthlyQuota}</span>
                            <Button 
                              variant="ghost" 
                              size="icon"
                              onClick={() => handleOpenQuota(reseller.id, reseller.monthlyQuota)}
                            >
                              <Settings className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                        <TableCell>{reseller.dealerCount}</TableCell>
                        <TableCell>{formatDate(reseller.createdAt)}</TableCell>
                        <TableCell>
                          <div className="flex gap-2">
                            {reseller.status === 'PENDING' && (
                              <Button 
                                size="sm" 
                                variant="default"
                                onClick={() => handleApprove(reseller.id)}
                                disabled={approveReseller.isPending}
                              >
                                <Check className="h-4 w-4" />
                              </Button>
                            )}
                            {reseller.status !== 'SUSPENDED' && (
                              <Button 
                                size="sm" 
                                variant="destructive"
                                onClick={() => handleOpenSuspend(reseller.id)}
                              >
                                <X className="h-4 w-4" />
                              </Button>
                            )}
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>

              <div className="flex items-center justify-between mt-4">
                <p className="text-sm text-muted-foreground">
                  Showing {(page - 1) * limit + 1} to {Math.min(page * limit, data.total)} of {data.total} resellers
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
              <Users className="h-12 w-12 mb-4" />
              <p>No resellers found</p>
            </div>
          )}
        </CardContent>
      </Card>

      <Dialog open={modalState.type === 'quota'} onOpenChange={closeModal}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Update Reseller Quota</DialogTitle>
            <DialogDescription>Set the monthly key quota for this reseller</DialogDescription>
          </DialogHeader>
          {modalState.type === 'quota' && (
            <div className="space-y-4 py-4">
              <div className="space-y-2">
                <Label htmlFor="quota">Monthly Quota</Label>
                <Input
                  id="quota"
                  type="number"
                  min="0"
                  value={modalState.currentQuota}
                  onChange={(e) => setModalState({ ...modalState, currentQuota: parseInt(e.target.value, 10) || 0 })}
                />
              </div>
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={closeModal}>
              Cancel
            </Button>
            <Button onClick={handleUpdateQuota} disabled={updateQuota.isPending}>
              Update Quota
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={modalState.type === 'suspend'} onOpenChange={closeModal}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Suspend Reseller</DialogTitle>
            <DialogDescription>Provide a reason for suspending this reseller</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="reason">Reason</Label>
              <Input
                id="reason"
                value={suspendReason}
                onChange={(e) => setSuspendReason(e.target.value)}
                placeholder="Enter suspension reason"
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={closeModal}>
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleSuspend} disabled={!suspendReason || suspendReseller.isPending}>
              Suspend Reseller
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}