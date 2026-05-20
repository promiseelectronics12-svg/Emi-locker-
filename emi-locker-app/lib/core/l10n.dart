import 'package:flutter/material.dart';

enum AppLanguage { english, bangla }

extension AppLanguageLocale on AppLanguage {
  Locale get locale => this == AppLanguage.bangla ? const Locale('bn') : const Locale('en');
  String get label => this == AppLanguage.bangla ? 'বাংলা' : 'English';
}

class AppStrings {
  const AppStrings._(this.lang);

  final AppLanguage lang;

  bool get isBangla => lang == AppLanguage.bangla;

  // ── App ─────────────────────────────────────────────────────────────────────
  String get appName => isBangla ? 'ইএমআই লকার' : 'EMI Locker';

  // ── Disclosure screen ────────────────────────────────────────────────────────
  String get disclosureTitle =>
      isBangla ? 'গ্রাহক সুরক্ষা স্তর' : 'Customer Protection Layer';

  String get disclosureIntro =>
      isBangla
          ? 'ইএমআই লকার আপনার ডিলারকে ডিভাইসের কিস্তি পরিচালনায় সহায়তা করে। আপনার সম্মতিতে:'
          : 'EMI Locker helps your dealer manage your device installment plan. With your agreement:';

  List<String> get disclosureBullets => isBangla
      ? [
          'কিস্তি বকেয়া থাকলে ফোন দূর থেকে লক হতে পারে।',
          'আপনার ডিভাইসের অবস্থান ডিলারের সাথে শেয়ার হতে পারে।',
          'সিম কার্ড পরিবর্তন ডিলারকে জানানো হবে।',
          'এই অ্যাপ আনইনস্টল করলে ডিভাইস লক হতে পারে।',
          'পেমেন্ট করলে ফোন আনলক করা যাবে।',
          'সহায়তার জন্য আপনার ডিলারের সাথে যোগাযোগ করুন।',
        ]
      : [
          'Your phone may be remotely locked if payments are overdue.',
          'Your device location may be shared with your dealer.',
          'SIM card changes are reported to your dealer.',
          'Uninstalling this app may trigger a device lock.',
          'You can unlock your phone by making a payment.',
          'Contact your dealer for support or more information.',
        ];

  String get disclosureAgree => isBangla ? 'আমি সম্মত' : 'I Agree';
  String get disclosureDecline => isBangla ? 'প্রত্যাখ্যান করুন' : 'Decline';
  String get disclosureDeclineWarning =>
      isBangla
          ? 'সম্মতি না দিলে এই অ্যাপ ব্যবহার করা যাবে না।'
          : 'You cannot use this app without agreeing to these terms.';

  // ── Login screen ─────────────────────────────────────────────────────────────
  String get loginTitle => isBangla ? 'লগ ইন করুন' : 'Sign In';
  String get loginSubtitle =>
      isBangla ? 'Google দিয়ে সাইন ইন করুন' : 'Sign in with Google';
  String get loginButton => isBangla ? 'Google দিয়ে চালিয়ে যান' : 'Continue with Google';
  String get loginLoading => isBangla ? 'লগ ইন হচ্ছে…' : 'Signing in…';
  String get loginError => isBangla ? 'সাইন ইন ব্যর্থ হয়েছে।' : 'Sign-in failed.';

  // ── IMEI dialog ───────────────────────────────────────────────────────────────
  String get imeiDialogTitle => isBangla ? 'ডিভাইস IMEI দিন' : 'Enter Device IMEI';

  String get imeiDialogInstruction =>
      isBangla
          ? 'প্রথমবার সাইন ইনে আপনার ডিভাইস নিশ্চিত করতে IMEI দরকার।\n\n*#06# ডায়াল করে আপনার IMEI খুঁজুন।'
          : 'First sign-in requires your device IMEI to verify enrollment.\n\nDial *#06# to find your IMEI.';

  String get imeiDialogHint => isBangla ? '১৫ সংখ্যার IMEI' : '15-digit IMEI';
  String get imeiDialogCancel => isBangla ? 'বাতিল' : 'Cancel';
  String get imeiDialogContinue => isBangla ? 'চালিয়ে যান' : 'Continue';

  String get imeiInvalidError =>
      isBangla
          ? 'IMEI অবশ্যই ১৫টি সংখ্যা হতে হবে।'
          : 'IMEI must be exactly 15 digits.';

  // ── Backend error codes → user-friendly messages ──────────────────────────────
  String errorForCode(String code) {
    switch (code) {
      case 'DEVICE_NOT_ENROLLED':
        return isBangla
            ? 'ডিভাইস নিবন্ধিত নয়। আপনার ডিলারের সাথে যোগাযোগ করুন।'
            : 'Device not enrolled. Contact your dealer.';
      case 'ACCOUNT_NOT_FOUND':
        return isBangla
            ? 'অ্যাকাউন্ট পাওয়া যায়নি। প্রথমবার সাইন ইনে IMEI দিন।'
            : 'Account not found. Provide your IMEI on first sign-in.';
      case 'INVALID_GOOGLE_TOKEN':
        return isBangla
            ? 'Google সাইন ইন ব্যর্থ। আবার চেষ্টা করুন।'
            : 'Google sign-in failed. Please try again.';
      case 'GOOGLE_AUTH_NOT_CONFIGURED':
        return isBangla
            ? 'Google সাইন ইন এখন উপলব্ধ নয়।'
            : 'Google sign-in is not available right now.';
      case 'TOKEN_EXPIRED':
      case 'ACCESS_TOKEN_REQUIRED':
      case 'INVALID_SESSION':
        return isBangla
            ? 'সেশন মেয়াদ শেষ। আবার সাইন ইন করুন।'
            : 'Session expired. Please sign in again.';
      case 'NO_DEVICE':
        return isBangla
            ? 'কোনো ডিভাইস নিবন্ধিত নেই। আপনার ডিলারের সাথে যোগাযোগ করুন।'
            : 'No device registered. Contact your dealer.';
      case 'NO_SCHEDULE':
        return isBangla
            ? 'কোনো কিস্তির সময়সূচি পাওয়া যায়নি।'
            : 'No EMI schedule found.';
      case 'NETWORK_ERROR':
        return isBangla
            ? 'নেটওয়ার্ক সমস্যা। আপনার সংযোগ পরীক্ষা করুন।'
            : 'Network error. Check your connection.';
      default:
        return isBangla ? 'একটি সমস্যা হয়েছে। আবার চেষ্টা করুন।' : 'Something went wrong. Please try again.';
    }
  }

  // ── Home screen ──────────────────────────────────────────────────────────────
  String get homeTitle => isBangla ? 'ইএমআই স্ট্যাটাস' : 'EMI Status';
  String get homeNotAvailable =>
      isBangla ? 'তথ্য পাওয়া যায়নি।' : 'No data available.';
  String get homeSignOut => isBangla ? 'সাইন আউট' : 'Sign Out';
  String get homeSessionExpired =>
      isBangla ? 'সেশন মেয়াদ শেষ হয়েছে।' : 'Your session has expired.';

  // ── Language toggle ──────────────────────────────────────────────────────────
  String get langToggleLabel =>
      isBangla ? 'Switch to English' : 'বাংলায় পড়ুন';

  static AppStrings of(AppLanguage lang) => AppStrings._(lang);
}
