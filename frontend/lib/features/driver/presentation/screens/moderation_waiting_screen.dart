import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroDriverColors;
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_verification_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/moderation_polling_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/screens/driver_main_screen.dart';

class ModerationWaitingScreen extends ConsumerStatefulWidget {
  const ModerationWaitingScreen({super.key});

  @override
  ConsumerState<ModerationWaitingScreen> createState() =>
      _ModerationWaitingScreenState();
}

class _ModerationWaitingScreenState
    extends ConsumerState<ModerationWaitingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final userId = ref.read(authProvider).user?.id;
      if (userId != null) {
        ref.invalidate(autoRefreshingVerificationStatusProvider(userId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).user?.id;

    if (userId == null) {
      return const _WaitingContent();
    }

    ref.watch(autoModerationPollingProvider);

    final verificationStatusAsync =
        ref.watch(autoRefreshingVerificationStatusProvider(userId));

    verificationStatusAsync.whenData((status) {
      if (status.status == 'approved' && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DriverMainScreen()),
            (route) => route.isFirst,
          );
        });
      }
    });

    return const _WaitingContent();
  }
}

class _WaitingContent extends StatelessWidget {
  const _WaitingContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AvroDriverColors.documentBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AvroDriverColors.darkBlue,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: 1,
                minHeight: 8,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: AvroDriverColors.documentCard,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AvroDriverColors.accent),
              ),
              const SizedBox(height: 18),
              const Text(
                'Шаг 3 из 3',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AvroDriverColors.border,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Документы отправлены',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AvroDriverColors.darkBlue,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.fact_check_rounded,
                      size: 56,
                      color: AvroDriverColors.accent,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Заявка принята на модерацию',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AvroDriverColors.darkBlue,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Проверка обычно занимает от нескольких минут до рабочего дня. Как только документы будут одобрены, водительский интерфейс станет доступен.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: AvroDriverColors.border,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil(
                    (route) => route.isFirst,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvroDriverColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Понятно',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
