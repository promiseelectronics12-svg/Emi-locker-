import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import api from '@/lib/api';

const loginSchema = z.object({
  email: z.string().email('Invalid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

const mfaSchema = z.object({
  code: z.string().length(6, 'Code must be 6 digits'),
});

type LoginFormData = z.infer<typeof loginSchema>;
type MfaFormData = z.infer<typeof mfaSchema>;

export function LoginPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<'login' | 'mfa'>('login');
  const [tempToken, setTempToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loginForm = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
  });

  const mfaForm = useForm<MfaFormData>({
    resolver: zodResolver(mfaSchema),
  });

  const onLoginSubmit = async (data: LoginFormData) => {
    try {
      setError(null);
      const response = await api.post<{ tempToken: string; requiresMfa: boolean }>(
        '/api/admin/auth/login',
        data
      );

      if (response.requiresMfa) {
        setTempToken(response.tempToken);
        setStep('mfa');
      } else {
        navigate('/dashboard');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    }
  };

  const onMfaSubmit = async (data: MfaFormData) => {
    try {
      setError(null);
      await api.post('/api/admin/auth/verify-mfa', {
        tempToken,
        code: data.code,
      });
      navigate('/dashboard');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Verification failed');
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-900 to-slate-800 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl text-center">EMI Admin Panel</CardTitle>
          <CardDescription className="text-center">
            Enter your credentials to access the admin dashboard
          </CardDescription>
        </CardHeader>
        <CardContent>
          {step === 'login' ? (
            <form onSubmit={loginForm.handleSubmit(onLoginSubmit)} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="admin@emilocker.com"
                  {...loginForm.register('email')}
                />
                {loginForm.formState.errors.email && (
                  <p className="text-sm text-destructive">{loginForm.formState.errors.email.message}</p>
                )}
              </div>
              <div className="space-y-2">
                <Label htmlFor="password">Password</Label>
                <Input
                  id="password"
                  type="password"
                  placeholder="••••••••"
                  {...loginForm.register('password')}
                />
                {loginForm.formState.errors.password && (
                  <p className="text-sm text-destructive">{loginForm.formState.errors.password.message}</p>
                )}
              </div>
              {error && <p className="text-sm text-destructive text-center">{error}</p>}
              <Button type="submit" className="w-full" disabled={loginForm.formState.isSubmitting}>
                {loginForm.formState.isSubmitting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                Sign In
              </Button>
            </form>
          ) : (
            <form onSubmit={mfaForm.handleSubmit(onMfaSubmit)} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="code">Enter 6-digit code from your authenticator</Label>
                <Input
                  id="code"
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]{6}"
                  maxLength={6}
                  placeholder="000000"
                  {...mfaForm.register('code')}
                  className="text-center text-2xl tracking-widest font-mono"
                />
                {mfaForm.formState.errors.code && (
                  <p className="text-sm text-destructive">{mfaForm.formState.errors.code.message}</p>
                )}
              </div>
              {error && <p className="text-sm text-destructive text-center">{error}</p>}
              <div className="flex gap-2">
                <Button type="button" variant="outline" className="flex-1" onClick={() => setStep('login')}>
                  Back
                </Button>
                <Button type="submit" className="flex-1" disabled={mfaForm.formState.isSubmitting}>
                  {mfaForm.formState.isSubmitting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                  Verify
                </Button>
              </div>
            </form>
          )}
        </CardContent>
      </Card>
    </div>
  );
}