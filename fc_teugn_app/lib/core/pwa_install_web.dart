import 'dart:convert';
import 'dart:js_interop';

@JS('fcTeugnPwaState')
external JSString _pwaState();

@JS('fcTeugnInstallPwa')
external JSPromise<JSBoolean> _installPwa();

Map<String, dynamic> get _state {
  try {
    return jsonDecode(_pwaState().toDart) as Map<String, dynamic>;
  } catch (_) {
    return const {};
  }
}

bool get pwaInstallSupported => true;

bool get pwaRunningStandalone => _state['standalone'] == true;

bool get pwaIsIos => _state['ios'] == true;

bool get pwaIsIosSafari => _state['iosSafari'] == true;

Future<bool> requestPwaInstall() async {
  try {
    return (await _installPwa().toDart).toDart;
  } catch (_) {
    return false;
  }
}
