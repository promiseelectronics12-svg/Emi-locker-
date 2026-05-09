import React, { useRef, useState } from 'react';
import { Bell, CheckCheck, Key, Menu, Search, ShieldAlert, Smartphone, User } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useAuthStore } from '@/store/authStore';
import { useAdminSSE, AdminNotification } from '@/contexts/AdminSSEContext';

type TopNavProps = { onMenuClick: () => void };

function timeAgo(iso: string) {
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

const NOTIF_META: Record<string, {
  icon: React.ReactNode;
  iconBg: string;
  route: string;
  label: string;
}> = {
  key_requested: {
    icon: <Key className="h-3.5 w-3.5 text-emerald-600" />,
    iconBg: 'bg-emerald-50 ring-1 ring-emerald-100',
    route: '/key-requests',
    label: 'View requests',
  },
  new_alert: {
    icon: <ShieldAlert className="h-3.5 w-3.5 text-red-500" />,
    iconBg: 'bg-red-50 ring-1 ring-red-100',
    route: '/alerts',
    label: 'View alerts',
  },
  enrollment_complete: {
    icon: <Smartphone className="h-3.5 w-3.5 text-blue-500" />,
    iconBg: 'bg-blue-50 ring-1 ring-blue-100',
    route: '/devices',
    label: 'View devices',
  },
  device_locked: {
    icon: <Smartphone className="h-3.5 w-3.5 text-amber-500" />,
    iconBg: 'bg-amber-50 ring-1 ring-amber-100',
    route: '/devices',
    label: 'View devices',
  },
};

const DEFAULT_META = {
  icon: <Bell className="h-3.5 w-3.5 text-slate-400" />,
  iconBg: 'bg-slate-50 ring-1 ring-slate-100',
  route: null,
  label: null,
};

function NotifItem({ n, onNavigate }: { n: AdminNotification; onNavigate: (route: string) => void }) {
  const meta = NOTIF_META[n.type] ?? DEFAULT_META;
  const clickable = !!meta.route;

  return (
    <div
      role={clickable ? 'button' : undefined}
      tabIndex={clickable ? 0 : undefined}
      onClick={clickable ? () => onNavigate(meta.route!) : undefined}
      onKeyDown={clickable ? (e) => e.key === 'Enter' && onNavigate(meta.route!) : undefined}
      className={[
        'group flex gap-3 px-4 py-3.5 transition-all',
        n.read ? 'opacity-55' : 'bg-gradient-to-r from-emerald-50/70 to-transparent',
        clickable ? 'cursor-pointer hover:bg-slate-50 active:bg-slate-100' : '',
      ].join(' ')}
    >
      {/* Icon */}
      <div className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${meta.iconBg}`}>
        {meta.icon}
      </div>

      {/* Text */}
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-semibold leading-tight tracking-[-0.1px] text-slate-800">
          {n.title}
        </p>
        <p className="mt-1 text-[12px] font-medium leading-snug text-slate-500">{n.body}</p>
        <div className="mt-1.5 flex items-center gap-2">
          <p className="text-[11px] font-medium text-slate-400">{timeAgo(n.at)}</p>
          {clickable && (
            <span className="text-[11px] font-semibold text-emerald-600 opacity-0 transition-opacity group-hover:opacity-100">
              {meta.label} →
            </span>
          )}
        </div>
      </div>

      {/* Unread dot */}
      {!n.read && (
        <div className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-emerald-500 shadow-sm shadow-emerald-200" />
      )}
    </div>
  );
}

const TopNav: React.FC<TopNavProps> = ({ onMenuClick }) => {
  const { user } = useAuthStore();
  const { notifications, unread, markAllRead } = useAdminSSE();
  const [open, setOpen] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  function togglePanel() {
    setOpen(v => {
      if (!v) markAllRead();
      return !v;
    });
  }

  function handleNavigate(route: string) {
    setOpen(false);
    navigate(route);
  }

  return (
    <header className="sticky top-0 z-20 border-b border-white/60 bg-background/80 px-4 py-3 backdrop-blur-xl lg:px-6">
      <div className="flex items-center gap-3">
        <Button variant="outline" size="icon" className="bg-white/70 lg:hidden" onClick={onMenuClick}>
          <Menu className="h-4 w-4" />
        </Button>

        <div className="relative hidden min-w-0 flex-1 sm:block">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder="Search devices, resellers, audit logs..."
            className="h-10 max-w-xl border-white/70 bg-white/70 pl-10 shadow-sm"
          />
        </div>

        <div className="ml-auto flex items-center gap-2">
          {/* Notification bell */}
          <div className="relative">
            <Button
              variant="outline"
              size="icon"
              className="relative bg-white/70"
              onClick={togglePanel}
            >
              <Bell className="h-4 w-4" />
              {unread > 0 && (
                <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-red-500 text-[10px] font-bold text-white shadow-sm">
                  {unread > 9 ? '9+' : unread}
                </span>
              )}
            </Button>

            {open && (
              <>
                <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
                <div
                  ref={panelRef}
                  className="absolute right-0 top-full z-40 mt-2 w-[340px] overflow-hidden rounded-2xl border border-slate-200/80 bg-white shadow-2xl shadow-slate-200/60"
                >
                  {/* Panel header */}
                  <div className="flex items-center justify-between border-b border-slate-100 px-4 py-3.5">
                    <div>
                      <p className="text-[14px] font-bold tracking-[-0.2px] text-slate-800">
                        Notifications
                      </p>
                      <p className="text-[11px] font-medium text-slate-400">
                        {notifications.length === 0 ? 'All clear' : `${notifications.length} total`}
                      </p>
                    </div>
                    {notifications.length > 0 && (
                      <button
                        onClick={markAllRead}
                        className="flex items-center gap-1 rounded-lg px-2 py-1 text-[11px] font-semibold text-emerald-600 hover:bg-emerald-50 hover:text-emerald-700 transition-colors"
                      >
                        <CheckCheck className="h-3 w-3" /> Mark all read
                      </button>
                    )}
                  </div>

                  {/* Items */}
                  <div className="max-h-[420px] overflow-y-auto divide-y divide-slate-100/80">
                    {notifications.length === 0 ? (
                      <div className="flex flex-col items-center gap-2 px-4 py-10 text-center">
                        <Bell className="h-8 w-8 text-slate-200" />
                        <p className="text-[13px] font-semibold text-slate-400">No notifications yet</p>
                        <p className="text-[12px] text-slate-300">Events will appear here in real time</p>
                      </div>
                    ) : (
                      notifications.map(n => (
                        <NotifItem key={n.id} n={n} onNavigate={handleNavigate} />
                      ))
                    )}
                  </div>
                </div>
              </>
            )}
          </div>

          <div className="hidden items-center gap-3 rounded-xl border border-white/70 bg-white/70 px-3 py-2 shadow-sm sm:flex">
            <div className="text-right">
              <p className="max-w-44 truncate text-[13px] font-semibold tracking-[-0.1px] text-emerald-950">
                {user?.email || 'Admin User'}
              </p>
              <p className="text-[11px] font-medium capitalize text-muted-foreground">{user?.role || 'admin'}</p>
            </div>
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-emerald-100 text-emerald-700">
              <User className="h-4 w-4" />
            </div>
          </div>
        </div>
      </div>
    </header>
  );
};

export default TopNav;
