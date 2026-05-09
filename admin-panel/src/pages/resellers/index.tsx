import React, { useState } from 'react';
import { useMutation, useQuery } from '@tanstack/react-query';
import { AlertTriangle, ArrowLeft, ArrowRight, CheckCircle2, Mail, MoreVertical, Search, ShieldCheck, User, UserPlus, Users } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader, normalizeList } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import api from '@/api/axios';
import { Reseller } from '@/types';
import { useToast } from '@/hooks/use-toast';

// ── Step indicator ──────────────────────────────────────────────────────────

function StepDots({ step, total }: { step: number; total: number }) {
  return (
    <div className="flex items-center justify-center gap-2 py-1">
      {Array.from({ length: total }).map((_, i) => (
        <div
          key={i}
          className={`h-2 rounded-full transition-all duration-300 ${
            i === step ? 'w-6 bg-emerald-600' : i < step ? 'w-2 bg-emerald-300' : 'w-2 bg-slate-200'
          }`}
        />
      ))}
    </div>
  );
}

// ── Invite wizard ───────────────────────────────────────────────────────────

interface InviteWizardProps {
  open: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

function InviteWizard({ open, onClose, onSuccess }: InviteWizardProps) {
  const { toast } = useToast();
  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [nameError, setNameError] = useState('');
  const [emailError, setEmailError] = useState('');

  const inviteMutation = useMutation({
    mutationFn: () => api.post('/admin/resellers/invite', { name: name.trim(), email: email.trim().toLowerCase() }),
    onSuccess: () => setStep(2),
    onError: (err: any) => {
      toast({
        title: 'Invite failed',
        description: err.response?.data?.error || 'Could not send invite',
        variant: 'destructive',
      });
    },
  });

  function reset() {
    setStep(0);
    setName('');
    setEmail('');
    setNameError('');
    setEmailError('');
  }

  function handleClose() {
    reset();
    onClose();
  }

  function validateStep0() {
    let ok = true;
    if (!name.trim()) { setNameError('Name is required'); ok = false; } else setNameError('');
    const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!email.trim()) { setEmailError('Email is required'); ok = false; }
    else if (!emailRe.test(email.trim())) { setEmailError('Enter a valid email'); ok = false; }
    else setEmailError('');
    return ok;
  }

  function handleFinish() {
    reset();
    onSuccess();
    onClose();
  }

