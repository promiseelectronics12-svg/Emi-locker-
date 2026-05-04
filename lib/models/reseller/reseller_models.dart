import 'package:json_annotation/json_annotation.dart';

part 'reseller_models.g.dart';

@JsonSerializable()
class Dealer {
  final String id;
  final String name;
  final String shopName;
  final String phone;
  final String status; // Active, Suspended, Pending
  final double activationRate;
  final double collectionRate;
  final int keysUsed;

  Dealer({
    required this.id,
    required this.name,
    required this.shopName,
    required this.phone,
    required this.status,
    required this.activationRate,
    required this.collectionRate,
    required this.keysUsed,
  });

  factory Dealer.fromJson(Map<<StringString, dynamic> json) => _$DealerFromJson(json);
  Map<<StringString, dynamic> toJson() => _$DealerToJson(this);
}

@JsonSerializable()
class KeyInventory {
  final int purchased;
  final int assigned;
  final int available;
  final int monthlyQuota;
  final int usedThisMonth;

  KeyInventory({
    required this.purchased,
    required this.assigned,
    required this.available,
    required this.monthlyQuota,
    required this.usedThisMonth,
  });

  factory KeyInventory.fromJson(Map<<StringString, dynamic> json) => _$KeyInventoryFromJson(json);
  Map<<StringString, dynamic> toJson() => _$KeyInventoryToJson(this);
}

@JsonSerializable()
class KeyRequest {
  final String id;
  final int quantity;
  final String justification;
  final String status; // Pending, Approved, Rejected
  final DateTime createdAt;

  KeyRequest({
    required this.id,
    required this.quantity,
    required this.justification,
    required this.status,
    required this.createdAt,
  });

  factory KeyRequest.fromJson(Map<<StringString, dynamic> json) => _$KeyRequestFromJson(json);
  Map<<StringString, dynamic> toJson() => _$KeyRequestToJson(this);
}
