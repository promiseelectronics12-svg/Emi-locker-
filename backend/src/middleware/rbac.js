const ROLES = {
  ADMIN: 'admin',
  RESELLER: 'reseller',
  DEALER: 'dealer',
  CUSTOMER: 'customer'
};

const ROLE_HIERARCHY = {
  [ROLES.ADMIN]: 4,
  [ROLES.RESELLER]: 3,
  [ROLES.DEALER]: 2,
  [ROLES.CUSTOMER]: 1
};

const PERMISSIONS = {
  USERS_CREATE: 'users:create',
  USERS_READ: 'users:read',
  USERS_UPDATE: 'users:update',
  USERS_DELETE: 'users:delete',
  DEVICES_ENROLL: 'devices:enroll',
  DEVICES_READ: 'devices:read',
  DEVICES_UPDATE: 'devices:update',
  DEVICES_DELETE: 'devices:delete',
  DEVICES_LOCK: 'devices:lock',
  DEVICES_UNLOCK: 'devices:unlock',
  DEVICES_DECOUPLE: 'devices:decouple',
  KEYS_CREATE: 'keys:create',
  KEYS_READ: 'keys:read',
  KEYS_ASSIGN: 'keys:assign',
  PAYMENTS_READ: 'payments:read',
  PAYMENTS_CREATE: 'payments:create',
  EMI_READ: 'emi:read',
  EMI_CREATE: 'emi:create',
  EMI_UPDATE: 'emi:update',
  REPORTS_READ: 'reports:read',
  ADMIN_ALL: 'admin:all'
};

const ROLE_PERMISSIONS = {
  [ROLES.ADMIN]: [
    PERMISSIONS.ADMIN_ALL,
    PERMISSIONS.USERS_CREATE,
    PERMISSIONS.USERS_READ,
    PERMISSIONS.USERS_UPDATE,
    PERMISSIONS.USERS_DELETE,
    PERMISSIONS.DEVICES_ENROLL,
    PERMISSIONS.DEVICES_READ,
    PERMISSIONS.DEVICES_UPDATE,
    PERMISSIONS.DEVICES_DELETE,
    PERMISSIONS.DEVICES_LOCK,
    PERMISSIONS.DEVICES_UNLOCK,
    PERMISSIONS.DEVICES_DECOUPLE,
    PERMISSIONS.KEYS_CREATE,
    PERMISSIONS.KEYS_READ,
    PERMISSIONS.KEYS_ASSIGN,
    PERMISSIONS.PAYMENTS_READ,
    PERMISSIONS.PAYMENTS_CREATE,
    PERMISSIONS.EMI_READ,
    PERMISSIONS.EMI_CREATE,
    PERMISSIONS.EMI_UPDATE,
    PERMISSIONS.REPORTS_READ
  ],
  [ROLES.RESELLER]: [
    PERMISSIONS.USERS_CREATE,
    PERMISSIONS.USERS_READ,
    PERMISSIONS.USERS_UPDATE,
    PERMISSIONS.DEVICES_READ,
    PERMISSIONS.KEYS_CREATE,
    PERMISSIONS.KEYS_READ,
    PERMISSIONS.KEYS_ASSIGN,
    PERMISSIONS.PAYMENTS_READ,
    PERMISSIONS.REPORTS_READ
  ],
  [ROLES.DEALER]: [
    PERMISSIONS.USERS_READ,
    PERMISSIONS.USERS_UPDATE,
    PERMISSIONS.DEVICES_ENROLL,
    PERMISSIONS.DEVICES_READ,
    PERMISSIONS.DEVICES_UPDATE,
    PERMISSIONS.DEVICES_LOCK,
    PERMISSIONS.KEYS_READ,
    PERMISSIONS.KEYS_ASSIGN,
    PERMISSIONS.PAYMENTS_READ,
    PERMISSIONS.EMI_READ,
    PERMISSIONS.EMI_CREATE,
    PERMISSIONS.EMI_UPDATE
  ],
  [ROLES.CUSTOMER]: [
    PERMISSIONS.DEVICES_READ,
    PERMISSIONS.DEVICES_UNLOCK,
    PERMISSIONS.PAYMENTS_READ,
    PERMISSIONS.EMI_READ,
    PERMISSIONS.EMI_UPDATE
  ]
};

function requireRole(...roles) {
  const allowedRoles = Array.isArray(roles[0]) ? roles[0] : roles;

  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json(buildErrorResponse(401, 'AUTHENTICATION_REQUIRED', 'Authentication required'));
    }

    const userRole = req.user.role;

    if (!allowedRoles.includes(userRole)) {
      return res.status(403).json(buildErrorResponse(403, 'INSUFFICIENT_PERMISSIONS', 'Insufficient permissions'));
    }

    next();
  };
}

function requirePermission(...permissions) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json(buildErrorResponse(401, 'AUTHENTICATION_REQUIRED', 'Authentication required'));
    }

    const userRole = req.user.role;
    const userPermissions = ROLE_PERMISSIONS[userRole] || [];

    const hasAllPermissions = permissions.every(perm =>
      userPermissions.includes(perm) || userPermissions.includes(PERMISSIONS.ADMIN_ALL)
    );

    if (!hasAllPermissions) {
      return res.status(403).json(buildErrorResponse(403, 'INSUFFICIENT_PERMISSIONS', 'Insufficient permissions'));
    }

    next();
  };
}

function requireMinRole(minRole) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json(buildErrorResponse(401, 'AUTHENTICATION_REQUIRED', 'Authentication required'));
    }

    const userRoleLevel = ROLE_HIERARCHY[req.user.role] || 0;
    const requiredLevel = ROLE_HIERARCHY[minRole] || 0;

    if (userRoleLevel < requiredLevel) {
      return res.status(403).json(buildErrorResponse(403, 'INSUFFICIENT_PERMISSIONS', 'Insufficient permissions'));
    }

    next();
  };
}

function requireAnyRole(...roles) {
  return requireRole(...roles);
}

function requireAllRoles(...roles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json(buildErrorResponse(401, 'AUTHENTICATION_REQUIRED', 'Authentication required'));
    }

    const hasAllRoles = roles.every(role => req.user.role === role);

    if (!hasAllRoles) {
      return res.status(403).json(buildErrorResponse(403, 'INSUFFICIENT_PERMISSIONS', 'Insufficient permissions'));
    }

    next();
  };
}

function isAdmin(req, res, next) {
  return requireRole(ROLES.ADMIN)(req, res, next);
}

function isResellerOrAbove(req, res, next) {
  return requireMinRole(ROLES.RESELLER)(req, res, next);
}

function isDealerOrAbove(req, res, next) {
  return requireMinRole(ROLES.DEALER)(req, res, next);
}

module.exports = {
  ROLES,
  PERMISSIONS,
  ROLE_HIERARCHY,
  ROLE_PERMISSIONS,
  requireRole,
  requirePermission,
  requireMinRole,
  requireAnyRole,
  requireAllRoles,
  isAdmin,
  isResellerOrAbove,
  isDealerOrAbove
};
const { buildErrorResponse } = require('./errorHandler');
