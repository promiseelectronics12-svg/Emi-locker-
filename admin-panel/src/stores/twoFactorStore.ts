import { create } from 'zustand';

interface TwoFactorState {
  isOpen: boolean;
  isLoading: boolean;
  onSuccess: (() => void) | null;
  onCancel: (() => void) | null;
  actionDescription: string;
  open: (options: {
    onSuccess: () => void;
    onCancel?: () => void;
    actionDescription: string;
  }) => void;
  close: () => void;
  setLoading: (loading: boolean) => void;
  reset: () => void;
}

export const useTwoFactorStore = create<TwoFactorState>((set) => ({
  isOpen: false,
  isLoading: false,
  onSuccess: null,
  onCancel: null,
  actionDescription: '',
  open: ({ onSuccess, onCancel, actionDescription }) =>
    set({
      isOpen: true,
      onSuccess,
      onCancel: onCancel || null,
      actionDescription,
    }),
  close: () => set({
    isOpen: false,
    onSuccess: null,
    onCancel: null,
    isLoading: false,
  }),
  setLoading: (isLoading) => set({ isLoading }),
  reset: () => set({
    isOpen: false,
    isLoading: false,
    onSuccess: null,
    onCancel: null,
    actionDescription: '',
  }),
}));