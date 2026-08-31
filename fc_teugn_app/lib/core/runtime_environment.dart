import 'package:flutter/material.dart';

enum AppRuntimeEnvironment { production, demo }

class RuntimeEnvironment {
  const RuntimeEnvironment._();

  static const _configured = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'production',
  );

  static const current = _configured == 'demo'
      ? AppRuntimeEnvironment.demo
      : AppRuntimeEnvironment.production;

  static const isDemo = current == AppRuntimeEnvironment.demo;
}

class DemoEnvironmentStrip extends StatelessWidget {
  const DemoEnvironmentStrip({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Testumgebung. Keine Produktivdaten.',
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 34),
          color: const Color(0xFFFFC107),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.science_outlined, size: 18, color: Color(0xFF171813)),
              SizedBox(width: 7),
              Flexible(
                child: Text(
                  'TESTUMGEBUNG · KEINE PRODUKTIVDATEN',
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF171813),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .35,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
