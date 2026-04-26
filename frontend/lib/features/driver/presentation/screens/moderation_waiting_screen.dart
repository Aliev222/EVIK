import 'package:flutter/material.dart';

import '../../../../core/theme/evik_colors.dart';

class ModerationWaitingScreen extends StatelessWidget {
  const ModerationWaitingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4EF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: EvikColors.textPrimaryDark,
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
                backgroundColor: const Color(0xFFE2DDD5),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(EvikColors.accent),
              ),
              const SizedBox(height: 18),
              const Text(
                'Шаг 3 из 3',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: EvikColors.textSecondaryDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Документы отправлены',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: EvikColors.textPrimaryDark,
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
                      color: EvikColors.accent,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Заявка принята на модерацию',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: EvikColors.textPrimaryDark,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Проверка обычно занимает от нескольких минут до рабочего дня. Как только документы будут одобрены, водительский интерфейс станет доступен.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: EvikColors.textSecondaryDark,
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
                    backgroundColor: EvikColors.accent,
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
