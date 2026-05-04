part of 'reseller_bloc.dart';

class ResellerState extends Equatable {
  final bool isLoading;
  final String? error;
  final List<Dealer> dealers;
  final Dealer? selectedDealer;
  final List<ActivationKey> activationKeys;
  final List<ActivationKey> generatedKeys;
  final int totalDealers;
  final bool hasMoreDealers;
  final bool keySold;
  final bool dealerActivated;
  final ResellerAnalytics? resellerAnalytics;

  const ResellerState({
    this.isLoading = false,
    this.error,
    this.dealers = const [],
    this.selectedDealer,
    this.activationKeys = const [],
    this.generatedKeys = const [],
    this.totalDealers = 0,
    this.hasMoreDealers = false,
    this.keySold = false,
    this.dealerActivated = false,
    this.resellerAnalytics,
  });

  ResellerState copyWith({
    bool? isLoading,
    String? error,
    List<Dealer>? dealers,
    Dealer? selectedDealer,
    List<ActivationKey>? activationKeys,
    List<ActivationKey>? generatedKeys,
    int? totalDealers,
    bool? hasMoreDealers,
    bool? keySold,
    bool? dealerActivated,
    ResellerAnalytics? resellerAnalytics,
  }) {
    return ResellerState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      dealers: dealers ?? this.dealers,
      selectedDealer: selectedDealer ?? this.selectedDealer,
      activationKeys: activationKeys ?? this.activationKeys,
      generatedKeys: generatedKeys ?? this.generatedKeys,
      totalDealers: totalDealers ?? this.totalDealers,
      hasMoreDealers: hasMoreDealers ?? this.hasMoreDealers,
      keySold: keySold ?? this.keySold,
      dealerActivated: dealerActivated ?? this.dealerActivated,
      resellerAnalytics: resellerAnalytics ?? this.resellerAnalytics,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        error,
        dealers,
        selectedDealer,
        activationKeys,
        generatedKeys,
        totalDealers,
        hasMoreDealers,
        keySold,
        dealerActivated,
        resellerAnalytics,
      ];
}