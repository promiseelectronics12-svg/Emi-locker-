import { useEffect, useRef, useState } from 'react';
import { useAuthStore } from '@/store/authStore';

export interface AdminNotification {
  id: string;
  type: 'key_requested' | 'new_alert' | 'enrollment_complete' | 'device_locked';
  title: string;
  body: string;
  at: string;
  read: boolean;
  data: Record<string, unknown>;
}

let _notifAudio: HTMLAudioElement | null = null;

function playDing() {
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
    const tierLabel = tier.charAt(0).toUpperCase() + tier.slice(1);
    return {
      id, type: 'key_requested', at, read: false, data,
      title: 'Key Request',
      body: `${data.resellerName} requested ${data.quantity} ${tierLabel} keys`,
    };
  }
  if (event === 'new_alert') {
    return {
      id, type: 'new_alert', at, read: false, data,
      title: 'Security Alert',
      body: `${data.type || 'Alert'} on device ${data.deviceName || data.deviceId}`,
    };
  }
  if (event === 'enrollment_complete') {
    return {
      id, type: 'enrollment_complete', at, read: false, data,
      title: 'Device Enrolled',
      body: `${data.deviceName || data.deviceId} enrolled successfully`,
    };
  }
  if (event === 'device_locked') {
    return {
      id, type: 'device_locked', at, read: false, data,
      title: 'Device Locked',
      body: `${data.deviceName || data.deviceId} locked — ${data.reason || ''}`,
    };
  }
  return null;
}

export function useAdminNotifications() {
  const { token } = useAuthStore();
  const [notifications, setNotifications] = useState<AdminNotification[]>([]);
  const esRef = useRef<EventSource | null>(null);

  const unread = notifications.filter(n => !n.read).length;

  function markAllRead() {
    setNotifications(prev => prev.map(n => ({ ...n, read: true })));
  }

  useEffect(() => {
    if (!token) return;

    const baseUrl = (import.meta as any).env?.VITE_API_BASE_URL || 'http://localhost:3000';
    const url = `${baseUrl}/api/v1/events?token=${encodeURIComponent(token)}`;

    const es = new EventSource(url);
    esRef.current = es;

    const TRACKED = ['key_requested', 'new_alert', 'enrollment_complete', 'device_locked'];

    TRACKED.forEach(event => {
      es.addEventListener(event, (e: MessageEvent) => {
        try {
          const data = JSON.parse(e.data);
          const notif = buildNotification(event, data);
          if (notif) {
            setNotifications(prev => [notif, ...prev].slice(0, 50));
            playDing();
          }
        } catch (_) {}
      });
    });

    es.onerror = () => {
      es.close();
      esRef.current = null;
    };

    return () => {
      es.close();
      esRef.current = null;
    };
  }, [token]);

  return { notifications, unread, markAllRead };
}
