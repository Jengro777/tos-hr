import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../config/app_version.dart';
import '../config/wecom_config.dart';
import '../data/attendance_database.dart';
import '../data/connection_status.dart';
import '../services/sync_api_server.dart';
import '../theme/tospino_hr_style.dart';

typedef AttendanceSyncCallback = Future<bool> Function(
  AttendanceSyncMode mode,
  AttendanceSyncDataset dataset,
  ValueChanged<String>? onProgress,
);

typedef ConnectionCheckCallback = Future<ConnectionStatus> Function();

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.config,
    required this.database,
    required this.onSync,
    required this.onCheckWeCom,
    required this.syncApiServer,
    this.versionInfo = const AppVersionInfo.unknown(),
  });

  final WecomConfig config;
  final AttendanceDatabase database;
  final AttendanceSyncCallback onSync;
  final ConnectionCheckCallback onCheckWeCom;
  final SyncApiServer syncApiServer;
  final AppVersionInfo versionInfo;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _fullSyncConfirmation = '我已知晓全量获取时间较长，期间不可离开页面';

  final _confirmationController = TextEditingController();
  AttendanceDatabaseStats? _stats;
  bool _loadingStats = true;
  bool _checkingDatabase = true;
  bool _checkingWeCom = true;
  ConnectionStatus? _databaseStatus;
  ConnectionStatus? _wecomStatus;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _checkConnections();
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 22),
                  _buildConnectionCard(),
                  const SizedBox(height: 14),
                  _buildSyncApiCard(),
                  const SizedBox(height: 14),
                  _buildSyncCard(),
                  const SizedBox(height: 14),
                  _buildStorageCard(),
                  const SizedBox(height: 14),
                  _buildSecurityNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '返回',
          style: IconButton.styleFrom(
            backgroundColor: TospinoHrColors.surface,
            foregroundColor: TospinoHrColors.ink,
            side: const BorderSide(color: TospinoHrColors.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TOSPINO · SETTINGS', style: TospinoHrText.eyebrow),
              const SizedBox(height: 2),
              const Text('设置', style: TospinoHrText.pageTitle),
              if (widget.versionInfo.isAvailable) ...[
                const SizedBox(height: 3),
                Text(
                  widget.versionInfo.displayText,
                  style: TospinoHrText.meta.copyWith(
                    color: TospinoHrColors.ink4,
                  ),
                ),
              ],
            ],
          ),
        ),
        _SettingsConfigChip(isConfigured: widget.config.isConfigured),
      ],
    );
  }

  Widget _buildConnectionCard() {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeading(
            icon: Icons.cable_rounded,
            title: '连接状态',
            subtitle: _checkingDatabase || _checkingWeCom
                ? '正在检测连接状态…'
                : '最近一次连接检测结果',
            trailing: IconButton(
              onPressed: _checkingDatabase || _checkingWeCom
                  ? null
                  : _checkConnections,
              tooltip: '检测全部连接',
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final tiles = [
                _ConnectionTile(
                  icon: Icons.storage_rounded,
                  title: '数据库',
                  endpoint: widget.database.storageLabel,
                  details: [
                    _ConnectionDetail(
                      label: '数据库地址',
                      value: widget.database.storageEndpoint,
                    ),
                  ],
                  status: _databaseStatus,
                  checking: _checkingDatabase,
                  onTest: _testDatabaseConnection,
                ),
                _ConnectionTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: '企业微信',
                  endpoint: widget.config.maskedCorpId,
                  details: [
                    _ConnectionDetail(
                      label: 'AgentId',
                      value: widget.config.maskedAgentId,
                    ),
                    _ConnectionDetail(
                      label: '打卡 Secret',
                      value: widget.config.hasCheckinSecret ? '已加载' : '未配置',
                      valueColor: widget.config.hasCheckinSecret
                          ? TospinoHrColors.success
                          : TospinoHrColors.warning,
                    ),
                  ],
                  status: _wecomStatus,
                  checking: _checkingWeCom,
                  onTest: _testWeComConnection,
                ),
              ];
              if (compact) {
                return Column(
                  children: [
                    tiles.first,
                    const SizedBox(height: 10),
                    tiles.last,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tiles.first),
                  const SizedBox(width: 10),
                  Expanded(child: tiles.last),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncApiCard() {
    final server = widget.syncApiServer;
    final running = server.isRunning;
    final error = server.error;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeading(
            icon: Icons.api_rounded,
            title: '同步 API',
            subtitle: running ? '服务运行中 · 端口 ${server.port}' : error ?? '服务未启动',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: running
                    ? TospinoHrColors.successTint
                    : TospinoHrColors.warningTint,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                running ? '运行中' : '未启动',
                style: TospinoHrText.meta.copyWith(
                  color: running
                      ? TospinoHrColors.success
                      : TospinoHrColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '两个接口均使用 GET。{URL} 由外部系统配置，'
            '并支持 X-Api-Token 请求头或 token 查询参数。',
            style: TospinoHrText.meta,
          ),
          const SizedBox(height: 12),
          const _ApiEndpointRow(
            label: '全量同步',
            urls: ['{URL}/api/attendance/sync/full'],
          ),
          const SizedBox(height: 10),
          const _ApiEndpointRow(
            label: '增量同步',
            urls: ['{URL}/api/attendance/sync/incremental'],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeading(
            icon: Icons.sync_rounded,
            title: '数据同步',
            subtitle: '所有成员 · 2018-01 至当前月份',
          ),
          const SizedBox(height: 16),
          const _SyncGroupLabel('增量同步'),
          _SyncOptionRow(
            icon: Icons.sync_rounded,
            title: '打卡记录',
            description: '补齐缺失的历史打卡周期',
            onTap: widget.config.isConfigured
                ? () => _runSync(
                    AttendanceSyncMode.incremental,
                    AttendanceSyncDataset.checkins,
                  )
                : null,
          ),
          _SyncOptionRow(
            icon: Icons.description_outlined,
            title: '月报',
            description: '补齐缺失的完整自然月月报',
            onTap: widget.config.isConfigured
                ? () => _runSync(
                    AttendanceSyncMode.incremental,
                    AttendanceSyncDataset.reports,
                  )
                : null,
          ),
          _SyncOptionRow(
            icon: Icons.sync_alt_rounded,
            title: '全部数据',
            description: '同时补齐打卡记录和月报',
            onTap: widget.config.isConfigured
                ? () => _runSync(
                    AttendanceSyncMode.incremental,
                    AttendanceSyncDataset.all,
                  )
                : null,
          ),
          const Divider(height: 26),
          const _SyncGroupLabel('全量覆盖'),
          _SyncOptionRow(
            icon: Icons.warning_amber_rounded,
            title: '打卡记录',
            description: '重新获取全部历史打卡',
            warning: true,
            onTap: widget.config.isConfigured
                ? () => _confirmAndRunFullSync(AttendanceSyncDataset.checkins)
                : null,
          ),
          _SyncOptionRow(
            icon: Icons.description_outlined,
            title: '月报',
            description: '重新获取全部自然月月报',
            warning: true,
            onTap: widget.config.isConfigured
                ? () => _confirmAndRunFullSync(AttendanceSyncDataset.reports)
                : null,
          ),
          _SyncOptionRow(
            icon: Icons.warning_amber_rounded,
            title: '全部数据',
            description: '重新获取全部历史打卡和月报',
            warning: true,
            onTap: widget.config.isConfigured
                ? () => _confirmAndRunFullSync(AttendanceSyncDataset.all)
                : null,
          ),
          if (!widget.config.isConfigured) ...[
            const SizedBox(height: 12),
            Text(
              '请先完成企业微信配置：${widget.config.missingCheckinFields.join('、')}',
              style: TospinoHrText.meta.copyWith(color: TospinoHrColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    final stats = _stats;
    final lastRun = stats?.lastRun;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeading(
            icon: Icons.storage_rounded,
            title: '数据存储',
            subtitle: _loadingStats ? '正在读取数据状态…' : '统一持久化存储',
            trailing: IconButton(
              onPressed: _loadingStats ? null : _loadStats,
              tooltip: '刷新状态',
              icon: const Icon(Icons.refresh_rounded, size: 19),
            ),
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DataMetric(
                label: '打卡明细',
                value: '${stats?.checkinRecordCount ?? 0}',
                unit: '条',
              ),
              _DataMetric(
                label: '打卡日期',
                value: '${stats?.attendanceDateCount ?? 0}',
                unit: '天',
              ),
              _DataMetric(
                label: '月报快照',
                value: '${stats?.monthlyReportCount ?? 0}',
                unit: '份',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ConfigRow(
            label: '最近同步',
            value: lastRun == null
                ? '尚未同步'
                : DateFormat('yyyy-MM-dd HH:mm')
                      .format(lastRun.completedAt ?? lastRun.startedAt),
          ),
          const Divider(height: 21),
          _ConfigRow(
            label: '同步模式',
            value: lastRun == null
                ? '--'
                : lastRun.syncMode == AttendanceSyncMode.full.name
                ? '全量覆盖'
                : '增量获取',
          ),
          const Divider(height: 21),
          _ConfigRow(
            label: '同步状态',
            value: lastRun == null
                ? '--'
                : lastRun.status == 'completed'
                ? '已完成'
                : '未完成',
            valueColor: lastRun?.status == 'completed'
                ? TospinoHrColors.success
                : lastRun == null
                ? TospinoHrColors.ink3
                : TospinoHrColors.danger,
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildConfigCard() {
    final config = widget.config;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeading(
            icon: Icons.badge_outlined,
            title: '企业微信配置',
            subtitle: '当前运行环境加载的配置记录',
          ),
          const SizedBox(height: 14),
          _ConfigRow(label: '数据存储', value: widget.database.storageLabel),
          const Divider(height: 21),
          _ConfigRow(label: '数据库地址', value: widget.database.storageEndpoint),
          const Divider(height: 21),
          _ConfigRow(label: '企业 ID', value: config.maskedCorpId),
          const Divider(height: 21),
          _ConfigRow(label: 'AgentId', value: config.maskedAgentId),
          const Divider(height: 21),
          _ConfigRow(
            label: '打卡 Secret',
            value: config.hasCheckinSecret ? '已加载' : '未配置',
            valueColor: config.hasCheckinSecret
                ? TospinoHrColors.success
                : TospinoHrColors.warning,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: TospinoHrColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '配置通过启动参数加载。为防止泄露，设置页只显示脱敏标识和加载状态，不展示 Secret 明文。',
              style: TospinoHrText.meta,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TospinoHrColors.brandTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TospinoHrColors.brandTintBorder),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: TospinoHrColors.brand, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '当前客户端仍直接保存企业微信应用凭据。正式部署时应将凭据与打卡请求迁移到服务端代理。',
              style: TospinoHrText.body,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() => _loadingStats = true);
    }
    try {
      final stats = await widget.database.loadStats();
      if (mounted) {
        setState(() => _stats = stats);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Future<void> _checkConnections() async {
    if (mounted) {
      setState(() {
        _checkingDatabase = true;
        _checkingWeCom = true;
      });
    }
    final results = await Future.wait([
      widget.database.checkConnection(),
      widget.onCheckWeCom(),
    ]);
    if (mounted) {
      setState(() {
        _databaseStatus = results[0];
        _wecomStatus = results[1];
        _checkingDatabase = false;
        _checkingWeCom = false;
      });
    }
  }

  Future<void> _testDatabaseConnection() async {
    setState(() => _checkingDatabase = true);
    final status = await widget.database.checkConnection();
    if (mounted) {
      setState(() {
        _databaseStatus = status;
        _checkingDatabase = false;
      });
    }
  }

  Future<void> _testWeComConnection() async {
    setState(() => _checkingWeCom = true);
    final status = await widget.onCheckWeCom();
    if (mounted) {
      setState(() {
        _wecomStatus = status;
        _checkingWeCom = false;
      });
    }
  }

  Future<void> _confirmAndRunFullSync(AttendanceSyncDataset dataset) async {
    _confirmationController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var matches = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('确认全量获取${dataset.label}'),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '全量获取会重新拉取全部成员从 2018-01 至当前月份的'
                    '${dataset.label}，耗时较长，执行期间不能关闭进度窗口或离开页面。',
                    style: TextStyle(height: 1.55),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '请原样输入以下文案以继续：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 7),
                  const SelectableText(
                    _fullSyncConfirmation,
                    style: TextStyle(
                      color: TospinoHrColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmationController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '输入确认文案'),
                    onChanged: (value) {
                      setDialogState(
                        () => matches = value.trim() == _fullSyncConfirmation,
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: matches
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: TospinoHrColors.brand,
                ),
                child: const Text('开始全量获取'),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed == true && mounted) {
      await _runSync(AttendanceSyncMode.full, dataset);
    }
  }

  Future<void> _runSync(
    AttendanceSyncMode mode,
    AttendanceSyncDataset dataset,
  ) async {
    final progress = ValueNotifier<String>(
      '正在准备${mode == AttendanceSyncMode.full ? '全量' : '增量'}'
      '获取${dataset.label}…',
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            '正在${mode == AttendanceSyncMode.full ? '全量' : '增量'}'
            '获取${dataset.label}',
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 18),
                ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (context, message, child) => Text(
                    message,
                    style: TospinoHrText.body.copyWith(
                      color: TospinoHrColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.6,
                    ),
                  ),
                ),
                if (mode == AttendanceSyncMode.full) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '全量获取期间不可离开当前页面。',
                    style: TextStyle(
                      color: TospinoHrColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    var lastMessage = progress.value;
    final succeeded = await widget.onSync(mode, dataset, (message) {
      lastMessage = message;
      progress.value = message;
    });
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (navigator.canPop()) {
      navigator.pop();
    }
    progress.dispose();
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? '${mode == AttendanceSyncMode.full ? '全量' : '增量'}'
                      '${dataset.label}获取已完成'
                : lastMessage,
          ),
        ),
      );
    }
  }
}

class _SyncGroupLabel extends StatelessWidget {
  const _SyncGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text(
        text,
        style: TospinoHrText.meta.copyWith(
          fontWeight: FontWeight.w700,
          color: TospinoHrColors.ink3,
        ),
      ),
    );
  }
}

class _SyncOptionRow extends StatelessWidget {
  const _SyncOptionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? TospinoHrColors.danger : TospinoHrColors.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: warning
            ? TospinoHrColors.brandTint.withValues(alpha: 0.65)
            : TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TospinoHrText.meta.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TospinoHrColors.ink4,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TospinoHrColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: TospinoHrColors.line),
        boxShadow: TospinoHrShadows.card,
      ),
      child: child,
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: TospinoHrColors.brandTint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: TospinoHrColors.brand, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TospinoHrText.cardTitle),
              const SizedBox(height: 3),
              Text(subtitle, style: TospinoHrText.meta),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _ConnectionDetail {
  const _ConnectionDetail({
    required this.label,
    required this.value,
    this.valueColor = TospinoHrColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;
}

class _ConnectionDetailRow extends StatelessWidget {
  const _ConnectionDetailRow({required this.detail});

  final _ConnectionDetail detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 94,
          child: Text(detail.label, style: TospinoHrText.meta),
        ),
        Expanded(
          child: Text(
            detail.value,
            textAlign: TextAlign.right,
            style: TospinoHrText.body.copyWith(
              color: detail.valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.icon,
    required this.title,
    required this.endpoint,
    required this.details,
    required this.status,
    required this.checking,
    required this.onTest,
  });

  final IconData icon;
  final String title;
  final String endpoint;
  final List<_ConnectionDetail> details;
  final ConnectionStatus? status;
  final bool checking;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final connected = status?.connected == true;
    final color = checking
        ? TospinoHrColors.ink4
        : connected
        ? TospinoHrColors.success
        : TospinoHrColors.danger;
    final background = checking
        ? TospinoHrColors.surfaceMuted
        : connected
        ? TospinoHrColors.successTint
        : TospinoHrColors.dangerTint;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TospinoHrColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: TospinoHrColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: checking ? TospinoHrColors.ink3 : color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TospinoHrText.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TospinoHrText.meta,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (checking)
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.7),
                      )
                    else
                      Icon(
                        connected
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 13,
                        color: color,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      checking
                          ? '检测中'
                          : connected
                          ? '已连接'
                          : '连接失败',
                      style: TospinoHrText.meta.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var index = 0; index < details.length; index++) ...[
              _ConnectionDetailRow(detail: details[index]),
              if (index != details.length - 1) const Divider(height: 15),
            ],
          ],
          const SizedBox(height: 11),
          Text(
            checking ? '正在检测连接与鉴权…' : status?.message ?? '尚未检测',
            style: TospinoHrText.meta.copyWith(
              color: checking ? TospinoHrColors.ink3 : color,
              height: 1.45,
            ),
          ),
          if (!checking && status != null) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Text('延迟 ${status!.latencyText}', style: TospinoHrText.meta),
                const Spacer(),
                Text(
                  DateFormat('HH:mm:ss').format(status!.checkedAt),
                  style: TospinoHrText.meta,
                ),
              ],
            ),
          ],
          const SizedBox(height: 11),
          SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              onPressed: checking ? null : onTest,
              style: OutlinedButton.styleFrom(
                foregroundColor: TospinoHrColors.ink,
                side: const BorderSide(color: TospinoHrColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cable_rounded, size: 17),
              label: Text(checking ? '正在测试连接…' : '测试连接'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiEndpointRow extends StatelessWidget {
  const _ApiEndpointRow({required this.label, required this.urls});

  final String label;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: TospinoHrText.cardTitle),
          const SizedBox(height: 8),
          if (urls.isEmpty)
            Text('未获取到可用地址', style: TospinoHrText.meta)
          else
            for (final url in urls)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        url,
                        style: TospinoHrText.meta.copyWith(
                          color: TospinoHrColors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('API 地址已复制')),
                          );
                        }
                      },
                      tooltip: '复制地址',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 17),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _DataMetric extends StatelessWidget {
  const _DataMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TospinoHrText.meta),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: TospinoHrText.number),
                TextSpan(
                  text: ' $unit',
                  style: TospinoHrText.meta.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    required this.label,
    required this.value,
    this.valueColor = TospinoHrColors.ink,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 116, child: Text(label, style: TospinoHrText.meta)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TospinoHrText.body.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsConfigChip extends StatelessWidget {
  const _SettingsConfigChip({required this.isConfigured});

  final bool isConfigured;

  @override
  Widget build(BuildContext context) {
    final color = isConfigured
        ? TospinoHrColors.success
        : TospinoHrColors.warning;
    final background = isConfigured
        ? TospinoHrColors.successTint
        : TospinoHrColors.warningTint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        isConfigured ? '配置已完成' : '待配置',
        style: TospinoHrText.meta.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
