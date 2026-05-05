import React, { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import { ArrowLeft, FileText, History, Lock, MapPin, ShieldAlert, Smartphone, Unlock } from 'lucide-react';
import { BentoPanel, EmptyState, ErrorState, LoadingState, PageHeader } from '@/components/admin/Bento';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import api from '@/api/axios';
import { Device } from '@/types';
import { TwoFactorModal } from '@/components/TwoFactorModal';
import { useToast } from '@/hooks/use-toast';

const DeviceDetail: React.FC = () => {
  const { id } = useParams();
  const { toast } = useToast();
  const [isTwoFactorOpen, setIsTwoFactorOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<{ type: 'LOCK' | 'UNLOCK'; deviceId: string } | null>(null);

  const query = useQuery({
    queryKey: ['device-detail', id],
    enabled: Boolean(id),
    queryFn: async () => {
      const { data } = await api.get(`/admin/devices/${id}`);
      return (data.data ?? data) as Device & Record<string, any>;
    },
  });

  const actionMutation = useMutation({
    mutationFn: async ({ type, deviceId, code }: { type: 'LOCK' | 'UNLOCK'; deviceId: string; code: string }) =>
      api.post(`/admin/devices/${deviceId}/action`, { type, twoFactorCode: code }),
    onSuccess: () => {
      toast({ title: 'Action executed', description: 'Device state updated successfully' });
      setIsTwoFactorOpen(false);
      query.refetch();
    },
    onError: (err: any) => {
      toast({ title: 'Action failed', description: err.response?.data?.message || 'An error occurred', variant: 'destructive' });
      setIsTwoFactorOpen(false);
    },
  });

  if (query.isLoading) return <LoadingState title="Loading device detail" rows={5} />;
  if (query.isError) return <ErrorState onRetry={() => query.refetch()} title="Device detail could not be loaded" />;

  const device = query.data;

  if (!device) {
    return <EmptyState title="Device was not found" description="The selected device may not exist or may no longer be visible to this admin." icon={Smartphone} />;
  }

  const lockState = device.lockState || device.lock_level || 'NONE';
  const hasLocation = Boolean(device.lastLocation?.timestamp || device.last_location_time);

  const triggerAction = (type: 'LOCK' | 'UNLOCK') => {
    setPendingAction({ type, deviceId: id! });
    setIsTwoFactorOpen(true);
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title={device.model || device.device_name || 'Device Detail'}
        description={`IMEI ${device.imei || 'not captured'} - ${device.brand || 'Unknown brand'}`}
        action={
          <Button asChild variant="outline" className="bg-white/70">
            <Link to="/devices"><ArrowLeft className="mr-2 h-4 w-4" /> Back to devices</Link>
          </Button>
        }
      />

      <BentoPanel className="grid gap-5 lg:grid-cols-[1fr_auto]">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-3">
            <Badge variant={lockState === 'FULL_LOCK' ? 'destructive' : lockState === 'NONE' || lockState === 'UNLOCKED' ? 'success' : 'warning'}>
              {lockState}
            </Badge>
            <Badge variant="outline">{device.status || 'active'}</Badge>
          </div>
          <div className="mt-5 grid gap-3 sm:grid-cols-3">
            <div>
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Dealer</p>
              <p className="mt-1 truncate text-sm font-medium text-emerald-950">{device.dealer_name || device.dealerId || device.dealer_id || 'Unassigned'}</p>
            </div>
            <div>
              <p className="text-xs uppercase tracking-wide text-muted-foreground">Owner</p>
              <p className="mt-1 truncate text-sm font-medium text-emerald-950">{device.owner_name || 'No owner linked'}</p>
            </div>
            <div>
              <p className="text-xs uppercase tracking-wide text-muted-foreground">EMI status</p>
              <p className="mt-1 text-sm font-medium text-emerald-950">{device.isOverdue ? `Overdue ${device.overdueDays || 0} days` : 'On Track'}</p>
            </div>
          </div>
        </div>
        <div className="grid gap-2 sm:grid-cols-2 lg:w-72">
          <Button variant="outline" onClick={() => triggerAction('UNLOCK')} disabled={lockState === 'NONE' || lockState === 'UNLOCKED'}>
            <Unlock className="mr-2 h-4 w-4" /> Unlock
          </Button>
          <Button variant="destructive" onClick={() => triggerAction('LOCK')} disabled={lockState === 'FULL_LOCK'}>
            <Lock className="mr-2 h-4 w-4" /> Full Lock
          </Button>
        </div>
      </BentoPanel>

      <div className="grid gap-4 lg:grid-cols-3">
        <BentoPanel>
          <h2 className="text-lg font-semibold text-emerald-950">Device Information</h2>
          <div className="mt-5 space-y-4 text-sm">
            <InfoRow label="IMEI" value={device.imei || 'Not captured'} mono />
            <InfoRow label="Serial" value={device.serial_number || 'Not captured'} mono />
            <InfoRow label="Model" value={device.model || 'Unknown'} />
            <InfoRow label="Brand" value={device.brand || 'Unknown'} />
          </div>
        </BentoPanel>

        <BentoPanel className="lg:col-span-2">
          <h2 className="text-lg font-semibold text-emerald-950">Location & Connectivity</h2>
          {hasLocation ? (
            <div className="mt-5 rounded-lg border border-emerald-100 bg-emerald-50/70 p-5">
              <MapPin className="h-6 w-6 text-emerald-700" />
              <p className="mt-3 text-sm font-medium">Last seen: {device.lastLocation?.timestamp || device.last_location_time}</p>
              <p className="text-xs text-muted-foreground">
                {device.lastLocation?.lat || device.last_location_lat}, {device.lastLocation?.lng || device.last_location_lng}
              </p>
            </div>
          ) : (
            <EmptyState title="No location has been reported" description="Location appears after the locker app or policy channel reports telemetry." icon={MapPin} />
          )}
        </BentoPanel>
      </div>

      <Tabs defaultValue="logs">
        <TabsList className="bg-white/70">
          <TabsTrigger value="logs"><History className="mr-2 h-4 w-4" /> Audit Log</TabsTrigger>
          <TabsTrigger value="schedule"><FileText className="mr-2 h-4 w-4" /> EMI Schedule</TabsTrigger>
          <TabsTrigger value="security"><ShieldAlert className="mr-2 h-4 w-4" /> Security</TabsTrigger>
        </TabsList>
        <TabsContent value="logs" className="mt-4">
          <EmptyState title="No audit records for this device yet" description="Device-level actions will appear here after enrollment, locking, unlock, or decoupling." icon={History} />
        </TabsContent>
        <TabsContent value="schedule" className="mt-4">
          <EmptyState title="No EMI schedule is attached" description="Once a schedule is linked, installments and payment state will be shown here." icon={FileText} />
        </TabsContent>
        <TabsContent value="security" className="mt-4">
          <EmptyState title="No critical security events for this device" description="Integrity, tamper, and fraud signals will appear here when reported." icon={ShieldAlert} />
        </TabsContent>
      </Tabs>

      <TwoFactorModal
        isOpen={isTwoFactorOpen}
        onClose={() => setIsTwoFactorOpen(false)}
        onConfirm={code => pendingAction && actionMutation.mutate({ ...pendingAction, code })}
        title="Confirm device action"
        description="This action changes the device operational state. Verify your identity before continuing."
      />
    </div>
  );
};

function InfoRow({ label, value, mono = false }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 border-b border-emerald-100 pb-3 last:border-0 last:pb-0">
      <span className="text-muted-foreground">{label}</span>
      <span className={mono ? 'font-mono text-xs text-emerald-950' : 'text-right font-medium text-emerald-950'}>{value}</span>
    </div>
  );
}

export default DeviceDetail;
