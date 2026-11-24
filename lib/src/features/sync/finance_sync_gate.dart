import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app.dart';
import '../../core/data/finance_repository.dart';
import '../../core/database/app_database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/settings/app_settings_controller.dart';
import '../../core/sync/ledger_outbox.dart';
import '../../core/sync/ledger_sync.dart';
import '../../core/sync/push_notifications.dart';
import '../../core/sync/sync_database_stub.dart'
    if (dart.library.js_interop) '../../core/sync/sync_database_web.dart';
import '../../core/theme/finance_theme.dart';
import '../home/home_screen.dart';
import '../shared/compass_loading.dart';
import '../shared/compass_ui.dart';

class FinanceSyncGate extends StatefulWidget {
  const FinanceSyncGate({
    super.key,
    required this.settingsController,
    this.localOnly = false,
  });

  final AppSettingsController settingsController;
  final bool localOnly;

  @override
  State<FinanceSyncGate> createState() => _FinanceSyncGateState();
}

class _FinanceSyncGateState extends State<FinanceSyncGate> {
  final _navigator = GlobalKey<NavigatorState>();
  final _offlineNavigator = GlobalKey<NavigatorState>();
  final _loginNavigator = GlobalKey<NavigatorState>();
  final _workspaceNavigation = FinanceWorkspaceNavigation();
  final _offlineWorkspaceNavigation = FinanceWorkspaceNavigation();
  final _client = http.Client();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  late final _api = LedgerSyncApi(_client, Uri.base);
  late final _outbox = openLedgerOutboxStore();
  LedgerSyncSession? _session;
  AppDatabase? _database;
  bool _offline = false;
  bool _registering = false;
  bool _busy = true;
  String? _error;
  bool _updateAvailable = false;
  bool _updatePromptOpen = false;
  Timer? _updatePromptTimer;
  late final VoidCallback _stopListeningForUpdates;

  @override
  void initState() {
    super.initState();
    _stopListeningForUpdates = listenForPwaUpdates(_offerUpdate);
    if (widget.localOnly) {
      _offline = true;
      _busy = false;
    } else {
      unawaited(_connect());
    }
  }

  @override
  void dispose() {
    _stopListeningForUpdates();
    _updatePromptTimer?.cancel();
    _client.close();
    _username.dispose();
    _password.dispose();
    _confirmation.dispose();
    _closeLedger();
    super.dispose();
  }

