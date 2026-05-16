import 'package:flutter/material.dart';

import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_tokens.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.child,
    this.title = 'EVIK',
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
              Color(0xFFF7F7F7),
              EvikColors.darkBackground,
              Color(0xFFF0F0F0),
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
