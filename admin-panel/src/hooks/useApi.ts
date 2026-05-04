import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '@/lib/api';
import type {
  DashboardStats,
  Device,
  PaginatedResponse,
  DecouplingDevice,
  AuditLogEntry,
  SecurityEvent,
  NeirQueueItem,
  Reseller,
  KeyRequest,
  User,
} from '@/types';

export function useDashboardStats() {
  return useQuery({
    queryKey: ['dashboard', 'stats'],
    queryFn: () => api.get<DashboardStats>('/api/admin/dashboard/stats'),
    refetchInterval: 30000,
  });
}

export function useDevices(params?: {
  page?: number;
  limit?: number;
  search?: string;
  state?: string;
  dealerId?: string;
  overdue?: boolean;
}) {
  return useQuery({
    queryKey: ['devices', params],
    queryFn: () => api.get<PaginatedResponse<Device>>('/api/admin/devices', { params }),
  });
}

export function useDevice(id: string) {
  return useQuery({
    queryKey: ['device', id],
    queryFn: () => api.get<Device>(`/api/admin/devices/${id}`),
    enabled: !!id,
  });
}

export function useDeviceAuditLog(deviceId: string, params?: { page?: number; limit?: number }) {
  return useQuery({
    queryKey: ['device', deviceId, 'audit-log', params],
    queryFn: () => api.get<PaginatedResponse<AuditLogEntry>>(`/api/admin/devices/${deviceId}/audit-log`, { params }),
    enabled: !!deviceId,
  });
}

export function useDeviceEmiSchedule(deviceId: string) {
  return useQuery({
    queryKey: ['device', deviceId, 'emi-schedule'],
    queryFn: () => api.get<{ schedules: unknown[] }>(`/api/admin/devices/${deviceId}/emi-schedule`),
    enabled: !!deviceId,
  });
}

export function useDeviceLocationHistory(deviceId: string, params?: { page?: number; limit?: number }) {
  return useQuery({
    queryKey: ['device', deviceId, 'location-history', params],
    queryFn: () => api.get<{ locations: unknown[] }>(`/api/admin/devices/${deviceId}/location-history`, { params }),
    enabled: !!deviceId,
  });
}

export function useResellers(params?: { page?: number; limit?: number; status?: string }) {
  return useQuery({
    queryKey: ['resellers', params],
    queryFn: () => api.get<PaginatedResponse<Reseller>>('/api/admin/resellers', { params }),
  });
}

export function useApproveReseller() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (resellerId: string) =>
      api.post(`/api/admin/resellers/${resellerId}/approve`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['resellers'] });
    },
  });
}

export function useSuspendReseller() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ resellerId, reason }: { resellerId: string; reason: string }) =>
      api.post(`/api/admin/resellers/${resellerId}/suspend`, { reason }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['resellers'] });
    },
  });
}

export function useUpdateResellerQuota() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ resellerId, quota }: { resellerId: string; quota: number }) =>
      api.patch(`/api/admin/resellers/${resellerId}/quota`, { quota }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['resellers'] });
    },
  });
}

export function useKeyRequests(params?: { page?: number; limit?: number; status?: string }) {
  return useQuery({
    queryKey: ['key-requests', params],
    queryFn: () => api.get<PaginatedResponse<KeyRequest>>('/api/admin/key-requests', { params }),
  });
}

export function useApproveKeyRequest() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (requestId: string) =>
      api.post(`/api/admin/key-requests/${requestId}/approve`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['key-requests'] });
    },
  });
}

export function useRejectKeyRequest() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ requestId, reason }: { requestId: string; reason: string }) =>
      api.post(`/api/admin/key-requests/${requestId}/reject`, { reason }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['key-requests'] });
    },
  });
}

export function useDecouplingDevices(params?: { page?: number; limit?: number }) {
  return useQuery({
    queryKey: ['decoupling', params],
    queryFn: () => api.get<PaginatedResponse<DecouplingDevice>>('/api/admin/decoupling', { params }),
  });
}

export function useExecuteDecoupling() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ deviceId, code }: { deviceId: string; code: string }) =>
      api.post(`/api/admin/decoupling/${deviceId}/execute`, { code }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['decoupling'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useAuditLog(params?: {
  page?: number;
  limit?: number;
  action?: string;
  targetType?: string;
  startDate?: string;
  endDate?: string;
  adminId?: string;
}) {
  return useQuery({
    queryKey: ['audit-log', params],
    queryFn: () => api.get<PaginatedResponse<AuditLogEntry>>('/api/admin/audit-log', { params }),
  });
}

export function useSecurityEvents(params?: {
  page?: number;
  limit?: number;
  severity?: string;
  resolved?: boolean;
}) {
  return useQuery({
    queryKey: ['security-events', params],
    queryFn: () => api.get<PaginatedResponse<SecurityEvent>>('/api/admin/security-events', { params }),
  });
}

export function useResolveSecurityEvent() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ eventId, resolution }: { eventId: string; resolution: string }) =>
      api.post(`/api/admin/security-events/${eventId}/resolve`, { resolution }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['security-events'] });
    },
  });
}

export function useNeiraQueue(params?: { page?: number; limit?: number }) {
  return useQuery({
    queryKey: ['neir-queue', params],
    queryFn: () => api.get<PaginatedResponse<NeirQueueItem>>('/api/admin/neir-queue', { params }),
  });
}

export function useSubmitNeiraReport() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ itemId, evidence }: { itemId: string; evidence: unknown }) =>
      api.post(`/api/admin/neir-queue/${itemId}/report`, { evidence }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['neir-queue'] });
    },
  });
}

export function useLockDevice() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ deviceId, code }: { deviceId: string; code: string }) =>
      api.post(`/api/admin/devices/${deviceId}/lock`, { code }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useUnlockDevice() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ deviceId, code }: { deviceId: string; code: string }) =>
      api.post(`/api/admin/devices/${deviceId}/unlock`, { code }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useSuspendDevice() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ deviceId, reason, code }: { deviceId: string; reason: string; code: string }) =>
      api.post(`/api/admin/devices/${deviceId}/suspend`, { reason, code }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['devices'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard'] });
    },
  });
}

export function useCurrentUser() {
  return useQuery({
    queryKey: ['current-user'],
    queryFn: () => api.get<User>('/api/admin/auth/me'),
  });
}