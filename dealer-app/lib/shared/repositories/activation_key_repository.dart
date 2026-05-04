import '../../shared/models/activation_key_model.dart';

class ActivationKeyRepository {
  Future<List<ActivationKey>> getKeys(String dealerId) async {
    return [];
  }

  Future<ActivationKey?> getKey(String keyId) async {
    return null;
  }

  Future<List<ActivationKey>> getAvailableKeys(String resellerId) async {
    return [];
  }

  Future<ActivationKey> reserveKey(String resellerId, String dealerId) async {
    return ActivationKey(
      id: '',
      resellerId: resellerId,
      dealerId: dealerId,
      keyCode: '',
      status: 'RESERVED',
      createdAt: DateTime.now(),
    );
  }

  Future<void> releaseKey(String keyId) async {
  }

  Future<ActivationKey> purchaseKey(String dealerId, String resellerCode) async {
    return ActivationKey(
      id: '',
      resellerId: '',
      dealerId: dealerId,
      keyCode: '',
      status: 'AVAILABLE',
      createdAt: DateTime.now(),
    );
  }
}