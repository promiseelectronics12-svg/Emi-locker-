import 'package:equatable/equatable.dart';
import 'device.dart';

class Dealer extends Equatable {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String shopName;
  final String tradeLicense;
  final String address;
  final String resellerId;
  final int totalDevices;
  final int activeDevices;
  final int lockedDevices;
  final DateTime createdAt;

  const Dealer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.shopName,
    required this.tradeLicense,
    required this.address,
    required this.resellerId,
    required this.totalDevices,
    required this.activeDevices,
    required this.lockedDevices,
    required this.createdAt,
  });

  factory Dealer.fromJson(Map<String, dynamic> json) {
    return Dealer(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      shopName: json['shop_name'] as String,
      tradeLicense: json['trade_license'] as String,
      address: json['address'] as String,
      resellerId: json['reseller_id'] as String,
      totalDevices: json['total_devices'] as int? ?? 0,
      activeDevices: json['active_devices'] as int? ?? 0,
      lockedDevices: json['locked_devices'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'shop_name': shopName,
      'trade_license': tradeLicense,
      'address': address,
      'reseller_id': resellerId,
      'total_devices': totalDevices,
      'active_devices': activeDevices,
      'locked_devices': lockedDevices,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        phone,
        shopName,
        tradeLicense,
        address,
        resellerId,
        totalDevices,
        activeDevices,
        lockedDevices,
        createdAt,
      ];
}