import { Outlet, Link, useLocation, useNavigate } from 'react-router-dom';
import { 
  LayoutDashboard, 
  Smartphone, 
  Users, 
  Key, 
  Unplug, 
  FileText, 
  Shield, 
  Flag,
  LogOut,
  Menu,
  X
} from 'lucide-react';
import { useState } from 'react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { useAuthStore } from '@/stores/authStore';
import api from '@/lib/api';

const navItems = [
  { href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/devices', label: 'Devices', icon: Smartphone },
  { href: '/resellers', label: 'Resellers', icon: Users },
  { href: '/key-requests', label: 'Key Requests', icon: Key },
  { href: '/decoupling', label: 'Decoupling', icon: Unplug },
  { href: '/audit-log', label: 'Audit Log', icon: FileText },
  { href: '/security-events', label: 'Security Events', icon: Shield },
  { href: '/neir-queue', label: 'NEIR Queue', icon: Flag },
];

export function AdminLayout() {
  const location = useLocation();
  const navigate = useNavigate();
  const { user, logout } = useAuthStore();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  const handleLogout = async () => {
    try {
      await api.post('/api/admin/auth/logout');
    } finally {
      logout();
      navigate('/login');
    }
  };

  return (
    <div className="h-screen w-screen overflow-hidden flex bg-background">
      {/* Mobile Backdrop */}
      {sidebarOpen && (
        <div 
          className="fixed inset-0 z-40 bg-black/50 backdrop-blur-sm lg:hidden transition-opacity"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <aside className={cn(
        "fixed inset-y-0 left-0 z-50 w-64 bg-sidebar border-r shadow-2xl lg:shadow-none transition-transform lg:static lg:translate-x-0 flex flex-col",
        sidebarOpen ? "translate-x-0" : "-translate-x-full"
      )}>
        <div className="flex-shrink-0 flex h-16 items-center justify-between px-6 border-b">
          <span className="text-xl font-bold bg-gradient-to-r from-primary to-emerald-400 bg-clip-text text-transparent">
            EMI Admin
          </span>
          <button onClick={() => setSidebarOpen(false)} className="lg:hidden text-sidebar-foreground hover:bg-sidebar-accent p-1 rounded-md">
            <X className="h-5 w-5" />
          </button>
        </div>

        <nav className="flex-1 overflow-y-auto space-y-1 px-4 py-6 scrollbar-none">
          {navItems.map((item) => {
            const isActive = location.pathname === item.href || 
              (item.href !== '/dashboard' && location.pathname.startsWith(item.href));
            return (
              <Link
                key={item.href}
                to={item.href}
                onClick={() => setSidebarOpen(false)}
                className={cn(
                  "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all duration-200",
                  isActive 
                    ? "bg-primary/10 text-primary shadow-sm" 
                    : "text-sidebar-foreground hover:bg-sidebar-accent hover:translate-x-1"
                )}
              >
                <item.icon className={cn("h-5 w-5", isActive ? "text-primary" : "text-sidebar-foreground/70")} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex-shrink-0 border-t p-4 bg-sidebar">
          <div className="flex items-center gap-3 mb-4">
            <div className="h-10 w-10 rounded-xl bg-gradient-to-br from-primary/20 to-primary/10 border border-primary/20 flex items-center justify-center shadow-inner">
              <span className="text-sm font-bold text-primary">
                {user?.name?.charAt(0) || 'A'}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-sidebar-foreground truncate">{user?.name || 'Administrator'}</p>
              <p className="text-xs text-sidebar-foreground/60 truncate">{user?.email || 'admin@emilocker.com'}</p>
            </div>
          </div>
          <Button variant="ghost" className="w-full justify-start gap-3 text-sidebar-foreground hover:text-destructive hover:bg-destructive/10 rounded-xl transition-colors" onClick={handleLogout}>
            <LogOut className="h-5 w-5" />
            Logout
          </Button>
        </div>
      </aside>

      <div className="flex-1 flex flex-col min-w-0 h-screen overflow-hidden bg-background">
        <header className="flex-shrink-0 flex h-16 items-center gap-4 border-b bg-background/80 backdrop-blur-md px-4 sm:px-6 z-30">
          <button onClick={() => setSidebarOpen(true)} className="lg:hidden p-2 rounded-md hover:bg-accent text-foreground">
            <Menu className="h-6 w-6" />
          </button>
          <div className="flex-1" />
        </header>

        <main className="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8 scroll-smooth">
          <div className="mx-auto max-w-7xl h-full animate-in fade-in duration-500">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}