import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/round_provider.dart'; // defaultRoundIdProvider
import '../providers/ranking_provider.dart'; // topRankingsProvider

class RankingView extends ConsumerWidget {
  const RankingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ① 최신 라운드 ID 로딩
    final roundAsync = ref.watch(defaultRoundIdProvider);

    return roundAsync.when(
      data: (_) {
        // ② 랭킹 스트림 구독
        final rankings = ref.watch(topRankingsProvider);
        return Scaffold(
          appBar: AppBar(title: const Text('실시간 랭킹')),
          body: rankings.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('랭킹 오류: $e')),
            data: (list) {
              if (list.isEmpty) {
                return const Center(child: Text('랭킹 데이터가 없습니다'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final e = list[i];
                  return ListTile(
                    leading: Text('#${i + 1}'),
                    title: Text(e.nick),
                    trailing: Text('${e.score}점'),
                  );
                },
              );
            },
          ),
        );
      },
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('초기 오류: $e'))),
    );
  }
}
