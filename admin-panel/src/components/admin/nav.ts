import {
  FileText,
  Key,
  LayoutDashboard,
  Radio,
  ShieldAlert,
  Smartphone,
  Unlink,
  Users,
} from 'lucide-react';

export const primaryNavItems = [
  { name: 'Dashboard', path: '/dashboard', icon: LayoutDashboard },
  { name: 'Devices', path: '/devices', icon: Smartphone },
  { name: 'Resellers', path: '/resellers', icon: Users },
  { name: 'Keys', path: '/key-requests', icon: Key },
];

export const secondaryNavItems = [
  { name: 'Decoupling', path: '/decoupling', icon: Unlink },
  { name: 'Audit Log', path: '/audit-log', icon: FileText },
  { name: 'Security', path: '/security-events', icon: ShieldAlert },
  { name: 'NEIR Queue', path: '/neir-queue', icon: Radio },
];

export const navItems = [...primaryNavItems, ...secondaryNavItems];
