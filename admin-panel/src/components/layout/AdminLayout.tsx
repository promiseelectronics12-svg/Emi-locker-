import React, { useState } from 'react';
import { Link, Navigate, Outlet, useLocation } from 'react-router-dom';
import { X } from 'lucide-react';
import { primaryNavItems, secondaryNavItems } from '@/components/admin/nav';
import { Button } from '@/components/ui/button';
import { useAuthStore } from '@/store/authStore';
import { cn } from '@/lib/utils';
import { AdminSSEProvider } from '@/contexts/AdminSSEContext';
import Sidebar from './Sidebar';
import TopNav from './TopNav';

const AdminLayout: React.FC = () => {
  const { isAuthenticated } = useAuthStore();
  const [menuOpen, setMenuOpen] = useState(false);
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return (
    <AdminSSEProvider>
    <div className="bento-grid-bg min-h-screen">
      <div className="flex min-h-screen">
        <Sidebar />
        <div className="flex min-w-0 flex-1 flex-col pb-20 lg:pb-0">
          <TopNav onMenuClick={() => setMenuOpen(true)} />
          <main className="mx-auto w-full max-w-[1500px] flex-1 p-4 sm:p-6 lg:p-8">
            <Outlet />
          </main>
        </div>
      </div>

      <nav className="fixed inset-x-3 bottom-3 z-30 rounded-lg border border-white/70 bg-white/90 p-2 shadow-[0_18px_55px_rgba(15,118,110,0.18)] backdrop-blur-xl lg:hidden">
        <div className="grid grid-cols-4 gap-1">
          {primaryNavItems.map(({ name, path, icon: Icon }) => {
            const active = location.pathname === path || location.pathname.startsWith(`${path}/`);
            return (
              <Link
                key={path}
                to={path}
                className={cn(
                  'flex min-w-0 flex-col items-center gap-1 rounded-lg px-2 py-2 text-[11px] font-medium',
                  active ? 'bg-emerald-600 text-white' : 'text-muted-foreground hover:bg-emerald-50 hover:text-emerald-800'
                )}
              >
                <Icon className="h-4 w-4" />
                <span className="truncate">{name}</span>
              </Link>
            );
          })}
        </div>
      </nav>

      {menuOpen ? (
        <div className="fixed inset-0 z-40 bg-emerald-950/40 backdrop-blur-sm lg:hidden" onClick={() => setMenuOpen(false)}>
          <div
            className="ml-auto h-full w-[86vw] max-w-sm bg-emerald-950 p-4 text-white shadow-2xl"
            onClick={event => event.stopPropagation()}
          >
            <div className="mb-5 flex items-center justify-between">
              <div>
                <p className="font-semibold">More admin tools</p>
                <p className="text-xs text-emerald-100/60">Secondary operations</p>
              </div>
              <Button variant="ghost" size="icon" className="text-white hover:bg-white/10" onClick={() => setMenuOpen(false)}>
                <X className="h-4 w-4" />
              </Button>
            </div>
            <div className="space-y-2">
              {secondaryNavItems.map(({ name, path, icon: Icon }) => (
                <Link
                  key={path}
                  to={path}
                  onClick={() => setMenuOpen(false)}
                  className="flex items-center gap-3 rounded-lg px-3 py-3 text-sm text-emerald-50/76 hover:bg-white/10 hover:text-white"
                >
                  <Icon className="h-4 w-4" />
                  {name}
                </Link>
              ))}
            </div>
          </div>
        </div>
      ) : null}
    </div>
    </AdminSSEProvider>
  );
};

export default AdminLayout;
