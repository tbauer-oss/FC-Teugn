import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user.dart';
import 'auth_controller.dart';

class PendingPage extends ConsumerWidget {
  const PendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final title = switch (user?.status) {
      AccountStatus.rejected => 'Registrierung nicht freigegeben',
      AccountStatus.blocked => 'Account blockiert',
      AccountStatus.archived => 'Account archiviert',
      _ => user?.registrationRequest?.reviewStatus ==
              RegistrationReviewStatus.needsInfo
          ? 'Rückfrage zur Registrierung'
          : 'Account wartet auf Freigabe',
    };
    final message = switch (user?.status) {
      AccountStatus.rejected =>
        'Der Verein hat die Registrierung abgelehnt. Bitte kontaktiere die Jugendleitung, falls du Rückfragen hast.',
      AccountStatus.blocked =>
        'Bitte kontaktiere einen Vereinsadministrator für weitere Informationen.',
      AccountStatus.archived =>
        'Dieser Zugang wurde archiviert. Bitte kontaktiere den Verein, wenn er wieder benötigt wird.',
      _ => user?.registrationRequest?.reviewStatus ==
              RegistrationReviewStatus.needsInfo
          ? user?.registrationRequest?.applicantMessage ??
              'Der Verein benötigt weitere Angaben von dir.'
          : 'Der Verein prüft Identität, Rolle, Mannschaft und gegebenenfalls die Kind-Zuordnung.',
    };

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.hourglass_top, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    child: const Text('Abmelden'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
