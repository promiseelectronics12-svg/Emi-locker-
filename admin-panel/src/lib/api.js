import axios from 'axios'

const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || 'http://localhost:3000',
  headers: {
    'Content-Type': 'application/json',
  },
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('auth_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('auth_token')
      window.location.href = '/login'
    }
    return Promise.reject(error)
  }
)

export const authApi = {
  login: (email, password) => api.post('/api/v1/auth/login', { email, password }),
  logout: () => api.post('/api/v1/auth/logout'),
  me: () => api.get('/api/v1/auth/me'),
}

export const usersApi = {
  getAll: (page = 1, limit = 50) => api.get(`/api/v1/admin/users?page=${page}&limit=${limit}`),
  updateStatus: (userId, status) => api.patch(`/api/v1/admin/users/${userId}/status`, { status }),
}

export const devicesApi = {
  getAll: () => api.get('/api/v1/admin/devices'),
  getById: (id) => api.get(`/api/v1/devices/${id}`),
  updateStatus: (id, status, reason) => api.patch(`/api/v1/devices/${id}/status`, { status, reason }),
}

export const dealersApi = {
  getAll: () => api.get('/api/v1/admin/dealers'),
  getById: (id) => api.get(`/api/v1/dealers/${id}`),
  getDevices: (id) => api.get(`/api/v1/dealers/${id}/devices`),
}

export const paymentsApi = {
  getAll: () => api.get('/api/v1/admin/payments'),
  getById: (id) => api.get(`/api/v1/payments/${id}`),
  confirm: (id, notes) => api.patch(`/api/v1/payments/${id}/confirm`, { status: 'confirmed', notes }),
  reject: (id, notes) => api.patch(`/api/v1/payments/${id}/confirm`, { status: 'rejected', notes }),
}

export const statsApi = {
  getDashboard: () => api.get('/api/v1/admin/stats'),
}

export default api