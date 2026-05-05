import { Outlet } from 'react-router-dom'
import { Sidebar } from '@/components/Sidebar'
import { TwoFactorModal } from '@/components/TwoFactorModal'

export function Layout() {
  return (
    <div className="min-h-screen bg-background">
      <Sidebar />
      <main className="md:ml-64 p-6">
        <Outlet />
      </main>
      <TwoFactorModal />
    </div>
  )
}