import 'package:fc_teugn_app/core/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native releases use the production API by default', () {
    final client = ApiClient();

    expect(client.dio.options.baseUrl, ApiClient.productionBaseUrl);
  });

  test('an explicit API base URL overrides the production default', () {
    final client = ApiClient(baseUrl: 'http://10.0.2.2:4000');

    expect(client.dio.options.baseUrl, 'http://10.0.2.2:4000');
  });
}
