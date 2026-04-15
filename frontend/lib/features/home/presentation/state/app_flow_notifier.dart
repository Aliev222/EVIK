import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserRole { client, driver }

enum AuthStep { role, phone, sms, success, app }

enum AppTab { home, history, profile }

enum ClientHomeStage {
  idle,
  addressSelection,
  orderParameters,
  orderReview,
  searching,
  noDrivers,
  driverFound,
  driverEnRoute,
  driverArrived,
  completed,
}

enum DriverHomeStage {
  offline,
  online,
  newOrder,
  accepted,
  enRoute,
  arrived,
  completed,
}

enum DocumentStatus { missing, pending, approved, rejected }

class AppFlowState {
  const AppFlowState({
    required this.authStep,
    this.role,
    this.phone = '',
    this.code = '',
    this.currentTab = AppTab.home,
    this.clientStage = ClientHomeStage.idle,
    this.driverStage = DriverHomeStage.offline,
    this.documents = const {
      'Паспорт': DocumentStatus.missing,
      'Водительское удостоверение': DocumentStatus.missing,
      'СТС автомобиля': DocumentStatus.missing,
      'Страховка': DocumentStatus.missing,
    },
    this.searchAttempt = 0,
  });

  final AuthStep authStep;
  final UserRole? role;
  final String phone;
  final String code;
  final AppTab currentTab;
  final ClientHomeStage clientStage;
  final DriverHomeStage driverStage;
  final Map<String, DocumentStatus> documents;
  final int searchAttempt;

  bool get isDriver => role == UserRole.driver;

  AppFlowState copyWith({
    AuthStep? authStep,
    UserRole? role,
    String? phone,
    String? code,
    AppTab? currentTab,
    ClientHomeStage? clientStage,
    DriverHomeStage? driverStage,
    Map<String, DocumentStatus>? documents,
    int? searchAttempt,
  }) {
    return AppFlowState(
      authStep: authStep ?? this.authStep,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      code: code ?? this.code,
      currentTab: currentTab ?? this.currentTab,
      clientStage: clientStage ?? this.clientStage,
      driverStage: driverStage ?? this.driverStage,
      documents: documents ?? this.documents,
      searchAttempt: searchAttempt ?? this.searchAttempt,
    );
  }
}

final appFlowProvider =
    StateNotifierProvider<AppFlowNotifier, AppFlowState>((ref) {
  return AppFlowNotifier();
});

class AppFlowNotifier extends StateNotifier<AppFlowState> {
  AppFlowNotifier() : super(const AppFlowState(authStep: AuthStep.role));

  Timer? _searchTimer;

  void selectRole(UserRole role) {
    state = state.copyWith(role: role);
  }

  void continueFromRole() {
    if (state.role == null) return;
    state = state.copyWith(authStep: AuthStep.phone);
  }

  void submitPhone(String phone) {
    state = state.copyWith(authStep: AuthStep.sms, phone: phone.trim());
  }

  void backToPhoneEntry() {
    state = state.copyWith(authStep: AuthStep.phone);
  }

  void submitSms(String code) {
    state = state.copyWith(authStep: AuthStep.success, code: code.trim());
  }

  void finishAuth() {
    state = state.copyWith(
      authStep: AuthStep.app,
      currentTab: AppTab.home,
      clientStage: ClientHomeStage.idle,
      driverStage: DriverHomeStage.offline,
    );
  }

  void setTab(AppTab tab) {
    state = state.copyWith(currentTab: tab);
  }

  void showAddressSelection() {
    state = state.copyWith(clientStage: ClientHomeStage.addressSelection);
  }

  void confirmAddress() {
    state = state.copyWith(clientStage: ClientHomeStage.orderParameters);
  }

  void startSearch() {
    _searchTimer?.cancel();
    final attempt = state.searchAttempt + 1;
    state = state.copyWith(
        clientStage: ClientHomeStage.searching, searchAttempt: attempt);

    _searchTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      if (attempt.isOdd) {
        state = state.copyWith(clientStage: ClientHomeStage.noDrivers);
      } else {
        state = state.copyWith(clientStage: ClientHomeStage.driverFound);
      }
    });
  }

  void retrySearch() {
    startSearch();
  }

  void setClientStage(ClientHomeStage stage) {
    _searchTimer?.cancel();
    state = state.copyWith(clientStage: stage);
  }

  void toggleDriverOnline(bool value) {
    state = state.copyWith(
      driverStage: value ? DriverHomeStage.online : DriverHomeStage.offline,
    );
  }

  void setDriverStage(DriverHomeStage stage) {
    state = state.copyWith(driverStage: stage);
  }

  void updateDocumentStatus(String document, DocumentStatus status) {
    final next = Map<String, DocumentStatus>.from(state.documents);
    next[document] = status;
    state = state.copyWith(documents: next);
  }

  void logout() {
    _searchTimer?.cancel();
    state = const AppFlowState(authStep: AuthStep.role);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
