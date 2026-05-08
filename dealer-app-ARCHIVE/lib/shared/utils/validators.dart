import 'package:intl/intl.dart';

class Validators {
  static final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  static final _phoneRegex = RegExp(r'^01[3-9]\d{8}$');
  static final _nidRegex = RegExp(r'^\d{10,17}$');
  static final _passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d@$!%*#?&]{8,}$');
  static final _tradeLicenseRegex = RegExp(r'^[A-Z0-9\-]{5,30}$');
  static final _imeiRegex = RegExp(r'^\d{15}$');

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (!_emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  static String? validateStrongPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!_passwordRegex.hasMatch(value)) {
      return 'Password must contain letters and numbers';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!_phoneRegex.hasMatch(cleaned)) {
      return 'Enter a valid BD phone number (01XXXXXXXXX)';
    }
    return null;
  }

  static String? validateNID(String? value) {
    if (value == null || value.isEmpty) {
      return 'NID number is required';
    }
    if (!_nidRegex.hasMatch(value)) {
      return 'Enter a valid NID number (10-17 digits)';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Name is required';
    }
    if (value.length < 2) {
      return 'Name must be at least 2 characters';
    }
    if (value.length > 100) {
      return 'Name must be less than 100 characters';
    }
    return null;
  }

  static String? validateShopName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Shop name is required';
    }
    if (value.length < 2) {
      return 'Shop name must be at least 2 characters';
    }
    if (value.length > 200) {
      return 'Shop name must be less than 200 characters';
    }
    return null;
  }

  static String? validateTradeLicense(String? value) {
    if (value == null || value.isEmpty) {
      return 'Trade license is required';
    }
    if (!_tradeLicenseRegex.hasMatch(value.toUpperCase())) {
      return 'Enter a valid trade license number';
    }
    return null;
  }

  static String? validateAddress(String? value) {
    if (value == null || value.isEmpty) {
      return 'Address is required';
    }
    if (value.length < 5) {
      return 'Enter a complete address';
    }
    return null;
  }

  static String? validateResellerCode(String? value) {
    if (value == null || value.isEmpty) {
      return 'Reseller code is required';
    }
    if (value.length < 4) {
      return 'Enter a valid reseller code';
    }
    return null;
  }

  static String? validateIMEI(String? value) {
    if (value == null || value.isEmpty) {
      return 'IMEI is required';
    }
    final cleaned = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!_imeiRegex.hasMatch(cleaned)) {
      return 'Enter a valid 15-digit IMEI';
    }
    return null;
  }

  static String? validateLockNote(String? value) {
    if (value != null && value.length > 200) {
      return 'Note must be less than 200 characters';
    }
    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? validateAmount(String? value, {double? min, double? max}) {
    if (value == null || value.isEmpty) {
      return 'Amount is required';
    }
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Enter a valid amount';
    }
    if (min != null && amount < min) {
      return 'Amount must be at least $min';
    }
    if (max != null && amount > max) {
      return 'Amount must be at most $max';
    }
    return null;
  }

  static String? validateDateOfBirth(String? value) {
    if (value == null || value.isEmpty) {
      return 'Date of birth is required';
    }
    try {
      final parts = value.split('/');
      if (parts.length != 3) {
        return 'Enter date in DD/MM/YYYY format';
      }
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final dob = DateTime(year, month, day);
      final now = DateTime.now();
      final age = now.year - dob.year;
      if (age < 18) {
        return 'Must be at least 18 years old';
      }
      if (dob.isAfter(now)) {
        return 'Enter a valid date';
      }
    } catch (e) {
      return 'Enter a valid date (DD/MM/YYYY)';
    }
    return null;
  }

  static String formatDate(DateTime date, {String format = 'dd/MM/yyyy'}) {
    return DateFormat(format).format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  static String formatCurrency(double amount, {String symbol = '৳'}) {
    final formatter = NumberFormat('#,##0.00');
    return '$symbol${formatter.format(amount)}';
  }

  static String formatPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 7)}-${phone.substring(7)}';
    }
    return phone;
  }

  static String maskNID(String nid) {
    if (nid.length <= 4) return nid;
    return '${nid.substring(0, 4)}${'*' * (nid.length - 8)}${nid.substring(nid.length - 4)}';
  }

  static String maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }
}