  return (
    <Dialog open={open} onOpenChange={open => { if (!open) handleClose(); }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <UserPlus className="h-5 w-5 text-emerald-600" />
            Invite Reseller
          </DialogTitle>
        </DialogHeader>

        <StepDots step={step} total={3} />

        {/* Step 0 — Name & Email */}
        {step === 0 && (
          <div className="space-y-4 py-2">
            <p className="text-sm text-muted-foreground">
              Enter the reseller's name and email. They'll receive an invite link to set up their account.
            </p>
            <div className="space-y-2">
              <Label htmlFor="r-name">Full name</Label>
              <div className="relative">
                <User className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  id="r-name"
                  className="pl-9"
                  placeholder="e.g. Rahman Traders"
                  value={name}
                  onChange={e => { setName(e.target.value); setNameError(''); }}
                  onKeyDown={e => e.key === 'Enter' && validateStep0() && setStep(1)}
                  autoFocus
                />
              </div>
              {nameError && <p className="text-xs text-red-500">{nameError}</p>}
            </div>
            <div className="space-y-2">
              <Label htmlFor="r-email">Email address</Label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  id="r-email"
                  type="email"
                  className="pl-9"
                  placeholder="reseller@example.com"
                  value={email}
                  onChange={e => { setEmail(e.target.value); setEmailError(''); }}
                  onKeyDown={e => e.key === 'Enter' && validateStep0() && setStep(1)}
                />
              </div>
              {emailError && <p className="text-xs text-red-500">{emailError}</p>}
            </div>
            <div className="flex justify-end pt-2">
              <Button
                className="bg-emerald-600 hover:bg-emerald-700"
                onClick={() => validateStep0() && setStep(1)}
              >
                Next <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            </div>
          </div>
        )}

        {/* Step 1 — Review */}
        {step === 1 && (
          <div className="space-y-4 py-2">
            <p className="text-sm text-muted-foreground">
              Review the details before sending. The invite link expires in 48 hours.
            </p>
            <div className="rounded-xl border border-slate-200 bg-slate-50 p-4 space-y-3">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-white font-bold text-sm">
                  {name.trim().charAt(0).toUpperCase()}
                </div>
                <div>
                  <p className="font-semibold text-slate-800">{name.trim()}</p>
                  <p className="text-sm text-muted-foreground">{email.trim().toLowerCase()}</p>
                </div>
              </div>
              <div className="rounded-lg bg-amber-50 border border-amber-200 px-3 py-2 text-xs text-amber-700">
                An email will be sent with a secure setup link. The reseller will create their password and activate their account.
              </div>
            </div>
            <div className="flex justify-between pt-2">
              <Button variant="ghost" onClick={() => setStep(0)}>
                <ArrowLeft className="mr-2 h-4 w-4" /> Back
              </Button>
              <Button
                className="bg-emerald-600 hover:bg-emerald-700"
                onClick={() => inviteMutation.mutate()}
                disabled={inviteMutation.isPending}
              >
                {inviteMutation.isPending ? 'Sending…' : 'Send invite'}
                {!inviteMutation.isPending && <ArrowRight className="ml-2 h-4 w-4" />}
              </Button>
            </div>
          </div>
        )}

        {/* Step 2 — Success */}
        {step === 2 && (
          <div className="flex flex-col items-center gap-4 py-6 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-emerald-50">
              <CheckCircle2 className="h-8 w-8 text-emerald-600" />
            </div>
            <div>
              <p className="text-lg font-bold text-slate-800">Invite sent!</p>
              <p className="mt-1 text-sm text-muted-foreground">
                <span className="font-medium text-slate-700">{name.trim()}</span> will receive an email at{' '}
                <span className="font-medium text-slate-700">{email.trim().toLowerCase()}</span> with a setup link valid for 48 hours.
              </p>
            </div>
            <Button className="mt-2 bg-emerald-600 hover:bg-emerald-700 w-full" onClick={handleFinish}>
              Done
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

// ── Resellers page ──────────────────────────────────────────────────────────

interface SuspendTarget { id: string; name: string }

function SuspendConfirmDialog({ target, onConfirm, onClose, loading }: {
  target: SuspendTarget | null; onConfirm: () => void; onClose: () => void; loading: boolean;
}) {
  const [typed, setTyped] = useState('');
  const correct = typed.trim().toUpperCase() === 'SUSPEND';
  return (
    <Dialog open={!!target} onOpenChange={open => { if (!open) { setTyped(''); onClose(); } }}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-red-600">
            <AlertTriangle className="h-5 w-5" /> Suspend reseller
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
            You are about to suspend <span className="font-bold">{target?.name}</span>. Their dealers will lose access to key quota. This can be reversed.
          </div>
          <div className="space-y-2">
            <p className="text-sm text-slate-600">Type <span className="font-mono font-bold text-slate-800">SUSPEND</span> to confirm:</p>
            <Input value={typed} onChange={e => setTyped(e.target.value)} placeholder="SUSPEND"
              className="font-mono uppercase" autoFocus onKeyDown={e => e.key === 'Enter' && correct && onConfirm()} />
          </div>
        </div>
        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={() => { setTyped(''); onClose(); }} disabled={loading}>Cancel</Button>
          <Button variant="destructive" onClick={() => { onConfirm(); setTyped(''); }} disabled={!correct || loading}>
            {loading ? 'Suspending…' : 'Confirm suspend'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

const Resellers: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [inviteOpen, setInviteOpen] = useState(false);
  const [suspendTarget, setSuspendTarget] = useState<SuspendTarget | null>(null);
  const { toast } = useToast();

  const query = useQuery({
    queryKey: ['resellers', searchTerm],
    queryFn: async () => {
      const { data } = await api.get('/admin/resellers', { params: { search: searchTerm || undefined } });
      return normalizeList<Reseller>(data.data ?? data);
    },
  });

  const statusMutation = useMutation({
    mutationFn: async ({ id, status }: { id: string; status: 'APPROVED' | 'SUSPENDED' }) => {
      if (status === 'APPROVED') return api.post(`/admin/resellers/${id}/approve`);
      return api.post(`/admin/resellers/${id}/suspend`, { reason: 'Suspended from admin panel' });
    },
    onSuccess: () => {
      toast({ title: 'Reseller updated', description: 'Status changed successfully' });
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Update failed', description: err.response?.data?.error || 'Could not update reseller', variant: 'destructive' });
    },
  });

  if (query.isLoading) return <LoadingState title="Loading reseller network" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Resellers could not be loaded" />;

  const resellers = Array.isArray(query.data) ? query.data : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reseller Management"
        description="Approve, suspend, and inspect reseller key quotas across the dealer network."
        action={
          <Button className="bg-emerald-600 hover:bg-emerald-700" onClick={() => setInviteOpen(true)}>
            <UserPlus className="mr-2 h-4 w-4" /> Invite Reseller
          </Button>
        }
      />

      <BentoPanel>
        <div className="relative max-w-xl">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search resellers by name or email..."
            className="bg-white/70 pl-10"
            value={searchTerm}
            onChange={event => setSearchTerm(event.target.value)}
          />
        </div>
      </BentoPanel>

      {resellers.length === 0 ? (
        <EmptyState title="No resellers in the network yet" description="Invite your first reseller using the button above." icon={Users} />
      ) : (
        <>
          <BentoPanel className="hidden p-0 md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Email</TableHead>
                  <TableHead>Quota</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {resellers.map(reseller => (
                  <TableRow key={reseller.id}>
                    <TableCell className="font-medium">{reseller.name || 'Unnamed reseller'}</TableCell>
                    <TableCell>{reseller.email}</TableCell>
                    <TableCell>
                      <div className="font-medium">{reseller.usedQuota ?? 0} / {reseller.monthlyQuota ?? 0}</div>
                      <div className="text-xs text-muted-foreground">Activated: {(reseller as any).activatedKeys ?? 0}</div>
                    </TableCell>
                    <TableCell>
                      <Badge variant={reseller.status === 'APPROVED' || (reseller as any).status === 'active' ? 'success' : 'outline'}>
                        {reseller.status || (reseller as any).status}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        <Button variant="outline" size="sm" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'APPROVED' })}>
                          <ShieldCheck className="mr-1 h-4 w-4" /> Approve
                        </Button>
                        <DropdownMenu>
                          <DropdownMenuTrigger asChild>
                            <Button variant="ghost" size="icon" className="h-8 w-8">
                              <MoreVertical className="h-4 w-4" />
                            </Button>
                          </DropdownMenuTrigger>
                          <DropdownMenuContent align="end">
                            <DropdownMenuItem
                              className="text-red-600 focus:text-red-600"
                              onClick={() => setSuspendTarget({ id: reseller.id, name: reseller.name || 'Reseller' })}
                            >
                              Suspend…
                            </DropdownMenuItem>
                          </DropdownMenuContent>
                        </DropdownMenu>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </BentoPanel>

          <div className="grid gap-3 md:hidden">
            {resellers.map(reseller => (
              <BentoPanel key={reseller.id}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-medium text-emerald-950">{reseller.name || 'Unnamed reseller'}</p>
                    <p className="truncate text-sm text-muted-foreground">{reseller.email}</p>
                  </div>
                  <Badge variant="outline">{reseller.status || (reseller as any).status}</Badge>
                </div>
                <p className="mt-4 text-sm text-muted-foreground">Quota: {reseller.usedQuota ?? 0} / {reseller.monthlyQuota ?? 0}</p>
                <div className="mt-4 flex gap-2">
                  <Button className="flex-1" variant="outline" onClick={() => statusMutation.mutate({ id: reseller.id, status: 'APPROVED' })}>
                    <ShieldCheck className="mr-1 h-4 w-4" /> Approve
                  </Button>
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="outline" size="icon"><MoreVertical className="h-4 w-4" /></Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem className="text-red-600 focus:text-red-600"
                        onClick={() => setSuspendTarget({ id: reseller.id, name: reseller.name || 'Reseller' })}>
                        Suspend…
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </div>
              </BentoPanel>
            ))}
          </div>
        </>
      )}

      <InviteWizard
        open={inviteOpen}
        onClose={() => setInviteOpen(false)}
        onSuccess={() => query.refetch()}
      />

      <SuspendConfirmDialog
        target={suspendTarget}
        onConfirm={() => suspendTarget && statusMutation.mutate({ id: suspendTarget.id, status: 'SUSPENDED' })}
        onClose={() => setSuspendTarget(null)}
        loading={statusMutation.isPending}
      />
    </div>
  );
};

export default Resellers;
