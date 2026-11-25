import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_analysis_service.dart';
import 'repository_provider.dart';

/// AI 分析状态
class AiAnalysisState {
  final bool loading;
  final String? summary;
  final String? error;
  final bool completed;

  const AiAnalysisState({
    this.loading = false,
    this.summary,
    this.error,
    this.completed = false,
  });

  AiAnalysisState copyWith({
    bool? loading,
    String? summary,
    String? error,
    bool clearError = false,
    bool? completed,
  }) {
    return AiAnalysisState(
      loading: loading ?? this.loading,
      summary: summary ?? this.summary,
      error: clearError ? null : error ?? this.error,
      completed: completed ?? this.completed,
    );
  }
}

/// 全局 AI 分析 Provider，后台运行不受页面切换影响
class AiAnalysisNotifier extends Notifier<AiAnalysisState> {
  Object? _ledgerScope;

  @override
  AiAnalysisState build() {
    ref.watch(ledgerSyncSessionProvider);
    _ledgerScope = Object();
    ref.onDispose(() => _ledgerScope = null);
    return const AiAnalysisState();
  }

  Future<void> runAnalysis({
    bool includePlanned = false,
    int monthCount = 6,
    int futureMonthCount = AiAnalysisService.defaultFutureMonthCount,
  }) async {
    final scope = _ledgerScope;
    final repoAsync = ref.read(financeRepositoryProvider);
    final repo = repoAsync.value;
    if (repo == null) return;

    final gatewayUrl = repo.aiGatewayUrl;
    if (gatewayUrl.isEmpty) {
      state = const AiAnalysisState(error: '请先在设置中配置 AI 网关地址');
      return;
    }

    // 已在运行则跳过
    if (state.loading) return;

    state = const AiAnalysisState(loading: true);

    try {
      final service = AiAnalysisService(gatewayUrl: gatewayUrl);
      final summary = await service.generateAnalysis(
        repo,
        includePlanned: includePlanned,
        monthCount: monthCount,
        futureMonthCount: futureMonthCount,
      );
      if (identical(_ledgerScope, scope)) {
        state = AiAnalysisState(summary: summary, completed: true);
      }
    } catch (e) {
      final msg = e is AiNetworkException ? e.message : 'AI 分析失败：$e';
      if (identical(_ledgerScope, scope)) state = AiAnalysisState(error: msg);
    }
  }

  void dismissCompleted() {
    state = state.copyWith(completed: false);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final aiAnalysisProvider =
    NotifierProvider<AiAnalysisNotifier, AiAnalysisState>(
  AiAnalysisNotifier.new,
  dependencies: [financeRepositoryProvider, ledgerSyncSessionProvider],
);
