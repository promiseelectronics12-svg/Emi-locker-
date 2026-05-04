import 'package:flutter/material.dart';

class ApiConstants {
  static const String loginEndpoint = '/api/auth/login';
  static const String registerEndpoint = '/api/auth/register';
  static const String refreshTokenEndpoint = '/api/auth/refresh';
  static const String logoutEndpoint = '/api/auth/logout';
  static const String changePasswordEndpoint = '/api/auth/change-password';
  static const String setup2FAEndpoint = '/api/auth/setup-2fa';
  static const String verify2FAEndpoint = '/api/auth/verify-2fa';
  static const String disable2FAEndpoint = '/api/auth/disable-2fa';

  static const String devicesEndpoint = '/api/devices';
  static const String enrollDeviceEndpoint = '/api/devices/enroll';
  static const String lockRequestEndpoint = '/api/devices/lock-request';
  static const String fraudFlagEndpoint = '/api/devices/fraud-flag';

  static const String emiScheduleEndpoint = '/api/emi/schedule';
  static const String paymentEndpoint = '/api/emi/payment';
  static const String decouplingEndpoint = '/api/emi/decouple';

  static const String keysEndpoint = '/api/keys';
  static const String purchaseKeyEndpoint = '/api/keys/purchase';
  static const String activateKeyEndpoint = '/api/keys/activate';

  static const String dealersEndpoint = '/api/dealers';
  static const String resellerDealersEndpoint = '/api/reseller/dealers';

  static const String analyticsEndpoint = '/api/analytics';
  static const String neirExportEndpoint = '/api/export/neir';

  static const String profileEndpoint = '/api/profile';
  static const String updateProfileEndpoint = '/api/profile/update';
}

class StorageKeys {
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String userRole = 'user_role';
  static const String userId = 'user_id';
  static const String dealerId = 'dealer_id';
  static const String resellerId = 'reseller_id';
  static const String is2FAEnabled = 'is_2fa_enabled';
  static const String biometricEnabled = 'biometric_enabled';
  static const String hmacSecret = 'hmac_signing_secret';
}

class AppRoles {
  static const String dealer = 'DEALER';
  static const String reseller = 'RESELLER';
}

class LockReasons {
  static const String nonPayment = 'NON_PAYMENT';
  static const String fraudulentActivity = 'FRAUDULENT_ACTIVITY';
  static const String theft = 'THEFT';
  static const String agreedByCustomer = 'AGREED_BY_CUSTOMER';
  static const String deviceCompromised = 'DEVICE_COMPROMISED';

  static const Map<String, String> labels = {
    nonPayment: 'Non-Payment',
    fraudulentActivity: 'Fraudulent Activity',
    theft: 'Theft Reported',
    agreedByCustomer: 'Agreed by Customer',
    deviceCompromised: 'Device Compromised',
  };

  static const Map<String, String> descriptions = {
    nonPayment: 'Customer has failed to make EMI payments',
    fraudulentActivity: 'Suspicious or fraudulent activity detected',
    theft: 'Device reported stolen',
    agreedByCustomer: 'Customer agreed to lock (voluntary)',
    deviceCompromised: 'Device security compromised',
  };
}

class DeviceStatus {
  static const String active = 'ACTIVE';
  static const String locked = 'LOCKED';
  static const String gracePeriod = 'GRACE_PERIOD';
  static const String decoupling = 'DECOUPLING';
  static const String decoupled = 'DECOUPLED';
  static const String blacklisted = 'BLACKLISTED';
}

class EMIStatus {
  static const String pending = 'PENDING';
  static const String paid = 'PAID';
  static const String overdue = 'OVERDUE';
  static const String defaultStatus = 'DEFAULT';
}

class DecouplingState {
  static const String emiActive = 'EMI_ACTIVE';
  static const String finalPaymentReceived = 'FINAL_PAYMENT_RECEIVED';
  static const String dealerNotified = 'DEALER_NOTIFIED';
  static const String pendingAdminDecouple = 'PENDING_ADMIN_DECOUPLE';
  static const String deviceDecoupled = 'DEVICE_DECOUPLED';
}