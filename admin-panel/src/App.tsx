import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from '@/stores/authStore';
import { LoginPage } from '@/pages/LoginPage';
import { AdminLayout } from '@/components/AdminLayout';
import { DashboardPage } from '@/pages/DashboardPage';
import { DevicesPage } from '@/pages/DevicesPage';
import { DeviceDetailPage } from '@/pages/DeviceDetailPage';
import { ResellersPage } from '@/pages/ResellersPage';
import { KeyRequestsPage } from '@/pages/KeyRequestsPage';
import { DecouplingPage } from '@/pages/DecouplingPage';
import { AuditLogPage } from '@/pages/AuditLogPage';
import { SecurityEventsPage } from '@/pages/SecurityEventsPage';
import { NeirQueuePage } from '@/pages/NeiraQueuePage';
import { TwoFactorModal } from '@/components/TwoFactorModal';

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated } = useAuthStore();
  
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  
  return <>{children}</>;
}

function App() {
  return (
    <>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/"
          element={
            <ProtectedRoute>
              <AdminLayout />
            </ProtectedRoute>
          }
        >
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="dashboard" element={<DashboardPage />} />
          <Route path="devices" element={<DevicesPage />} />
          <Route path="devices/:id" element={<DeviceDetailPage />} />
          <Route path="resellers" element={<ResellersPage />} />
          <Route path="key-requests" element={<KeyRequestsPage />} />
          <Route path="decoupling" element={<DecouplingPage />} />
          <Route path="audit-log" element={<AuditLogPage />} />
          <Route path="security-events" element={<SecurityEventsPage />} />
          <Route path="neir-queue" element={<NeirQueuePage />} />
        </Route>
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
      <TwoFactorModal />
    </>
  );
}

export default App;