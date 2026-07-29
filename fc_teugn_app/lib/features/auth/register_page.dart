import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/app_theme.dart';
import '../../core/club_logo.dart';
import '../../core/models/user.dart';
import 'auth_controller.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _childName = TextEditingController();
  UserRole _role = UserRole.parent;
  String _relationship = 'GUARDIAN';
  final Set<String> _teamIds = {};
  bool _privacyAccepted = false;
  bool _termsAccepted = false;
  bool _pushOptIn = false;
  late Future<_RegistrationOptions> _options;

  @override
  void initState() {
    super.initState();
    _options = _loadOptions();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _childName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: FutureBuilder<_RegistrationOptions>(
                    future: _options,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const SizedBox(
                          height: 360,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return _LoadError(
                          onRetry: () =>
                              setState(() => _options = _loadOptions()),
                        );
                      }
                      return _form(
                        context,
                        snapshot.data!,
                        authState,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    _RegistrationOptions options,
    AuthState authState,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ClubLogo(size: 88),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mitgliedschaft beantragen',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      'Dein Zugang wird anschließend vom Verein geprüft.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _sectionTitle(context, 'Persönliche Angaben', 'Wer beantragt den Zugang?'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final fields = [
                TextFormField(
                  controller: _firstName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Vorname *'),
                  validator: _required,
                ),
                TextFormField(
                  controller: _lastName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nachname *'),
                  validator: _required,
                ),
              ];
              return wide
                  ? Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    )
                  : Column(
                      children: [
                        fields[0],
                        const SizedBox(height: 12),
                        fields[1],
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-Mail-Adresse *'),
            validator: (value) {
              final text = value?.trim() ?? '';
              return !text.contains('@') || !text.contains('.')
                  ? 'Bitte eine gültige E-Mail-Adresse eingeben.'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(
              labelText: 'Passwort *',
              helperText: 'Mindestens 10 Zeichen',
            ),
            validator: (value) => (value?.length ?? 0) < 10
                ? 'Das Passwort muss mindestens 10 Zeichen lang sein.'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefon (optional)'),
          ),
          const SizedBox(height: 26),
          _sectionTitle(
            context,
            'Rolle & Mannschaften',
            'Mehrere Mannschaften sind möglich.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Gewünschte Rolle *'),
            items: const [
              DropdownMenuItem(
                value: UserRole.parent,
                child: Text('Elternteil / Sorgeberechtigte Person'),
              ),
              DropdownMenuItem(
                value: UserRole.player,
                child: Text('Spieler/in'),
              ),
              DropdownMenuItem(
                value: UserRole.coach,
                child: Text('Trainer/in'),
              ),
              DropdownMenuItem(
                value: UserRole.assistantCoach,
                child: Text('Co-Trainer/in'),
              ),
              DropdownMenuItem(
                value: UserRole.teamManager,
                child: Text('Teamorganisation'),
              ),
            ],
            onChanged: (value) => setState(() => _role = value!),
          ),
          const SizedBox(height: 14),
          if (options.teams.isEmpty)
            const Text('Aktuell sind keine Mannschaften zur Registrierung freigegeben.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final team in options.teams)
                  FilterChip(
                    selected: _teamIds.contains(team.id),
                    avatar: Icon(
                      _teamIds.contains(team.id)
                          ? Icons.check_circle_rounded
                          : Icons.shield_outlined,
                      size: 17,
                    ),
                    label: Text(team.label),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _teamIds.add(team.id);
                      } else {
                        _teamIds.remove(team.id);
                      }
                    }),
                  ),
              ],
            ),
          if (_teamIds.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Bitte mindestens eine Mannschaft auswählen.',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          if (_role == UserRole.parent) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _childName,
              decoration: const InputDecoration(
                labelText: 'Name des Kindes *',
                helperText: 'Die Zuordnung wird vor der Freigabe geprüft.',
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _relationship,
              decoration: const InputDecoration(labelText: 'Beziehung zum Kind'),
              items: const [
                DropdownMenuItem(value: 'MOTHER', child: Text('Mutter')),
                DropdownMenuItem(value: 'FATHER', child: Text('Vater')),
                DropdownMenuItem(
                  value: 'GUARDIAN',
                  child: Text('Sorgeberechtigte Person'),
                ),
                DropdownMenuItem(value: 'OTHER', child: Text('Andere Beziehung')),
              ],
              onChanged: (value) => setState(() => _relationship = value!),
            ),
          ],
          const SizedBox(height: 26),
          _sectionTitle(
            context,
            'Datenschutz & Einwilligungen',
            'Die bestätigte Textversion wird revisionssicher gespeichert.',
          ),
          const SizedBox(height: 8),
          _ConsentTile(
            value: _privacyAccepted,
            isRequired: true,
            text: 'Datenschutzinformation gelesen und bestätigt',
            document: options.privacy,
            onChanged: (value) => setState(() => _privacyAccepted = value),
          ),
          _ConsentTile(
            value: _termsAccepted,
            isRequired: true,
            text: 'Nutzungsbedingungen akzeptiert',
            document: options.terms,
            onChanged: (value) => setState(() => _termsAccepted = value),
          ),
          _ConsentTile(
            value: _pushOptIn,
            isRequired: false,
            text: 'Push-Mitteilungen erlauben (optional)',
            document: options.push,
            onChanged: (value) => setState(() => _pushOptIn = value),
          ),
          if (authState.error != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                authState.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: authState.loading
                  ? null
                  : () => _submit(options),
              icon: authState.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.how_to_reg_rounded),
              label: const Text('Registrierung verbindlich absenden'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: authState.loading ? null : () => context.go('/login'),
              child: const Text('Bereits registriert? Zum Login'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit(_RegistrationOptions options) {
    if (!_formKey.currentState!.validate()) return;
    if (_teamIds.isEmpty) {
      setState(() {});
      return;
    }
    if (!_privacyAccepted || !_termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte Datenschutzinformation und Nutzungsbedingungen bestätigen.',
          ),
        ),
      );
      return;
    }
    ref.read(authProvider.notifier).register(
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          role: _role,
          teamIds: _teamIds.toList(),
          childName:
              _role == UserRole.parent ? _childName.text.trim() : null,
          relationship: _role == UserRole.parent ? _relationship : null,
          privacyAccepted: _privacyAccepted,
          termsAccepted: _termsAccepted,
          pushOptIn: _pushOptIn,
          privacyTextVersionId: options.privacy.id,
          termsTextVersionId: options.terms.id,
          pushTextVersionId: options.push?.id,
        );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        Text(
          subtitle,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Pflichtfeld' : null;

  Future<_RegistrationOptions> _loadOptions() async {
    final client = ApiClient();
    final responses = await Future.wait([
      client.dio.get('/organization/public'),
      client.dio.get('/auth/consent-texts'),
    ]);
    final teams = <_RegistrationTeam>[];
    for (final entry in responses[0].data as List<dynamic>) {
      final data = entry as Map<String, dynamic>;
      final season = data['season'] as Map<String, dynamic>;
      for (final ageGroupEntry in data['ageGroups'] as List<dynamic>) {
        final ageGroup = ageGroupEntry as Map<String, dynamic>;
        for (final teamEntry in ageGroup['teams'] as List<dynamic>) {
          final team = teamEntry as Map<String, dynamic>;
          teams.add(
            _RegistrationTeam(
              id: team['id'] as String,
              label:
                  '${ageGroup['code']}-Jugend · ${team['name']} · ${season['name']}',
            ),
          );
        }
      }
    }
    final texts = (responses[1].data as List<dynamic>)
        .map((raw) => _ConsentDocument.fromJson(raw as Map<String, dynamic>))
        .toList();
    _ConsentDocument byType(String type) =>
        texts.firstWhere((document) => document.type == type);
    final pushDocuments =
        texts.where((item) => item.type == 'PUSH_NOTIFICATIONS').toList();
    return _RegistrationOptions(
      teams: teams,
      privacy: byType('PRIVACY_POLICY'),
      terms: byType('TERMS_OF_USE'),
      push: pushDocuments.isEmpty ? null : pushDocuments.first,
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({
    required this.value,
    required this.isRequired,
    required this.text,
    required this.document,
    required this.onChanged,
  });

  final bool value;
  final bool isRequired;
  final String text;
  final _ConsentDocument? document;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: document == null ? null : (value) => onChanged(value ?? false),
      title: Text('$text${isRequired ? ' *' : ''}'),
      subtitle: document == null
          ? const Text('Text derzeit nicht verfügbar')
          : TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('${document!.title} · Version ${document!.version}'),
                  content: SizedBox(
                    width: 620,
                    child: SingleChildScrollView(child: Text(document!.content)),
                  ),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Schließen'),
                    ),
                  ],
                ),
              ),
              child: Text('${document!.title} anzeigen'),
            ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(
            'Registrierung derzeit nicht erreichbar',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text('Bitte Verbindung prüfen und erneut versuchen.'),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Erneut laden'),
          ),
        ],
      ),
    );
  }
}

class _RegistrationOptions {
  const _RegistrationOptions({
    required this.teams,
    required this.privacy,
    required this.terms,
    required this.push,
  });
  final List<_RegistrationTeam> teams;
  final _ConsentDocument privacy;
  final _ConsentDocument terms;
  final _ConsentDocument? push;
}

class _RegistrationTeam {
  const _RegistrationTeam({required this.id, required this.label});
  final String id;
  final String label;
}

class _ConsentDocument {
  const _ConsentDocument({
    required this.id,
    required this.type,
    required this.version,
    required this.title,
    required this.content,
  });
  final String id;
  final String type;
  final int version;
  final String title;
  final String content;

  factory _ConsentDocument.fromJson(Map<String, dynamic> json) =>
      _ConsentDocument(
        id: json['id'] as String,
        type: json['type'] as String,
        version: json['version'] as int,
        title: json['title'] as String,
        content: json['content'] as String,
      );
}
