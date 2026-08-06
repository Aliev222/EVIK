import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart' show AvroClientColors;
import 'package:tow_truck_frontend/core/theme/evik_tokens.dart' show EvikSpacing, EvikDurations, EvikCurves;

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.title = 'Авро',
  });

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AvroClientColors.gradientLight1,
              AvroClientColors.background,
              AvroClientColors.gradientLight2,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EvikSpacing.screenPadding,
            child: AnimatedSwitcher(
              duration: EvikDurations.medium,
              switchInCurve: EvikCurves.enter,
              switchOutCurve: EvikCurves.exit,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
