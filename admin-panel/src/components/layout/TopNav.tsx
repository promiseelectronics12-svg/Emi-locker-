import React from 'react';
import { Bell, Menu, Search, User } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useAuthStore } from '@/store/authStore';

type TopNavProps = {
  onMenuClick: () => void;
};

const TopNav: React.FC<TopNavProps> = ({ onMenuClick }) => {
  const { user } = useAuthStore();

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
          <Button variant="outline" size="icon" className="relative bg-white/70">
            <Bell className="h-4 w-4" />
            <span className="absolute right-2 top-2 h-2 w-2 rounded-full bg-emerald-500" />
          </Button>
          <div className="hidden items-center gap-3 rounded-lg border border-white/70 bg-white/70 px-3 py-2 shadow-sm sm:flex">
            <div className="text-right">
              <p className="max-w-44 truncate text-sm font-medium text-emerald-950">{user?.email || 'Admin User'}</p>
              <p className="text-xs capitalize text-muted-foreground">{user?.role || 'admin'}</p>
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
