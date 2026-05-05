import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Eye, EyeOff, Lock, Server, Shield, Smartphone, Wifi } from 'lucide-react';
import { Navigate, useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import api from '@/api/axios';
import { useAuthStore } from '@/store/authStore';

const loginSchema = z.object({
  email: z.string().email('Enter a valid admin email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

const twoFactorSchema = z.object({
  code: z.string().length(6, 'Code must be 6 digits'),
});

type LoginFormData = z.infer<typeof loginSchema>;
type TwoFactorFormData = z.infer<typeof twoFactorSchema>;

const statusCards = [
  { label: 'API gateway', value: 'Online', icon: Server },
  { label: 'Device channel', value: 'Ready', icon: Smartphone },
  { label: 'Admin session', value: 'Protected', icon: Shield },
];

export function LoginPage() {
  const [step, setStep] = useState<'credentials' | '2fa'>('credentials');
  const [tempToken, setTempToken] = useState<string | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { setAuth, isAuthenticated } = useAuthStore();
  const navigate = useNavigate();

  const loginForm = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  });

  const twoFactorForm = useForm<TwoFactorFormData>({
    resolver: zodResolver(twoFactorSchema),
    defaultValues: { code: '' },
  });

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  const onLoginSubmit = async (data: LoginFormData) => {
    setError(null);
    try {
      const response = await api.post<{
        tempToken: string;
        requires2FA: boolean;
        user: unknown;
      }>('/auth/login', data);

      const { tempToken: token, requires2FA } = response.data;
      setTempToken(token);

      if (requires2FA) {
        setStep('2fa');
        return;
      }

      const verifyResponse = await api.post<{
        accessToken: string;
        user: unknown;
      }>('/auth/2fa/verify', { tempToken: token });

      setAuth(verifyResponse.data.user, verifyResponse.data.accessToken);
      navigate('/dashboard', { replace: true });
    } catch (err: any) {
      setError(err.response?.data?.message || err.message || 'Login failed. Check the admin API and try again.');
    }
  };

  const onTwoFactorSubmit = async (data: TwoFactorFormData) => {
    setError(null);
    try {
      const response = await api.post<{
        accessToken: string;
        user: unknown;
      }>('/auth/2fa/verify', {
        tempToken,
        code: data.code,
      });

      setAuth(response.data.user, response.data.accessToken);
      navigate('/dashboard', { replace: true });
    } catch (err: any) {
      setError(err.response?.data?.message || err.message || '2FA verification failed. Try a fresh code.');
    }
  };

  return (
    <main className="bento-grid-bg flex min-h-screen items-center justify-center p-4 sm:p-6 lg:p-8">
      {/* Unified Split-Screen Bento Card */}
      <div className="bento-card flex w-full max-w-[1100px] flex-col overflow-hidden bg-white/80 shadow-[0_40px_80px_rgba(0,0,0,0.12)] backdrop-blur-2xl lg:flex-row lg:items-stretch lg:p-0 animate-in fade-in zoom-in-95 duration-700 border-white/40">
        
        {/* Left Side: Branding & Status */}
        <section className="relative flex flex-col justify-between bg-emerald-950 p-8 text-white lg:w-[55%] lg:p-14 overflow-hidden">
          {/* Background decorative blob */}
          <div className="absolute -left-20 -top-20 h-64 w-64 rounded-full bg-emerald-500/20 blur-[80px]"></div>
          <div className="absolute -right-20 -bottom-20 h-64 w-64 rounded-full bg-emerald-700/30 blur-[80px]"></div>

          <div className="relative z-10">
            <div className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-2 text-sm font-medium text-emerald-50 shadow-inner backdrop-blur-md">
              <Shield className="h-4 w-4 text-emerald-400" />
              EMI Locker Command Center
            </div>
            <div className="mt-10 lg:mt-16 max-w-xl">
              <h1 className="text-3xl font-bold tracking-tight sm:text-4xl lg:text-5xl bg-gradient-to-br from-white to-emerald-200 bg-clip-text text-transparent pb-2">
                Secure device operations.
              </h1>
              <p className="mt-5 text-base sm:text-lg leading-relaxed text-emerald-100/80">
                Monitor bound devices, reseller key velocity, lock states, decoupling windows,
                and security events from one operational panel.
              </p>
            </div>
          </div>

          <div className="relative z-10 mt-10 grid gap-3 sm:grid-cols-3 lg:mt-16">
            {statusCards.map(({ label, value, icon: Icon }, i) => (
              <div key={label} className="rounded-2xl border border-white/10 bg-white/5 p-4 backdrop-blur-md transition-all hover:bg-white/10 hover:-translate-y-1" style={{ animationDelay: `${i * 150}ms` }}>
                <Icon className="h-5 w-5 text-emerald-400 mb-3" />
                <p className="text-xs font-semibold uppercase tracking-wider text-emerald-200/60">{label}</p>
                <p className="mt-1 text-lg font-bold text-white">{value}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Right Side: Login Form */}
        <section className="flex flex-1 flex-col items-center justify-center p-8 lg:p-14 relative z-10">
          <div className="w-full max-w-sm">
            <div className="mb-10 text-center lg:text-left">
              <div className="mx-auto lg:mx-0 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-emerald-500 to-emerald-700 text-white shadow-xl shadow-emerald-500/20 mb-6">
                {step === 'credentials' ? <Lock className="h-6 w-6" /> : <Wifi className="h-6 w-6" />}
              </div>
              <h2 className="text-2xl sm:text-3xl font-bold text-emerald-950">
                {step === 'credentials' ? 'Admin sign in' : 'Verify identity'}
              </h2>
              <p className="mt-3 text-base text-muted-foreground">
                {step === 'credentials'
                  ? 'Use your admin credentials to enter the control room.'
                  : 'Enter the 6-digit authenticator code for this session.'}
              </p>
            </div>

            {error ? (
              <div className="mb-6 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 font-medium animate-in slide-in-from-top-2">
                {error}
              </div>
            ) : null}

            {step === 'credentials' ? (
              <form onSubmit={loginForm.handleSubmit(onLoginSubmit)} className="space-y-5">
                <div className="space-y-2.5">
                  <Label htmlFor="email" className="text-sm font-semibold text-emerald-900">Email</Label>
                  <Input 
                    id="email" 
                    type="email" 
                    placeholder="admin@emilocker.local" 
                    className="h-12 text-base px-4 rounded-xl border-emerald-900/10 focus-visible:ring-emerald-500 bg-emerald-50/30"
                    {...loginForm.register('email')} 
                  />
                  {loginForm.formState.errors.email ? (
                    <p className="text-sm text-destructive font-medium">{loginForm.formState.errors.email.message}</p>
                  ) : null}
                </div>

                <div className="space-y-2.5">
                  <Label htmlFor="password" className="text-sm font-semibold text-emerald-900">Password</Label>
                  <div className="relative">
                    <Input
                      id="password"
                      type={showPassword ? 'text' : 'password'}
                      placeholder="Enter password"
                      className="h-12 text-base px-4 pr-12 rounded-xl border-emerald-900/10 focus-visible:ring-emerald-500 bg-emerald-50/30"
                      {...loginForm.register('password')}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword(value => !value)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 rounded-md p-2 text-emerald-900/40 hover:text-emerald-700 hover:bg-emerald-100/50 transition-colors"
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                    >
                      {showPassword ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
                    </button>
                  </div>
                  {loginForm.formState.errors.password ? (
                    <p className="text-sm text-destructive font-medium">{loginForm.formState.errors.password.message}</p>
                  ) : null}
                </div>

                <Button type="submit" className="w-full h-12 mt-4 rounded-xl text-base font-semibold shadow-xl shadow-emerald-600/20 transition-all hover:-translate-y-0.5 hover:shadow-emerald-600/30 active:translate-y-0" disabled={loginForm.formState.isSubmitting}>
                  {loginForm.formState.isSubmitting ? 'Authenticating...' : 'Enter System'}
                </Button>
              </form>
            ) : (
              <form onSubmit={twoFactorForm.handleSubmit(onTwoFactorSubmit)} className="space-y-6">
                <div className="space-y-3">
                  <Label htmlFor="code" className="text-sm font-semibold text-emerald-900">Verification code</Label>
                  <Input
                    id="code"
                    type="text"
                    inputMode="numeric"
                    placeholder="000000"
                    maxLength={6}
                    className="h-14 text-center text-2xl tracking-[0.4em] font-mono rounded-xl border-emerald-900/10 focus-visible:ring-emerald-500 bg-emerald-50/30"
                    {...twoFactorForm.register('code')}
                  />
                  {twoFactorForm.formState.errors.code ? (
                    <p className="text-sm text-destructive font-medium text-center">{twoFactorForm.formState.errors.code.message}</p>
                  ) : null}
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <Button
                    type="button"
                    variant="outline"
                    className="h-12 rounded-xl text-base font-semibold hover:bg-emerald-50"
                    onClick={() => {
                      setStep('credentials');
                      setTempToken(null);
                      setError(null);
                    }}
                  >
                    Back
                  </Button>
                  <Button type="submit" className="h-12 rounded-xl text-base font-semibold shadow-lg shadow-emerald-600/20" disabled={twoFactorForm.formState.isSubmitting}>
                    {twoFactorForm.formState.isSubmitting ? 'Verifying...' : 'Verify'}
                  </Button>
                </div>
              </form>
            )}
          </div>
        </section>
      </div>
    </main>
  );
}
