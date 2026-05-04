import { create } from 'zustand'

interface TwoFactorModalState {
  isOpen: boolean
  action: string
  resourceId?: string
  onSuccess?: () => void
  onError?: (error: string) => void
  openModal: (options: {
    action: string
    resourceId?: string
    onSuccess?: () => void
    onError?: (error: string) => void
  }) => void
  closeModal: () => void
}

export const useTwoFactorStore = create<TwoFactorModalState>((set) => ({
  isOpen: false,
  action: '',
  resourceId: undefined,
  onSuccess: undefined,
  onError: undefined,
  openModal: ({ action, resourceId, onSuccess, onError }) =>
    set({
      isOpen: true,
      action,
      resourceId,
      onSuccess,
      onError,
    }),
  closeModal: () =>
    set({
      isOpen: false,
      action: '',
      resourceId: undefined,
      onSuccess: undefined,
      onError: undefined,
    }),
}))