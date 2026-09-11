import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/communication.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';

final parentContactPreviewProvider =
    FutureProvider.autoDispose<List<FamilyContactMessage>>((ref) async {
  if (ref.watch(authProvider).user == null) return const [];
  ref.watch(manualDataRefreshProvider);
  final timer =
      Timer.periodic(const Duration(seconds: 60), (_) => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  final inbox = await ref.watch(repositoryProvider).familyContactPreview();
  return inbox.messages
      .where((message) => !message.sentByMe && !message.isRead)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});

final parentInboxUnreadProvider = Provider.autoDispose<int>((ref) {
  final notifications =
      ref.watch(parentDashboardSummaryProvider).valueOrNull?.notifications ??
          [];
  final messages = ref.watch(parentContactPreviewProvider).valueOrNull ?? [];
  return notifications
          .where((n) =>
              !n.isRead && !(n.actionUrl?.contains('section=contact') ?? false))
          .length +
      messages.length;
});
