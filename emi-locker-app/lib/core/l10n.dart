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

  // ── Home screen ──────────────────────────────────────────────────────────────
  String get homeTitle => isBangla ? 'ইএমআই স্ট্যাটাস' : 'EMI Status';
  String get homeNotAvailable =>
      isBangla ? 'তথ্য পাওয়া যায়নি।' : 'No data available.';
  String get homeSignOut => isBangla ? 'সাইন আউট' : 'Sign Out';

  // ── Language toggle ──────────────────────────────────────────────────────────
  String get langToggleLabel =>
      isBangla ? 'Switch to English' : 'বাংলায় পড়ুন';

  static AppStrings of(AppLanguage lang) => AppStrings._(lang);
}
