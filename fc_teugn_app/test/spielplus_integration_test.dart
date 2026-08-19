import 'package:fc_teugn_app/core/spielplus_credentials.dart';
import 'package:fc_teugn_app/features/integrations/spielplus_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryCredentialStorage implements SpielPlusCredentialStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('SpielPLUS navigation only accepts official secure hosts', () {
    expect(
      spielPlusPortalUri.toString(),
      'https://spielplus.bfv.de/spielplus/oauth/login',
    );
    expect(spielPlusLoginUri, spielPlusPortalUri);
    expect(
      isAllowedSpielPlusUri(
          Uri.parse('https://spielplus.bfv.de/spielplus/oauth/login')),
      isTrue,
    );
    expect(
      isAllowedSpielPlusUri(Uri.parse('https://auth.dfbnet.org/realms/dfbnet')),
      isTrue,
    );
    expect(
      isAllowedSpielPlusUri(Uri.parse('http://spielplus.bfv.de/spielplus')),
      isFalse,
    );
    expect(
      isAllowedSpielPlusUri(Uri.parse('https://bfv.de.example.org/login')),
      isFalse,
    );
  });

  test('saved SpielPLUS credentials stay separated per app user', () async {
    final storage = _MemoryCredentialStorage();
    final first =
        SpielPlusCredentialsStore(userId: 'trainer-1', storage: storage);
    final second =
        SpielPlusCredentialsStore(userId: 'trainer-2', storage: storage);

    await first.save(const SpielPlusCredentials(
      username: 'kennung-1',
      password: 'geheim-1',
      automaticLogin: true,
    ));

    expect((await first.load()).username, 'kennung-1');
    expect((await first.load()).automaticLogin, isTrue);
    expect((await second.load()).isComplete, isFalse);

    await first.clear();
    expect((await first.load()).isComplete, isFalse);
  });

  test('automatic login script escapes values and submits the DFBnet form', () {
    final script = buildSpielPlusCredentialScript(
      const SpielPlusCredentials(
        username: 'trainer"name',
        password: r'p\ass"word',
        automaticLogin: true,
      ),
    );

    expect(script, contains("'#username'"));
    expect(script, contains("'#password'"));
    expect(script, contains("document.querySelector('#kc-form-login')"));
    expect(script, contains('requestSubmit'));
    expect(script, contains('input[autocomplete="username"]'));
    expect(script, contains('input[autocomplete="current-password"]'));
    expect(script, contains("return 'credentials-submitted'"));
    expect(script, contains(r'trainer\"name'));
  });

  test('credential script can fill fields without automatic submission', () {
    final script = buildSpielPlusCredentialScript(
      const SpielPlusCredentials(
        username: 'kennung',
        password: 'passwort',
        automaticLogin: true,
      ),
      submitAutomatically: false,
    );

    expect(script, contains('if (false)'));
    expect(script, contains("return 'credentials-filled'"));
  });

  testWidgets('SpielPLUS device settings remain usable on narrow phones',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemoryCredentialStorage();
    final store =
        SpielPlusCredentialsStore(userId: 'trainer-1', storage: storage);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpielPlusSettingsCard(
              userId: 'trainer-1',
              store: store,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('manage-spielplus-credentials')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('spielplus-username')), 'kennung');
    await tester.enterText(
        find.byKey(const ValueKey('spielplus-password')), 'passwort');
    await tester.tap(find.byKey(const ValueKey('spielplus-auto-login')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('save-spielplus-credentials')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-spielplus-credentials')));
    await tester.pumpAndSettle();

    final saved = await store.load();
    expect(saved.username, 'kennung');
    expect(saved.password, 'passwort');
    expect(saved.automaticLogin, isTrue);
    expect(find.byKey(const ValueKey('open-spielplus')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
