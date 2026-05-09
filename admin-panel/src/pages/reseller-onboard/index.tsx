import React, { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import { ArrowLeft, ArrowRight, CheckCircle2, Eye, EyeOff, KeyRound, Loader2, ShieldAlert } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import api from '@/api/axios';

function StepDots({ step, total }: { step: number; total: number }) {
  return (
    <div className="flex items-center justify-center gap-2">
      {Array.from({ length: total }).map((_, i) => (
        <div
          key={i}
          className={`h-2 rounded-full transition-all duration-300 ${
            i === step ? 'w-6 bg-emerald-600' : i < step ? 'w-2 bg-emerald-400' : 'w-2 bg-slate-200'
          }`}
        />
      ))}
    </div>
  );
}

const ResellerOnboard: React.FC = () => {
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? '';

  const [step, setStep] = useState(0);
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPw, setShowPw] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [pwError, setPwError] = useState('');

  // Verify token on mount
  const verifyQuery = useQuery({
    queryKey: ['reseller-invite', token],
    queryFn: async () => {
      const { data } = await api.get(`/auth/reseller-invite/verify?token=${token}`);
      return data.data as { name: string; email: string };
    },
    enabled: !!token,
    retry: false,
  });

  const completeMutation = useMutation({
    mutationFn: () =>
      api.post('/auth/reseller-invite/complete', { token, password }),
    onSuccess: () => setStep(2),
  });

  useEffect(() => {
    if (verifyQuery.isSuccess && step === 0) setStep(1);
  }, [verifyQuery.isSuccess]);

  function validatePassword() {
    if (password.length < 8) { setPwError('Password must be at least 8 characters'); return false; }
    if (password !== confirm) { setPwError('Passwords do not match'); return false; }
    setPwError('');
    return true;
  }

  // ── Loading / invalid states ────────────────────────────────────────────

  if (!token) {
    return <ErrorScreen message="No invite token found. Check the link in your email." />;
  }

  if (verifyQuery.isLoading || (verifyQuery.isIdle && step === 0)) {
    return (
      <OnboardShell>
        <div className="flex flex-col items-center gap-4 py-12">
          <Loader2 className="h-8 w-8 animate-spin text-emerald-600" />
          <p className="text-sm text-muted-foreground">Verifying invite link…</p>
        </div>
      </OnboardShell>
    );
  }

  if (verifyQuery.isError) {
    return <ErrorScreen message="This invite link is invalid or has expired. Ask your admin to send a new one." />;
  }

  const invite = verifyQuery.data!;

  // ── Step 1 — Welcome + set password ────────────────────────────────────

  if (step === 1) {
    return (
      <OnboardShell>
        <div className="space-y-2 text-center">
          <p className="text-2xl font-black text-slate-800">Welcome, {invite.name.split(' ')[0]}!</p>
          <p className="text-sm text-muted-foreground">
            Setting up your reseller account for <span className="font-medium text-slate-700">{invite.email}</span>
          </p>
        </div>

        <StepDots step={0} total={2} />

        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="pw">Create password</Label>
            <div className="relative">
              <KeyRound className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                id="pw"
                type={showPw ? 'text' : 'password'}
                className="pl-9 pr-10"
                placeholder="At least 8 characters"
                value={password}
                onChange={e => { setPassword(e.target.value); setPwError(''); }}
                autoFocus
              />
              <button
                type="button"
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground"
                onClick={() => setShowPw(v => !v)}
              >
                {showPw ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="confirm">Confirm password</Label>
            <div className="relative">
              <KeyRound className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                id="confirm"
                type={showConfirm ? 'text' : 'password'}
                className="pl-9 pr-10"
                placeholder="Repeat password"
                value={confirm}
                onChange={e => { setConfirm(e.target.value); setPwError(''); }}
                onKeyDown={e => e.key === 'Enter' && validatePassword() && completeMutation.mutate()}
              />
              <button
                type="button"
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground"
                onClick={() => setShowConfirm(v => !v)}
              >
                {showConfirm ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
            {pwError && <p className="text-xs text-red-500">{pwError}</p>}
          </div>

          {completeMutation.isError && (
            <p className="text-xs text-red-500">
              {(completeMutation.error as any)?.response?.data?.error || 'Something went wrong. Try again.'}
            </p>
          )}

          <Button
            className="w-full bg-emerald-600 hover:bg-emerald-700"
            onClick={() => validatePassword() && completeMutation.mutate()}
            disabled={completeMutation.isPending}
          >
            {completeMutation.isPending
              ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Creating account…</>
              : <>Create account <ArrowRight className="ml-2 h-4 w-4" /></>}
          </Button>
        </div>
      </OnboardShell>
    );
  }

  // ── Step 2 — Success ────────────────────────────────────────────────────

  if (step === 2) {
    return (
      <OnboardShell>
        <StepDots step={1} total={2} />
        <div className="flex flex-col items-center gap-4 py-4 text-center">
          <div className="flex h-20 w-20 items-center justify-center rounded-full bg-emerald-50">
            <CheckCircle2 className="h-10 w-10 text-emerald-600" />
          </div>
          <div>
            <p className="text-2xl font-black text-slate-800">Account ready!</p>
            <p className="mt-2 text-sm text-muted-foreground">
              Your reseller account for <span className="font-medium text-slate-700">{invite.email}</span> is active.
              Your admin will assign your key quota shortly.
            </p>
          </div>
          <div className="w-full rounded-xl border border-slate-200 bg-slate-50 p-4 text-left space-y-2 mt-2">
            <p className="text-sm font-semibold text-slate-700">What's next?</p>
            <ul className="space-y-1 text-sm text-muted-foreground list-disc list-inside">
              <li>Download the EMI Locker dealer app</li>
              <li>Log in with <span className="font-medium text-slate-700">{invite.email}</span></li>
              <li>Wait for your admin to approve your key quota</li>
            </ul>
          </div>
        </div>
      </OnboardShell>
    );
  }

  return null;
};

// ── Shared shell ────────────────────────────────────────────────────────────

function OnboardShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-emerald-50 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="inline-flex h-12 w-12 items-center justify-center rounded-xl bg-emerald-600 text-white text-xl font-black">
            E
          </div>
          <p className="mt-2 text-sm font-medium text-slate-500">EMI Locker</p>
        </div>
        <div className="rounded-2xl border border-slate-200 bg-white p-8 shadow-lg space-y-6">
          {children}
        </div>
      </div>
    </div>
  );
}

function ErrorScreen({ message }: { message: string }) {
  return (
    <OnboardShell>
      <div className="flex flex-col items-center gap-4 py-6 text-center">
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-red-50">
          <ShieldAlert className="h-8 w-8 text-red-500" />
        </div>
        <div>
          <p className="text-lg font-bold text-slate-800">Invalid invite link</p>
          <p className="mt-1 text-sm text-muted-foreground">{message}</p>
        </div>
      </div>
    </OnboardShell>
  );
}

export default ResellerOnboard;