  void _offerUpdate() {
    if (!mounted || _updateAvailable) return;
    setState(() => _updateAvailable = true);
    _updatePromptTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_updateContext == null) return;
      timer.cancel();
      _updatePromptTimer = null;
      unawaited(_showUpdatePrompt());
    });
  }

  BuildContext? get _updateContext {
    if (_busy ||
        _updatePromptOpen ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return null;
    }
    final session = _session;
    final navigator = session != null
        ? _navigator.currentState
        : _offline
            ? _offlineNavigator.currentState
            : _loginNavigator.currentState;
    if (navigator?.canPop() != false ||
        _workspaceNavigation.hasOpenPage ||
        _offlineWorkspaceNavigation.hasOpenPage) {
      return null;
    }
    if (session != null) {
      if (session.busy || session.needsRecovery) {
        return null;
      }
    } else if (!_offline &&
        (_username.text.isNotEmpty ||
            _password.text.isNotEmpty ||
            _confirmation.text.isNotEmpty)) {
      return null;
    }
    return navigator?.overlay?.context;
  }

  Future<void> _showUpdatePrompt() async {
    final context = _updateContext;
    if (context == null) return;
    _updatePromptTimer?.cancel();
    _updatePromptTimer = null;
    _updatePromptOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PwaUpdateDialog(),
      );
    } finally {
      _updatePromptOpen = false;
    }
  }

  Widget? _settingsActions(Widget? actions) {
    if (!_updateAvailable) return actions;
    return Column(
      children: [
        if (actions != null) ...[actions, const Divider()],
        CompassSettingsRow(
          icon: Icons.system_update_alt_rounded,
          title: '更新应用',
          onTap: () => unawaited(_showUpdatePrompt()),
        ),
      ],
    );
  }

  void _closeLedger() {
    final session = _session;
    if (session != null) {
      session.removeListener(_protectDraft);
      session.dispose();
      protectPendingChanges(false);
    }
    final db = _database;
    if (db != null) unawaited(db.close());
    _session = null;
    _database = null;
  }

  void _protectDraft() {
    protectPendingChanges(_session!.busy);
  }

  Future<void> _connect({
    Future<void> Function()? authenticate,
    String? expectedUsername,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    AppDatabase? openingDatabase;
    try {
      if (authenticate != null) {
        await authenticate();
        if (mounted) {
          TextInput.finishAutofillContext();
          _password.clear();
          _confirmation.clear();
        }
      }
      final remote = await _api.read();
      if (expectedUsername != null &&
          remote.username.toLowerCase() != expectedUsername.toLowerCase()) {
        throw const SyncException('其他标签页已切换账号，请重新登录。');
      }
      await reconcileBrowserPush(remote.accountId);
      final restored = await _outbox.read(remote.accountId, remote.username);
      openingDatabase = await openSyncDatabase();
      final repository = await FinanceRepository.load(openingDatabase);
      final snapshot = restored?.latest?.snapshot ??
          restored?.head.snapshot ??
          remote.snapshot;
      if (snapshot != null) {
        await repository.restoreSyncedSnapshot(snapshot);
      }
      if (!mounted) return;
      final session = LedgerSyncSession(
        _api,
        remote,
        outboxStore: _outbox,
        restored: restored,
      );
      _database = openingDatabase;
      openingDatabase = null;
      _session = session;
      _registering = false;
      session.addListener(_protectDraft);
      session.kickBackgroundSync();
    } on SyncException catch (error) {
      if (authenticate != null || error.status != 401) _error = error.message;
    } on LedgerOutboxConflict catch (error) {
      _error = error.toString();
    } on LedgerOutboxStorageException {
      _error = '无法读取浏览器的同步存储。请检查站点存储权限。';
    } catch (_) {
      _error = '无法打开同步账本，请稍后重试。';
    } finally {
      await openingDatabase?.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final session = _session;
    if (session == null) return;
    await session.logout(before: () => disableBrowserPush(session));
    if (!mounted) return;
    setState(_closeLedger);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return ProviderScope(
        key: ValueKey(session),
        overrides: [
          appDatabaseProvider.overrideWithValue(_database!),
          ledgerSyncSessionProvider.overrideWithValue(session),
        ],
        child: FinanceApp(
          settingsController: widget.settingsController,
          navigatorKey: _navigator,
          workspaceNavigation: _workspaceNavigation,
          syncSettings: _settingsActions(
            _SyncSettingsActions(
              session: session,
              logout: _logout,
              navigation: _workspaceNavigation,
            ),
          ),
          builder: (_, child) => _SyncFrame(
            session: session,
            navigator: _navigator,
            workspaceNavigation: _workspaceNavigation,
            logout: _logout,
            child: child!,
          ),
        ),
      );
    }
    if (_offline) {
      return ProviderScope(
        key: const ValueKey('offline'),
        child: FinanceApp(
          settingsController: widget.settingsController,
          navigatorKey: _offlineNavigator,
          workspaceNavigation: _offlineWorkspaceNavigation,
          syncSettings: _settingsActions(
            widget.localOnly
                ? null
                : CompassSettingsRow(
                    icon: Icons.login_rounded,
                    title: '返回同步登录',
                    onTap: () {
                      setState(() => _offline = false);
                      unawaited(_connect());
                    },
                  ),
          ),
        ),
      );
    }
    final theme = buildFinanceTheme(widget.settingsController.themeStyle);
    return MaterialApp(
      title: 'Finance Compass',
      navigatorKey: _loginNavigator,
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1024;
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: wide ? _desktopLogin(theme) : _mobileLogin(theme),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _brandIcon(double size) => Image.network(
        Uri.base.resolve('/icons/Icon-192.png').toString(),
        width: size,
        height: size,
        excludeFromSemantics: true,
      );

  Widget _mobileLogin(ThemeData theme) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _brandIcon(72)),
            const SizedBox(height: 16),
            Text(
              _registering ? '注册 Finance Compass' : 'Finance Compass',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            _loginFields(),
          ],
        ),
      );

  Widget _desktopLogin(ThemeData theme) => SizedBox(
        width: 820,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _brandIcon(112),
                  const SizedBox(height: 20),
                  Text('Finance Compass', style: theme.textTheme.displaySmall),
                ],
              ),
            ),
            const SizedBox(width: 56),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _registering ? '注册账号' : '登录',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),
                      _loginFields(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _loginFields() => AutofillGroup(
        key: ValueKey(_registering),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _username,
              enabled: !_busy,
              autofillHints: const [AutofillHints.username],
              decoration: InputDecoration(
                labelText: '账号',
                helperText: _registering ? '使用英文字母、数字、点、连字符或下划线' : null,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: true,
              autofillHints: [
                _registering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: const InputDecoration(labelText: '密码'),
              textInputAction:
                  _registering ? TextInputAction.next : TextInputAction.done,
              onSubmitted: _registering ? null : (_) => _submit(),
            ),
            if (_registering) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmation,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: '确认密码'),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 20),
            if (_error case final error?) ...[
              Semantics(
                liveRegion: true,
                child: Text(error, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy) ...[
                    const CompassBusyIndicator(label: '正在连接账本'),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(_registering ? '创建账号并登录' : '登录同步账本')),
                ],
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _toggleRegistration,
              child: Text(_registering ? '已有账号，返回登录' : '注册账号'),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _offline = true),
              child: const Text('使用离线本地账本'),
            ),
          ],
        ),
      );

  void _toggleRegistration() {
    TextInput.finishAutofillContext(shouldSave: false);
    setState(() {
      _registering = !_registering;
      _error = null;
      _password.clear();
      _confirmation.clear();
    });
  }

  void _submit() {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    final error = _inputError(username, password);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final authenticate = _registering ? _api.register : _api.login;
    unawaited(_connect(
      authenticate: () => authenticate(username, password),
      expectedUsername: username,
    ));
  }

  String? _inputError(String username, String password) {
    if (username.isEmpty || password.isEmpty) return '请输入账号和密码。';
    if (!_registering) return null;
    if (!RegExp(r'^[a-zA-Z0-9._-]{1,64}$').hasMatch(username)) {
      return '账号名须为 1–64 位英文字母、数字、点、连字符或下划线。';
    }
    final bytes = utf8.encode(password).length;
    if (bytes < 12 || bytes > 256) {
      return '密码须为 12–256 个 UTF-8 字节，例如至少 12 个英文字母。';
    }
    if (password != _confirmation.text) return '两次输入的密码不一致。';
    return null;
  }
}

