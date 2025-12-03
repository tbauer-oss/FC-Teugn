import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data_repository.dart';
import 'api_client.dart';
import '../features/auth/auth_controller.dart';

final repositoryProvider = Provider<DataRepository>((ref) {
  final authState = ref.watch(authProvider);
  final client = ApiClient(accessToken: authState.accessToken);
  return DataRepository(client);
});
