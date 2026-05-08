import 'dart:io';

import 'package:dealer_app/app/emi_locker_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enrollment handoff does not consume keys from the dealer app', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();

    expect(source, isNot(contains("/api/v1/keys/consume")));
    expect(source, contains('/api/v1/keys/my-keys'));
    expect(source, contains('/api/v1/device-activation/verify'));
  });

  test('settings is not a navigation destination', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();

    expect(
      source,
      isNot(contains("NavDestinationSpec(\n              'Settings'")),
    );
    expect(source, contains('openSettings'));
  });

  test('workspace uses floating profile controls and pull refresh only', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();

    expect(source, contains('class _FloatingWorkspaceControls'));
    expect(source, contains('class _AlertBell'));
    expect(source, contains('/api/v1/alerts'));
    expect(source, isNot(contains('class _WorkspaceProfileStrip')));
    expect(source, isNot(contains('class _WorkspaceTopHeader')));
    expect(source, isNot(contains('class _PageHeader')));
    expect(source, isNot(contains('Icons.refresh')));
    expect(source, isNot(contains("tooltip: 'Refresh'")));
  });

  test('role accents are distinct for dealer and reseller', () {
    final dealer = AppUser(
      id: 'dealer',
      email: 'dealer@example.com',
      name: 'Dealer',
      role: 'dealer',
      phone: '',
      shopName: '',
    );
    final reseller = AppUser(
      id: 'reseller',
      email: 'reseller@example.com',
      name: 'Reseller',
      role: 'reseller',
      phone: '',
      shopName: '',
    );

    expect(roleAccent(dealer), isNot(roleAccent(reseller)));
    expect(roleAccent(dealer), const Color(0xFF00A86B));
    expect(roleAccent(reseller), const Color(0xFF635BFF));
  });

  test('key status labels hide backend jargon', () {
    expect(dealerKeyStatusLabel('assigned'), 'Ready for activation');
    expect(dealerKeyStatusLabel('activated'), 'Used by device');
    expect(dealerKeyStatusLabel('revoked'), 'Cancelled');
    expect(resellerKeyStatusLabel('available'), 'In reseller stock');
    expect(resellerKeyStatusLabel('assigned'), 'Sent to dealer');
    expect(resellerKeyStatusLabel('activated'), 'Used by device');
  });

  test('enrollment uses activation-code handoff labels', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();

    expect(source, contains('Choose ready activation code'));
    expect(source, contains('Show this code to the customer phone'));
    expect(source, contains('Phone verifies'));
    expect(source, contains('Device appears'));
    expect(source, isNot(contains('Share with phone')));
    expect(source, isNot(contains('Select activation key')));
    expect(source, isNot(contains('Still assigned')));
  });

  test('settings hides raw API URL and keeps connection human-readable', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();
    final settingsSource = source.substring(
      source.indexOf('class SettingsPage'),
      source.indexOf('class LockDialog'),
    );

    expect(settingsSource, contains('Connection OK'));
    expect(settingsSource, contains('Secure dealer services are reachable.'));
    expect(settingsSource, contains('class _SettingsProfileCard'));
    expect(settingsSource, isNot(contains('widget.api.dio.options.baseUrl')));
  });

  test('reseller send-keys flow stays visible even without stock', () {
    final source = File('lib/app/emi_locker_app.dart').readAsStringSync();

    expect(source, contains('Dealer key handoff'));
    expect(source, contains('No ready codes in reseller stock'));
    expect(source, contains('All approved stock has already been sent'));
    expect(source, contains('send_keys_dealer_dropdown'));
    expect(source, contains('Send keys to dealer'));
  });

  testWidgets('login screen renders on desktop and mobile widths', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: '');
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(api: ApiClient(), onAuthenticated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMI Locker'), findsWidgets);
    expect(find.text('Sign in securely'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(api: ApiClient(), onAuthenticated: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dealer and reseller sign in'), findsOneWidget);
    expect(find.text('Sign in securely'), findsOneWidget);
  });

  testWidgets('logout requires explicit confirmation', (tester) async {
    bool? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                confirmed = await confirmLogout(context);
              },
              child: const Text('Open confirm'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out of EMI Locker?'), findsOneWidget);
    expect(
      find.text(
        'You will be logged out of this dealer workspace and will need to sign in again to continue.',
      ),
      findsOneWidget,
    );
    expect(confirmed, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