class _PwaUpdateDialog extends StatefulWidget {
  const _PwaUpdateDialog();

  @override
  State<_PwaUpdateDialog> createState() => _PwaUpdateDialogState();
}

class _PwaUpdateDialogState extends State<_PwaUpdateDialog> {
  bool _applying = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await applyPwaUpdate();
    } catch (_) {
      if (mounted) setState(() => _error = '无法更新，请重试。');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_applying,
        child: AlertDialog(
          title: const Text('有新版本'),
          content: _error == null
              ? null
              : Semantics(liveRegion: true, child: Text(_error!)),
          actions: [
            TextButton(
              onPressed: _applying ? null : () => Navigator.of(context).pop(),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: _applying ? null : _update,
              child: Text(_applying ? '更新中' : '更新'),
            ),
          ],
        ),
      );
}

class _SyncSettingsActions extends ConsumerWidget {
  const _SyncSettingsActions({
    required this.session,
    required this.logout,
    required this.navigation,
  });

  final LedgerSyncSession session;
  final Future<void> Function() logout;
  final FinanceWorkspaceNavigation navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => Column(
          children: [
            CompassSettingsRow(
              icon: Icons.sync_rounded,
              title: session.hasPending ? '立即同步账本' : '刷新账本',
              subtitle: session.hasPending ? session.message : null,
              onTap: session.busy
                  ? null
                  : () {
                      if (session.hasPending) {
                        session.kickBackgroundSync(immediate: true);
                        return;
                      }
                      unawaited(_run(
                        context,
                        () => ref
                            .read(financeRepositoryProvider.notifier)
                            .pullRemote(
                              canApply: () =>
                                  context.mounted &&
                                  !navigation.hasOpenPage &&
                                  !Navigator.of(context, rootNavigator: true)
                                      .canPop(),
                            ),
                      ));
                    },
            ),
            const Divider(),
            CompassSettingsRow(
              icon: Icons.logout_rounded,
              title: '退出登录',
              onTap: session.busy ? null : () => _run(context, logout),
            ),
          ],
        ),
      );

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final String message;
    try {
      await action();
      return;
    } on SyncException catch (error) {
      message = error.message;
    } catch (_) {
      message = '操作未完成，请重试。';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SyncFrame extends ConsumerStatefulWidget {
  const _SyncFrame({
    required this.session,
    required this.navigator,
    required this.workspaceNavigation,
    required this.logout,
    required this.child,
  });

  final LedgerSyncSession session;
  final GlobalKey<NavigatorState> navigator;
  final FinanceWorkspaceNavigation workspaceNavigation;
  final Future<void> Function() logout;
  final Widget child;

  @override
  ConsumerState<_SyncFrame> createState() => _SyncFrameState();
}

class _SyncFrameState extends ConsumerState<_SyncFrame> {
  bool _confirmDiscard = false;
  bool _polling = false;
  String? _recoveryError;
  late final Timer _pollTimer;
  late final AppLifecycleListener _lifecycle;
  late final VoidCallback _stopListeningForReconnect;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_poll()),
    );
    _lifecycle = AppLifecycleListener(onResume: _resumeSync);
    _stopListeningForReconnect = listenForNetworkReconnect(_resumeSync);
  }

  @override
  void dispose() {
    _pollTimer.cancel();
    _lifecycle.dispose();
    _stopListeningForReconnect();
    _password.dispose();
    super.dispose();
  }

  void _resumeSync() {
    session.kickBackgroundSync(immediate: true);
    unawaited(_poll());
  }

  bool get _canApplyRemote =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      navigator.currentState?.canPop() == false &&
      !widget.workspaceNavigation.hasOpenPage &&
      !session.hasPending &&
      !session.needsRecovery;

  bool get _canPoll =>
      _canApplyRemote &&
      !session.busy &&
      ref.read(financeRepositoryProvider).hasValue;

  Future<void> _poll() async {
    if (_polling || !_canPoll) return;
    _polling = true;
    try {
      // Fetch without blocking the UI, then verify that the user did not
      // enter an editor or start a write while the request was in flight.
      final revision =
          await session.api.readRevision(accountId: session.accountId);
      if (_canPoll && revision > session.revision) {
        final remote = await session.readRemote();
        if (!_canPoll || remote.revision <= session.revision) return;
        await ref
            .read(financeRepositoryProvider.notifier)
            .pullRemote(available: remote, canApply: () => _canApplyRemote);
      }
    } on SyncException catch (error) {
      if (_canPoll &&
          (error.status == 401 || error.code == 'account_changed')) {
        session.markAuthenticationExpired(error);
      }
    } catch (_) {
      // Automatic polling is best-effort. Manual refresh surfaces failures.
    } finally {
      _polling = false;
    }
  }

  LedgerSyncSession get session => widget.session;
  GlobalKey<NavigatorState> get navigator => widget.navigator;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, child) {
          final recovering = session.needsRecovery;
          return Stack(
            fit: StackFit.expand,
            children: [
              Visibility(
                visible: !recovering,
                maintainState: true,
                child: child!,
              ),
              if (recovering) _buildRecovery(context),
            ],
          );
        },
        child: widget.child,
      );

  Widget _buildRecovery(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.authenticationExpired
                                ? '同步登录已失效'
                                : '账本同步需要处理',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        if (session.busy) ...[
                          const SizedBox(width: 8),
                          const CompassBusyIndicator(label: '正在处理同步'),
                        ],
                      ],
                    ),
                    if (session.message case final message?) ...[
                      const SizedBox(height: 8),
                      Semantics(liveRegion: true, child: Text(message)),
                    ],
                    if (_recoveryError case final error?) ...[
                      const SizedBox(height: 8),
                      Semantics(liveRegion: true, child: Text(error)),
                    ],
                    const SizedBox(height: 16),
                    if (session.authenticationExpired) ...[
                      Text('请重新登录 ${session.username} 以继续使用此账本。'),
                      const SizedBox(height: 12),
                      AutofillGroup(
                        child: TextField(
                          controller: _password,
                          enabled: !session.busy,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(labelText: '密码'),
                          onSubmitted: (_) => _reauthenticate(),
                        ),
                      ),
                      FilledButton(
                        onPressed: session.busy ? null : _reauthenticate,
                        child: const Text('重新登录'),
                      ),
                      TextButton(
                        onPressed:
                            session.busy ? null : () => _run(widget.logout),
                        child: const Text('返回登录页'),
                      ),
                    ],
                    if (session.hasPending) ...[
                      if (!session.conflicted && !session.authenticationExpired)
                        FilledButton(
                          onPressed:
                              session.busy ? null : () => _refresh(retry: true),
                          child: const Text('重试保存'),
                        ),
                      if (!session.accountMismatch)
                        OutlinedButton(
                          onPressed: session.busy ? null : _downloadDraft,
                          child: const Text('下载本次账本'),
                        ),
                      if (!session.authenticationExpired)
                        if (_confirmDiscard) ...[
                          const Text('放弃未确认的更改并显示服务器账本？'),
                          TextButton(
                            onPressed: session.busy
                                ? null
                                : () => _refresh(retry: false),
                            child: const Text('确认放弃'),
                          ),
                          TextButton(
                            onPressed: session.busy
                                ? null
                                : () => setState(() => _confirmDiscard = false),
                            child: const Text('取消'),
                          ),
                        ] else
                          TextButton(
                            onPressed: session.busy
                                ? null
                                : () => setState(() => _confirmDiscard = true),
                            child: const Text('放弃并刷新'),
                          ),
                    ] else if (session.requiresRefresh &&
                        !session.authenticationExpired)
                      FilledButton(
                        onPressed:
                            session.busy ? null : () => _refresh(retry: false),
                        child: const Text('重新加载账本'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  void _reauthenticate() {
    if (session.busy) return;
    unawaited(_run(() async {
      await session.renewAuthentication(
        _password.text,
        beforeResume: () => reconcileBrowserPush(session.accountId),
      );
      if (mounted) _password.clear();
    }));
  }

  Future<void> _refresh({required bool retry}) async {
    final nav = navigator.currentState;
    if (nav == null) return;
    setState(() => _confirmDiscard = false);
    nav.popUntil((route) => route.isFirst);
    await _run(() => ref.read(financeRepositoryProvider.notifier).pullRemote(
          retryPending: retry,
          discardPending: !retry && session.hasPending,
        ));
  }

  Future<void> _downloadDraft() => _run(() async {
        final draft = session.pendingBackup();
        if (draft == null) return;
        await FilePicker.platform.saveFile(
          fileName: 'finance-compass-unsynced.json',
          bytes: draft,
        );
      });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _recoveryError = null);
    try {
      await action();
    } on SyncException catch (error) {
      if (mounted && session.message != error.message) {
        setState(() => _recoveryError = error.message);
      }
    } catch (_) {
      if (mounted) setState(() => _recoveryError = '操作未完成，请重试。');
    }
  }
}
