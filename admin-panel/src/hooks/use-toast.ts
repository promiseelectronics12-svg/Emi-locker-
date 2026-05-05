import { useState } from "react"

interface ToastOptions {
  title: string
  description?: string
  variant?: 'default' | 'destructive'
}

export function useToast() {
  const [toasts] = useState<ToastOptions[]>([])

  const toast = ({ title, description, variant }: ToastOptions) => {
    console.log(`[Toast${variant ? ` (${variant})` : ''}] ${title}${description ? ': ' + description : ''}`)
  }

  return {
    toasts,
    toast,
    dismiss: () => {},
  }
}
