import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import AdminLayout from '@/components/layout/AdminLayout';
import { LoginPage } from '@/pages/LoginPage';
import Dashboard from '@/pages/dashboard';
import Devices from '@/pages/devices';
import DeviceDetail from '@/pages/devices/DeviceDetail';
import Resellers from '@/pages/resellers';
import KeyRequests from '@/pages/key-requests';
import Decoupling from '@/pages/decoupling';
import AuditLogPage from '@/pages/audit-log';
import SecurityEvents from '@/pages/security-events';
import NeirQueue from '@/pages/neir-queue';
import Dealers from '@/pages/dealers';
import Districts from '@/pages/districts';

const queryClient = new QueryClient();

const App: React.FC = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />

          <Route element={<AdminLayout />}>
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/devices" element={<Devices />} />
            <Route path="/devices/:id" element={<DeviceDetail />} />
            <Route path="/resellers" element={<Resellers />} />
            <Route path="/dealers" element={<Dealers />} />
            <Route path="/districts" element={<Districts />} />
            <Route path="/key-requests" element={<KeyRequests />} />
            <Route path="/decoupling" element={<Decoupling />} />
            <Route path="/audit-log" element={<AuditLogPage />} />
            <Route path="/security-events" element={<SecurityEvents />} />
            <Route path="/neir-queue" element={<NeirQueue />} />
          </Route>

          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
};

export default App;
