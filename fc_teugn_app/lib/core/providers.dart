import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data_repository.dart';
import 'api_client.dart';
import '../features/auth/auth_controller.dart';
import 'models/event.dart';
import 'models/player.dart';
import 'models/user.dart';

final repositoryProvider = Provider<DataRepository>((ref) {
  final authState = ref.watch(authProvider);
  final client = ApiClient(accessToken: authState.accessToken);
  return DataRepository(client);
});

final playersProvider = FutureProvider<List<PlayerModel>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  return repository.players();
});

final eventsProvider = FutureProvider<List<EventModel>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  return repository.events();
});

final pendingUsersProvider = FutureProvider<List<AppUser>>((ref) async {
  final repository = ref.watch(repositoryProvider);
  return repository.pendingUsers();
});
