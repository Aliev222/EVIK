import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/features/driver/data/repository/driver_wallet_repository.dart';
import 'package:tow_truck_frontend/features/driver/domain/entities/driver_wallet.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_wallet_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_debt_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_earnings_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_order_receipt_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/widgets/driver_debt_banner.dart';
import 'package:tow_truck_frontend/features/order/data/repository_impl/http_order_repository.dart';

DriverWallet _wallet({required int debt, required int maxDebt}) {
  return DriverWallet(
    availableBalance: 0,
    pendingBalance: 0,
    debtBalance: debt,
    maxCashDebtKopecks: maxDebt,
    currency: 'RUB',
    recentTransactions: const [],
    recentPayouts: const [],
  );
}

DriverDebtBreakdown _breakdown({bool withRepayment = true}) {
  return DriverDebtBreakdown(
    accrued: 120000,
    repaid: withRepayment ? 50000 : 0,
    transactions: [
      DriverDebtTransaction(
        id: 'debt-1',
        type: 'cash_commission_debt',
        direction: 'credit',
        amount: 120000,
        currency: 'RUB',
        status: 'succeeded',
        description: 'Tow Truck commission debt for cash order',
        orderId: 'order-cash-1',
        orderAmount: 800000,
        createdAt: DateTime(2026, 8, 14, 18, 30),
      ),
      if (withRepayment)
        DriverDebtTransaction(
          id: 'repay-1',
          type: 'debt_repayment',
          direction: 'debit',
          amount: 50000,
          currency: 'RUB',
          status: 'succeeded',
          description: 'Debt repayment from card order',
          orderId: 'order-card-1',
          orderAmount: 700000,
          createdAt: DateTime(2026, 8, 15, 10, 0),
        ),
    ],
  );
}

OrderReceipt _cashReceipt() {
  return OrderReceipt(
    orderId: 'order-cash-1',
    priceTotal: 800000,
    currency: 'RUB',
    paymentMethod: 'cash',
    paymentStatus: 'succeeded',
    commissionAmount: 120000,
    driverAmount: 680000,
    createdAt: DateTime(2026, 8, 14, 18, 0),
    completedAt: DateTime(2026, 8, 14, 18, 30),
    pickupAddress: 'ул. Тверская, 1',
    dropoffAddress: 'ул. Арбат, 10',
  );
}

