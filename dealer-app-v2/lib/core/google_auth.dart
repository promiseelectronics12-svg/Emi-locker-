import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

class DealerGoogleAuth {
  DealerGoogleAuth._();

  static GoogleSignIn _signIn() {
    final serverClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim();
    return GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: serverClientId == null || serverClientId.isEmpty
          ? null
          : serverClientId,
    );
  }

  static Future<DealerGoogleIdentity?> signInForIdToken() async {
    final account = await _signIn().signIn();
    if (account == null) return null;

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError(
        'Google login needs GOOGLE_WEB_CLIENT_ID in the Dealer app .env.',
      );
    }

    return DealerGoogleIdentity(
      idToken: idToken,
      email: account.email,
      displayName: account.displayName,
    );
  }
}

class DealerGoogleIdentity {
  const DealerGoogleIdentity({
    required this.idToken,
    required this.email,
    this.displayName,
  });

  final String idToken;
  final String email;
  final String? displayName;
}
