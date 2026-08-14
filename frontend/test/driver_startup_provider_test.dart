import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_startup_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_tax_profile_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_verification_provider.dart';

DriverVerificationStatus statusOf(
  String status, {
  String adminComments = '',
}) {
  return DriverVerificationStatus(
    driverId: 'driver-1',
    status: status,
    documentsUploaded: const <String, DocumentInfo>{},
    adminComments: adminComments,
  );
}

void main() {
  group('driverStartupProvider rejected vs blocked routing', () {
    test('rejected leads to documents resubmission with reason', () {
      final info = determineStartupState(
        statusOf('rejected', adminComments: 'Паспорт нечитаемый'),
        null,
      );

      expect(info.state, DriverStartupState.needsDocuments);
      expect(info.nextRoute, '/driver/documents');
      expect(info.message, contains('Заявка отклонена'));
      expect(info.message, contains('Паспорт нечитаемый'));
      expect(info.message, contains('отправьте повторно'));
    });

    test('rejected without comment falls back to generic resubmit message', () {
      final info = determineStartupState(statusOf('rejected'), null);

      expect(info.state, DriverStartupState.needsDocuments);
      expect(info.nextRoute, '/driver/documents');
      expect(
        info.message,
        contains('Исправьте документы и отправьте повторно'),
      );
    });

    test('blocked routes to support only, never to resubmission', () {
      final info = determineStartupState(statusOf('blocked'), null);

      expect(info.state, DriverStartupState.blocked);
      expect(info.nextRoute, '/driver/blocked');
      expect(info.message, contains('заблокирован'));
      expect(info.message, isNot(contains('отправьте повторно')));
    });

    test('changes_requested still leads to documents resubmission', () {
      final info = determineStartupState(
        statusOf('changes_requested', adminComments: 'Нужен чёткий снимок СТС'),
        null,
      );

      expect(info.state, DriverStartupState.needsDocuments);
      expect(info.nextRoute, '/driver/documents');
      expect(info.message, contains('Нужен чёткий снимок СТС'));
    });

    test('pending stays under review', () {
      final info = determineStartupState(statusOf('pending'), null);

      expect(info.state, DriverStartupState.documentsUnderReview);
      expect(info.nextRoute, '/driver/moderation');
    });

    test('approved with missing tax profile keeps needsTaxProfile', () {
      final info = determineStartupState(statusOf('approved'), null);

      expect(info.state, DriverStartupState.needsTaxProfile);
      expect(info.nextRoute, '/driver/tax-profile');
    });

    test('approved + verified tax profile allows work', () {
      const profile = DriverTaxProfile(
        driverId: 'driver-1',
        inn: '123456789012',
        taxpayerType: 'npd',
        verificationStatus: 'verified',
      );
      final info = determineStartupState(statusOf('approved'), profile);

      expect(info.state, DriverStartupState.canWork);
      expect(info.nextRoute, '/driver/home');
    });
  });
}