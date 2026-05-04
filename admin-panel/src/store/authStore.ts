import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface AuthState {
  isAuthenticated: boolean
  admin: {
    id: string
    name: string
    email: string
    role: string
  } | null
  setAuth: (admin: AuthState['admin']) => void
  logout: () => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      isAuthenticated: false,
      admin: null,
      setAuth: (admin) => set({ isAuthenticated: !!admin, admin }),
      logout: () => set({ isAuthenticated: false, admin: null }),
    }),
    {
      name: 'emi-auth-storage',
    }
  )
)