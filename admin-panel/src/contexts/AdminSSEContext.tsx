import React, { createContext, useContext, useEffect, useRef, useState } from 'react';
import { useAuthStore } from '@/store/authStore';

export interface AdminNotification {
  id: string;
  type: string;
  title: string;
  body: string;
  at: string;
  read: boolean;
  data: Record<string, unknown>;
}

type EventCallback = (data: Record<string, unknown>) => void;

interface AdminSSEContextValue {
  notifications: AdminNotification[];
  unread: number;
  markAllRead: () => void;
  subscribe: (event: string, callback: EventCallback) => () => void;
}

const AdminSSEContext = createContext<AdminSSEContextValue | null>(null);

let _notifAudio: HTMLAudioElement | null = null;
function playNotification() {
  try {
    if (!_notifAudio) {
      _notifAudio = new Audio('/notification.wav');
      _notifAudio.volume = 0.8;
    }
    _notifAudio.currentTime = 0;
    _notifAudio.play().catch(() => {});
  } catch (_) {}
}

function buildNotification(event: string, data: Record<string, unknown>): AdminNotification | null {
  const id = `${Date.now()}-${Math.random()}`;
  const at = new Date().toISOString();
  if (event === 'key_requested') {
    const tier = String(data.tier || 'standard');
    const tierLabel = tier === 'vip' ? 'VIP' : tier.charAt(0).toUpperCase() + tier.slice(1);
    return { id, type: event, at, read: false, data,
      title: 'Key Request', body: `${data.resellerName} requested ${data.quantity} ${tierLabel} keys` };
  }
  if (event === 'new_alert') return { id, type: event, at, read: false, data,
    title: 'Security Alert', body: `${data.type || 'Alert'} on device ${data.deviceName || data.deviceId}` };
  if (event === 'enrollment_complete') return { id, type: event, at, read: false, data,
    title: 'Device Enrolled', body: `${data.deviceName || data.deviceId} enrolled successfully` };
  if (event === 'device_locked') return { id, type: event, at, read: false, data,
    title: 'Device Locked', body: `${data.deviceName || data.deviceId} — ${data.reason || 'locked'}` };
  return null;
}

const TRACKED_EVENTS = ['key_requested', 'new_alert', 'enrollment_complete', 'device_locked'];

export function AdminSSEProvider({ children }: { children: React.ReactNode }) {
  const { token } = useAuthStore();
  const [notifications, setNotifications] = useState<AdminNotification[]>([]);
  const subscribersRef = useRef<Map<string, Set<EventCallback>>>(new Map());
  const esRef = useRef<EventSource | null>(null);

  const unread = notifications.filter(n => !n.read).length;

  function markAllRead() {
    setNotifications(prev => prev.map(n => ({ ...n, read: true })));
  }

  function subscribe(event: string, callback: EventCallback) {
    if (!subscribersRef.current.has(event)) {
      subscribersRef.current.set(event, new Set());
    }
    subscribersRef.current.get(event)!.add(callback);
    return () => { subscribersRef.current.get(event)?.delete(callback); };
  }

  useEffect(() => {
    if (!token) return;
    const baseUrl = (import.meta as any).env?.VITE_API_BASE_URL || 'http://localhost:3000';
    const url = `${baseUrl}/api/v1/events?token=${encodeURIComponent(token)}`;
    const es = new EventSource(url);
    esRef.current = es;

    TRACKED_EVENTS.forEach(event => {
      es.addEventListener(event, (e: MessageEvent) => {
        try {
          const data = JSON.parse(e.data);
          const notif = buildNotification(event, data);
          if (notif) {
            setNotifications(prev => [notif, ...prev].slice(0, 50));
            playNotification();
          }
          subscribersRef.current.get(event)?.forEach(cb => {
            try { cb(data); } catch (_) {}
          });
        } catch (_) {}
      });
    });

    es.onerror = () => { es.close(); esRef.current = null; };
    return () => { es.close(); esRef.current = null; };
  }, [token]);

  return (
    <AdminSSEContext.Provider value={{ notifications, unread, markAllRead, subscribe }}>
      {children}
    </AdminSSEContext.Provider>
  );
}

export function useAdminSSE() {
  const ctx = useContext(AdminSSEContext);
  if (!ctx) throw new Error('useAdminSSE must be used inside AdminSSEProvider');
  return ctx;
}
