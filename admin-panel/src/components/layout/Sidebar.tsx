import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { LogOut, Shield } from 'lucide-react';
import { navItems } from '@/components/admin/nav';
import { useAuthStore } from '@/store/authStore';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

const Sidebar: React.FC = () => {
  const location = useLocation();
  const { logout } = useAuthStore();

  return (
    <aside className="hidden h-screen w-72 shrink-0 p-4 lg:block sticky top-0">
      <div className="flex h-full flex-col rounded-lg border border-white/60 bg-emerald-950/95 text-white shadow-[0_20px_60px_rgba(6,78,59,0.24)]">
        <div className="border-b border-white/10 p-5">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-emerald-500 text-white">
              <Shield className="h-5 w-5" />
            </div>
            <div>
              <p className="font-semibold">EMI Admin</p>
              <p className="text-xs text-emerald-100/60">Operations panel</p>
            </div>
          </div>
        </div>

        <nav className="flex-1 space-y-1 p-3">
          {navItems.map(({ name, path, icon: Icon }) => {
            const active = location.pathname === path || location.pathname.startsWith(`${path}/`);
            return (
              <Link
                key={path}
                to={path}
                className={cn(
                  'flex items-center gap-3 rounded-lg px-3 py-3 text-sm transition-colors',
                  active
                    ? 'bg-white text-emerald-950 shadow-sm'
                    : 'text-emerald-50/68 hover:bg-white/10 hover:text-white'
                )}
              >
                <Icon className="h-4 w-4" />
                <span>{name}</span>
              </Link>
            );
          })}
        </nav>

        <div className="p-3">
          <Button
            variant="ghost"
            className="w-full justify-start text-emerald-50/70 hover:bg-white/10 hover:text-white"
            onClick={logout}
          >
            <LogOut className="mr-3 h-4 w-4" />
            Logout
          </Button>
        </div>
      </div>
    </aside>
  );
};

export default Sidebar;
