import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/constants/app_constants.dart';
import 'package:tow_truck_frontend/features/driver/data/repository/driver_verification_repository.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_moderation_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_documents_screen.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_moderation_screen.dart';

const _resubmitLabel = 'Исправить и переотправить документы';
const _supportLabel = 'Обратиться в поддержку';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConstants.supportEmail', () {
    test('uses Авро contact, not old evik.app', () {
      expect(AppConstants.supportEmail, isNotEmpty);
      expect(AppConstants.supportEmail, isNot(contains('evik.app')));
      expect(AppConstants.supportEmail, contains('avro.app'));
    });
  });

  group('DriverVerificationDocument._parseStatus', () {
    DriverVerificationDocument docWithStatus(String status) {
      return DriverVerificationDocument.fromMap({
        'userId': 'u1',
        'status': status,
        'documentUrls': <String, dynamic>{'passport': 'http://x/p.jpg'},
        'submittedAt': DateTime(2026, 4, 24).millisecondsSinceEpoch,
      });
    }

    test('changes_requested maps to changesRequested', () {
      expect(
        docWithStatus('changes_requested').status,
        DriverModerationStatus.changesRequested,
      );
    });

    test('changes_requested exposes moderator comment as rejectionReason', () {
      final doc = DriverVerificationDocument.fromMap({
        'userId': 'u1',
        'status': 'changes_requested',
        'documentUrls': <String, dynamic>{},
        'submittedAt': 0,
        'reviewComment': 'Паспорт нечитаемый, пришлите новое фото.',
      });
      expect(doc.status, DriverModerationStatus.changesRequested);
      expect(doc.rejectionReason, 'Паспорт нечитаемый, пришлите новое фото.');
    });

    test('rejected maps to rejected', () {
      expect(
        docWithStatus('rejected').status,
        DriverModerationStatus.rejected,
      );
    });

    test('blocked maps to rejected', () {
      expect(
        docWithStatus('blocked').status,
        DriverModerationStatus.rejected,
      );
    });

    test('pending maps to pending', () {
      expect(docWithStatus('pending').status, DriverModerationStatus.pending);
    });

    test('not_submitted falls back to pending', () {
      expect(
        docWithStatus('not_submitted').status,
        DriverModerationStatus.pending,
      );
    });

    test('approved maps to approved', () {
      expect(
        docWithStatus('approved').status,
        DriverModerationStatus.approved,
      );
    });
  });

  group('DriverModerationScreen', () {
    DriverVerificationDocument doc({
      required DriverModerationStatus status,
      String? rejectionReason,
    }) {
      return DriverVerificationDocument(
        userId: 'driver-1',
        fullName: 'Иванов Иван',
        vehicleModel: 'Hyundai HD78',
        vehicleNumber: 'А111АА77',
        vehicleType: 'light',
        documentUrls: const <String, String>{},
        status: status,
        submittedAt: DateTime(2026, 4, 24),
        rejectionReason: rejectionReason,
      );
    }

    Widget wrap(DriverVerificationDocument document) {
      return ProviderScope(
        overrides: [
          driverVerificationRepositoryProvider.overrideWithValue(
            const _FakeVerificationRepository(),
          ),
        ],
        child: MaterialApp(home: DriverModerationScreen(document: document)),
      );
    }

    testWidgets('rejected shows resubmit and support buttons', (tester) async {
      await tester.pumpWidget(
        wrap(doc(
          status: DriverModerationStatus.rejected,
          rejectionReason: 'Фото паспорта слишком тёмное.',
        )),
      );

      expect(find.text('Проверка не пройдена'), findsOneWidget);
      expect(find.text('Фото паспорта слишком тёмное.'), findsOneWidget);
      expect(find.text(_resubmitLabel), findsOneWidget);
      expect(find.text(_supportLabel), findsOneWidget);
      expect(find.text('Документы на проверке'), findsNothing);
    });

    testWidgets('rejected without reason shows fallback text', (tester) async {
      await tester.pumpWidget(
        wrap(doc(status: DriverModerationStatus.rejected)),
      );

      expect(find.text('Проверка не пройдена'), findsOneWidget);
      expect(find.text(_resubmitLabel), findsOneWidget);
    });

    testWidgets('changesRequested shows distinct state with reason and resubmit',
        (tester) async {
      await tester.pumpWidget(
        wrap(doc(
          status: DriverModerationStatus.changesRequested,
          rejectionReason: 'Нужен чёткий снимок СТС.',
        )),
      );

      expect(find.text('Нужны изменения в документах'), findsOneWidget);
      expect(find.text('Нужен чёткий снимок СТС.'), findsOneWidget);
      expect(find.text(_resubmitLabel), findsOneWidget);
      expect(find.text(_supportLabel), findsOneWidget);
      expect(find.text('Документы на проверке'), findsNothing);
      expect(find.text('Проверка не пройдена'), findsNothing);
    });

    testWidgets('pending does not show resubmit button', (tester) async {
      await tester.pumpWidget(wrap(doc(status: DriverModerationStatus.pending)));

      expect(find.text('Документы на проверке'), findsOneWidget);
      expect(find.text(_resubmitLabel), findsNothing);
      expect(find.text(_supportLabel), findsNothing);
    });

    testWidgets('resubmit button opens documents upload flow',
        (tester) async {
      await tester.pumpWidget(
        wrap(doc(status: DriverModerationStatus.rejected)),
      );

      await tester.tap(find.text(_resubmitLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DriverDocumentsScreen), findsOneWidget);
    });
  });
}

class _FakeVerificationRepository implements DriverVerificationRepository {
  const _FakeVerificationRepository();

  @override
  Future<DriverVerificationResult> submitVerification({
    required DriverVerificationPayload payload,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(1.0, 'submitted');
    return DriverVerificationResult(
      documentUrls: const <String, String>{},
      submittedAt: DateTime(2026, 4, 24),
    );
  }
}