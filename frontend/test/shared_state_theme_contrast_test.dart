import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tow_truck_frontend/core/theme/app_theme.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/shared/widgets/empty_state.dart';
import 'package:tow_truck_frontend/shared/widgets/error_state.dart';

void main() {
  Widget driverHarness(Widget child) => MaterialApp(
        theme: AppTheme.driver(),
        home: Scaffold(
          backgroundColor: AvroDriverColors.background,
          body: child,
        ),
      );

  Widget clientHarness(Widget child) => MaterialApp(
        theme: AppTheme.client(),
        home: Scaffold(
          backgroundColor: AvroClientColors.background,
          body: child,
        ),
      );

  testWidgets('ErrorState uses light text in the driver dark theme',
      (tester) async {
    await tester.pumpWidget(driverHarness(
      ErrorState(message: 'Повторите позже', onRetry: () {}),
    ));

    final title = tester.widget<Text>(find.text('Не удалось загрузить данные'));
    final message = tester.widget<Text>(find.text('Повторите позже'));

    expect(title.style?.color, AvroDriverColors.textPrimary);
    expect(message.style?.color, AvroDriverColors.grayHint);
  });

  testWidgets('EmptyState uses light text in the driver dark theme',
      (tester) async {
    await tester.pumpWidget(driverHarness(
      const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Заказов пока нет',
        subtitle: 'Включите статус онлайн',
      ),
    ));

    final title = tester.widget<Text>(find.text('Заказов пока нет'));
    final subtitle = tester.widget<Text>(find.text('Включите статус онлайн'));

    expect(title.style?.color, AvroDriverColors.textPrimary);
    expect(subtitle.style?.color, AvroDriverColors.grayHint);
  });

  testWidgets('shared states preserve dark text in the client light theme',
      (tester) async {
    await tester.pumpWidget(clientHarness(
      ErrorState(message: 'Повторите позже', onRetry: () {}),
    ));

    final errorTitle =
        tester.widget<Text>(find.text('Не удалось загрузить данные'));
    final errorMessage = tester.widget<Text>(find.text('Повторите позже'));
    expect(errorTitle.style?.color, AvroClientColors.textPrimary);
    expect(errorMessage.style?.color, AvroClientColors.tabInactive);

    await tester.pumpWidget(clientHarness(
      const EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Заказов пока нет',
        subtitle: 'Включите статус онлайн',
      ),
    ));

    final emptyTitle = tester.widget<Text>(find.text('Заказов пока нет'));
    final emptySubtitle =
        tester.widget<Text>(find.text('Включите статус онлайн'));
    expect(emptyTitle.style?.color, AvroClientColors.textPrimary);
    expect(emptySubtitle.style?.color, AvroClientColors.tabInactive);
  });
}