void main() {
  testWidgets('DriverDebtBanner shows block text when debt above threshold',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverDebtBanner(
            wallet: _wallet(debt: 150000, maxDebt: 100000),
          ),
        ),
      ),
    );

    expect(find.byType(DriverDebtBanner), findsOneWidget);
    expect(find.text('Погасите долг 1 500 ₽'), findsOneWidget);
    expect(find.text('Погасите долг, чтобы принимать заказы'), findsOneWidget);
  });

  testWidgets('DriverDebtBanner is informational when debt below threshold',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DriverDebtBanner(
            wallet: _wallet(debt: 50000, maxDebt: 100000),
          ),
        ),
      ),
    );

    expect(find.byType(DriverDebtBanner), findsOneWidget);
    expect(find.text('Долг за наличные: 500 ₽'), findsOneWidget);
    expect(find.text('Погасите долг, чтобы принимать заказы'), findsNothing);
  });

  testWidgets('DriverDebtScreen shows debt, SBP placeholder and card note',
      (tester) async {
    final wallet = _wallet(debt: 150000, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider
              .overrideWithValue(_FakeWalletRepository(wallet: wallet)),
        ],
        child: const MaterialApp(home: DriverDebtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Погасите долг, чтобы принимать заказы'), findsOneWidget);
    expect(find.text('1 500 ₽'), findsWidgets);
    expect(find.text('Оплата по СБП'), findsOneWidget);
    expect(find.textContaining('Оплата по СБП скоро'), findsOneWidget);
    expect(find.text('Карточные заказы погашают долг автоматически'),
        findsOneWidget);
  });

  testWidgets(
      'DriverDebtScreen shows debt sources list and repayments (сумма заказа и комиссия)',
      (tester) async {
    final wallet = _wallet(debt: 70000, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider.overrideWithValue(
            _FakeWalletRepository(
              wallet: wallet,
              breakdown: _breakdown(),
              receipt: _cashReceipt(),
            ),
          ),
        ],
        child: const MaterialApp(home: DriverDebtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Sources section header and totals.
    expect(find.text('Из чего сложился долг'), findsOneWidget);
    expect(find.text('Комиссия с наличных заказов'), findsOneWidget);
    // Accrual row: order total displayed under the commission.
    expect(find.text('Наличный заказ · 14.08.2026'), findsOneWidget);
    expect(find.text('1 200 ₽'), findsWidgets);
    expect(find.text('заказ 8 000 ₽'), findsOneWidget);
    // Repayments section.
    expect(find.text('Погашения'), findsOneWidget);
    expect(find.text('Погашение · 15.08.2026'), findsOneWidget);
    expect(find.text('-500 ₽'), findsOneWidget);
  });

  testWidgets('DriverDebtScreen hides sources list when there is no history',
      (tester) async {
    final wallet = _wallet(debt: 0, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider.overrideWithValue(
            _FakeWalletRepository(
              wallet: wallet,
              breakdown: const DriverDebtBreakdown(
                transactions: [],
                accrued: 0,
                repaid: 0,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: DriverDebtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Из чего сложился долг'), findsOneWidget);
    expect(find.text('Комиссия с наличных заказов'), findsOneWidget);
    expect(find.text('Наличных заказов с долгом пока нет.'), findsOneWidget);
  });

  testWidgets('Tapping a debt source row opens the cash order receipt',
      (tester) async {
    final wallet = _wallet(debt: 70000, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider.overrideWithValue(
            _FakeWalletRepository(
              wallet: wallet,
              breakdown: _breakdown(),
              receipt: _cashReceipt(),
            ),
          ),
        ],
        child: const MaterialApp(home: DriverDebtScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Наличный заказ · 14.08.2026'));
    await tester.pumpAndSettle();

    expect(find.byType(DriverOrderReceiptScreen), findsOneWidget);
    expect(find.text('Чек заказа'), findsOneWidget);
    // Cash receipt content: способ, сумма, комиссия, адреса.
    expect(find.text('Наличный заказ'), findsOneWidget);
    expect(find.text('8 000 ₽'), findsOneWidget);
    expect(find.text('Наличные'), findsOneWidget);
    expect(find.text('1 200 ₽'), findsWidgets);
    expect(find.text('ул. Тверская, 1'), findsOneWidget);
    expect(find.text('ул. Арбат, 10'), findsOneWidget);
  });

  testWidgets('DriverEarningsScreen shows debt banner when debt above threshold',
      (tester) async {
    final wallet = _wallet(debt: 150000, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider
              .overrideWithValue(_FakeWalletRepository(wallet: wallet)),
        ],
        child: const MaterialApp(home: DriverEarningsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DriverDebtBanner), findsOneWidget);
    expect(find.text('Погасите долг 1 500 ₽'), findsOneWidget);
  });

  testWidgets('DriverEarningsScreen hides debt banner when no debt',
      (tester) async {
    final wallet = _wallet(debt: 0, maxDebt: 100000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          driverWalletRepositoryProvider
              .overrideWithValue(_FakeWalletRepository(wallet: wallet)),
        ],
        child: const MaterialApp(home: DriverEarningsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DriverDebtBanner), findsNothing);
  });
}

class _FakeWalletRepository implements DriverWalletRepository {
  const _FakeWalletRepository({
    required this.wallet,
    this.breakdown = const DriverDebtBreakdown(
      transactions: [],
      accrued: 0,
      repaid: 0,
    ),
    this.receipt,
  });

  final DriverWallet wallet;
  final DriverDebtBreakdown breakdown;
  final OrderReceipt? receipt;

  @override
  Future<DriverWallet> getWallet() async => wallet;

  @override
  Future<List<WalletTransaction>> getTransactions() async => const [];

  @override
  Future<DriverDebtBreakdown> getDebtBreakdown() async => breakdown;

  @override
  Future<OrderReceipt> getOrderReceipt(String orderId) async {
    final r = receipt;
    if (r == null) {
      throw Exception('no receipt configured');
    }
    return r;
  }

  @override
  Future<List<DriverPayout>> getPayouts() async => const [];

  @override
  Future<List<DriverPayoutMethod>> getPayoutMethods() async => const [];

  @override
  Future<void> addPayoutMethod({
    required String type,
    required String providerRecipientId,
    required String maskedValue,
    required bool isDefault,
  }) async {}

  @override
  Future<void> requestPayout(int amount) async {}

  @override
  Future<DriverSubscriptionStatus> getSubscriptionStatus() async =>
      const DriverSubscriptionStatus(status: 'none');

  @override
  Future<String?> createSubscriptionPayment(String planId) async => null;
}