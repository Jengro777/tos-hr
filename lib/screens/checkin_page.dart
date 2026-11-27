import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../config/wecom_config.dart';
import '../config/sync_api_config.dart';
import '../data/attendance_database.dart';
import '../data/attendance_database_factory.dart';
import '../data/attendance_summary.dart';
import '../data/checkin_record.dart';
import '../data/monthly_report.dart';
import '../data/wecom_exception.dart';
import '../data/wecom_member.dart';
import '../services/wecom_api_client.dart';
import '../services/attendance_sync_service.dart';
import '../services/sync_api_server.dart';
import '../theme/tospino_hr_style.dart';
import '../widgets/attendance_summary_table.dart';
import 'settings_page.dart';

enum _WorkspaceMode { details, monthly, summary, all }

class CheckinPage extends StatefulWidget {
  const CheckinPage({
    super.key,
    required this.config,
    this.apiClient,
    this.database,
    this.syncApiConfig = const SyncApiConfig(),
  });

  final WecomConfig config;
  final WeComApiClient? apiClient;
  final AttendanceDatabase? database;
  final SyncApiConfig syncApiConfig;

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  static const _brandBlue = TospinoHrColors.brand;
  static const _muted = TospinoHrColors.ink3;
  static const _fullSyncConfirmation = '我已知晓全量获取时间较长，期间不可离开页面';
  static const _checkinPageSize = 200;

  final _userIdsController = TextEditingController();
  final _summarySearchController = TextEditingController();
  late final WeComApiClient _apiClient;
  late final bool _ownsApiClient;
  late final AttendanceDatabase _database;
  late final bool _ownsDatabase;
  late final AttendanceSyncService _syncService;
  late final SyncApiServer _syncApiServer;

  late DateTime _startDate;
  late DateTime _endDate;
  late int _reportYear;
  late int _reportMonthNumber;
  late int _summaryYear;
  late DateTime _allStartDate;
  late DateTime _allEndDate;
  late DateTime _allEarliestDate;
  bool _allDateRangeAuto = true;
  _WorkspaceMode _mode = _WorkspaceMode.details;
  CheckinDataType _dataType = CheckinDataType.all;
  List<CheckinRecord> _records = const [];
  int _totalRecordCount = 0;
  int _totalMemberCount = 0;
  int _totalExceptionCount = 0;
  List<AttendanceSummaryRow> _summaryRows = const [];
  List<WeComMember> _members = const [];
  bool _isLoading = false;
  bool _isLoadingMoreRecords = false;
  bool _hasSearched = false;
  String? _errorMessage;
  String? _summaryProgress;
  bool _apiSyncInProgress = false;

  @override
  void initState() {
    super.initState();
    _ownsApiClient = widget.apiClient == null;
    _apiClient = widget.apiClient ?? WeComApiClient(config: widget.config);
    _ownsDatabase = widget.database == null;
    _database = widget.database ?? createAttendanceDatabase();
    _syncService = AttendanceSyncService(
      apiClient: _apiClient,
      database: _database,
    );
    _syncApiServer = createSyncApiServer(
      config: widget.syncApiConfig,
      onSync: _handleApiSync,
    );
    _syncApiServer.start();

    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day);
    _startDate = _endDate;
    _reportYear = now.year;
    _reportMonthNumber = now.month;
    _summaryYear = now.year;
    _allEarliestDate = DateTime(2018);
    _allStartDate = _allEarliestDate;
    _allEndDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _userIdsController.dispose();
    _summarySearchController.dispose();
    if (_ownsApiClient) {
      _apiClient.close();
    }
    if (_ownsDatabase) {
      _database.close();
    }
    _syncApiServer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 980;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isWide ? 22 : 16,
                isWide ? 30 : 18,
                isWide ? 22 : 16,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  if (!widget.config.isConfigured) ...[
                    const SizedBox(height: 18),
                    _buildConfigWarning(),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: TospinoHrColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: TospinoHrColors.line),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<_WorkspaceMode>(
                          style: ButtonStyle(
                            elevation: WidgetStateProperty.all(0),
                            side: WidgetStateProperty.all(BorderSide.none),
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              return states.contains(WidgetState.selected)
                                  ? TospinoHrColors.brandTint
                                  : Colors.transparent;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              return states.contains(WidgetState.selected)
                                  ? TospinoHrColors.brand
                                  : TospinoHrColors.ink3;
                            }),
                            textStyle: WidgetStateProperty.all(
                              const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: _WorkspaceMode.details,
                              icon: Icon(Icons.fingerprint_rounded, size: 18),
                              label: Text('打卡明细'),
                            ),
                            ButtonSegment(
                              value: _WorkspaceMode.monthly,
                              icon: Icon(
                                Icons.calendar_view_month_rounded,
                                size: 18,
                              ),
                              label: Text('月度汇总'),
                            ),
                            ButtonSegment(
                              value: _WorkspaceMode.summary,
                              icon: Icon(Icons.table_chart_rounded, size: 18),
                              label: Text('分年汇总'),
                            ),
                            ButtonSegment(
                              value: _WorkspaceMode.all,
                              icon: Icon(Icons.history_rounded, size: 18),
                              label: Text('历史汇总'),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: _isLoading
                              ? null
                              : (selection) {
                                  setState(() {
                                    _mode = selection.single;
                                    _records = const [];
                                    _totalRecordCount = 0;
                                    _totalMemberCount = 0;
                                    _totalExceptionCount = 0;
                                    _isLoadingMoreRecords = false;
                                    _summaryRows = const [];
                                    _summarySearchController.clear();
                                    _hasSearched = false;
                                    _errorMessage = null;
                                    _summaryProgress = null;
                                  });
                                  if (selection.single !=
                                      _WorkspaceMode.details) {
                                    _loadLocalData();
                                  }
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _buildQueryPanel(),
                  const SizedBox(height: 18),
                  _buildResultPanel(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 16,
      spacing: 20,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TospinoLogoMark(size: 50),
            const SizedBox(width: 13),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOSPINO · PEOPLE OPS',
                  style: TospinoHrText.eyebrow,
                ),
                const SizedBox(height: 3),
                Text(
                  'Tospino-HR',
                  style: TospinoHrText.pageTitle.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 2),
                const Text('企业微信考勤数据中心', style: TospinoHrText.meta),
              ],
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConfigStatusChip(isConfigured: widget.config.isConfigured),
            const SizedBox(width: 9),
            IconButton(
              onPressed: _showSettingsDialog,
              tooltip: '设置',
              style: IconButton.styleFrom(
                backgroundColor: TospinoHrColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              icon: const Icon(Icons.settings_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfigWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TospinoHrColors.warningTint,
        border: Border.all(color: TospinoHrColors.warningBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.key_off_rounded, color: TospinoHrColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '企业微信配置尚未完成',
                  style: TextStyle(
                    color: TospinoHrColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '缺少：${widget.config.missingFields.join('、')}。'
                  '请通过配置文件传入企业ID、AgentId和应用Secret。',
                  style: const TextStyle(
                    color: TospinoHrColors.warning,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showConfigDialog(context),
            child: const Text('查看配置'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLegacyQueryPanel() {
    final isDetails = _mode == _WorkspaceMode.details;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            icon: Icons.tune_rounded,
            title: '查询条件',
            subtitle: isDetails ? '从 TiDB 按日期和成员查询' : '从 TiDB 统计，数据在设置中同步',
          ),
          const SizedBox(height: 22),
          if (isDetails) ...[
            const _FieldLabel('打卡类型'),
            const SizedBox(height: 8),
            DropdownButtonFormField<CheckinDataType>(
              initialValue: _dataType,
              isExpanded: true,
              decoration: _inputDecoration(),
              items: CheckinDataType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.label)),
                  )
                  .toList(growable: false),
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _dataType = value);
                      }
                    },
            ),
            const SizedBox(height: 18),
            const _FieldLabel('查询日期'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: '开始',
                    date: _startDate,
                    onTap: _isLoading ? null : () => _pickDate(isStart: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: _muted,
                  ),
                ),
                Expanded(
                  child: _DateField(
                    label: '结束',
                    date: _endDate,
                    onTap: _isLoading ? null : () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (_mode == _WorkspaceMode.monthly) ...[
              const SizedBox(height: 18),
              const _FieldLabel('年月'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _reportYear,
                      isExpanded: true,
                      decoration: _inputDecoration(),
                      items: [
                        for (
                          var year = DateTime.now().year;
                          year >= 2018;
                          year--
                        )
                          DropdownMenuItem(value: year, child: Text('$year 年')),
                      ],
                      onChanged: _isLoading
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  _reportYear = value;
                                  _hasSearched = false;
                                  _summaryRows = const [];
                                });
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _reportMonthNumber,
                      isExpanded: true,
                      decoration: _inputDecoration(),
                      items: [
                        for (var month = 1; month <= 12; month++)
                          DropdownMenuItem(
                            value: month,
                            child: Text('$month 月'),
                          ),
                      ],
                      onChanged: _isLoading
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  _reportMonthNumber = value;
                                  _hasSearched = false;
                                  _summaryRows = const [];
                                });
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              const Text(
                '统计所选自然月，人员范围为当前应用可见范围内的全部成员。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ] else if (_mode == _WorkspaceMode.summary) ...[
              const SizedBox(height: 18),
              const _FieldLabel('年份'),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _summaryYear,
                isExpanded: true,
                decoration: _inputDecoration(),
                items: [
                  for (var year = DateTime.now().year; year >= 2018; year--)
                    DropdownMenuItem(value: year, child: Text('$year 年')),
                ],
                onChanged: _isLoading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _summaryYear = value;
                            _hasSearched = false;
                            _summaryRows = const [];
                          });
                        }
                      },
              ),
              const SizedBox(height: 9),
              const Text(
                '统计所选自然年，人员范围为当前应用可见范围内的全部成员。',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ] else ...[
              const SizedBox(height: 18),
              const _FieldLabel('日期范围'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '开始日期',
                      date: _allStartDate,
                      onTap: _isLoading
                          ? null
                          : () => _pickAllDate(isStart: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: _muted,
                    ),
                  ),
                  Expanded(
                    child: _DateField(
                      label: '结束日期',
                      date: _allEndDate,
                      onTap: _isLoading
                          ? null
                          : () => _pickAllDate(isStart: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isLoading ? null : _resetAllDateRange,
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('重置为全部日期'),
                ),
              ),
            ],
          ],
          if (isDetails) ...[
            const SizedBox(height: 18),
            const _FieldLabel('成员 UserID'),
            const SizedBox(height: 8),
            TextField(
              controller: _userIdsController,
              enabled: !_isLoading,
              minLines: 3,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              decoration: _inputDecoration(
                hintText: '例如：james, paul\n支持逗号、分号或换行分隔',
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '成员 UserID 留空时查询本地库中的全部成员。',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _InlineError(message: _errorMessage!),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: widget.config.isConfigured && !_isLoading
                ? isDetails
                      ? _search
                      : _loadLocalData
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : isDetails
                ? const Icon(Icons.search_rounded)
                : const Icon(Icons.storage_rounded),
            label: Text(
              _isLoading
                  ? isDetails
                        ? '正在读取本地记录…'
                        : '正在读取本地数据…'
                  : isDetails
                  ? '查询本地打卡记录'
                  : '查看本地汇总',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueryPanel() {
    final isDetails = _mode == _WorkspaceMode.details;
    return _SectionCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1100;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDetails)
                _buildCompactDetailFilters(compact)
              else
                _buildCompactAnalyticsFilters(compact),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _errorMessage!),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactDetailFilters(bool compact) {
    final typeField = _QueryField(
      label: '打卡类型',
      width: compact ? double.infinity : 180,
      child: DropdownButtonFormField<CheckinDataType>(
        initialValue: _dataType,
        isExpanded: true,
        decoration: _inputDecoration(),
        items: CheckinDataType.values
            .map(
              (type) => DropdownMenuItem(value: type, child: Text(type.label)),
            )
            .toList(growable: false),
        onChanged: _isLoading
            ? null
            : (value) {
                if (value != null) {
                  setState(() => _dataType = value);
                }
              },
      ),
    );
    final dateField = _QueryField(
      label: '查询日期',
      width: compact ? double.infinity : 350,
      child: Row(
        children: [
          Expanded(
            child: _DateField(
              label: '开始',
              date: _startDate,
              onTap: _isLoading ? null : () => _pickDate(isStart: true),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: TospinoHrColors.ink4,
            ),
          ),
          Expanded(
            child: _DateField(
              label: '结束',
              date: _endDate,
              onTap: _isLoading ? null : () => _pickDate(isStart: false),
            ),
          ),
        ],
      ),
    );
    final userField = _QueryField(
      label: '成员 UserID',
      width: compact ? double.infinity : null,
      child: TextField(
        controller: _userIdsController,
        enabled: !_isLoading,
        minLines: 1,
        maxLines: 2,
        keyboardType: TextInputType.multiline,
        decoration: _inputDecoration(hintText: '留空查询全部成员'),
      ),
    );
    final action = _buildQueryAction();
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          typeField,
          const SizedBox(height: 10),
          dateField,
          const SizedBox(height: 10),
          userField,
          const SizedBox(height: 12),
          action,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        typeField,
        const SizedBox(width: 10),
        dateField,
        const SizedBox(width: 10),
        Expanded(child: userField),
        const SizedBox(width: 10),
        SizedBox(width: 188, child: action),
      ],
    );
  }

  Widget _buildCompactAnalyticsFilters(bool compact) {
    if (!compact) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            flex: 5,
            child: _buildAnalyticsPeriodControls(false, includeAction: false),
          ),
          const SizedBox(width: 12),
          Flexible(flex: 4, child: _buildSummaryListFilters(false)),
          const SizedBox(width: 12),
          SizedBox(width: 188, child: _buildQueryAction()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAnalyticsPeriodControls(compact, includeAction: false),
        const SizedBox(height: 8),
        _buildSummaryListFilters(compact),
        const SizedBox(height: 8),
        _buildQueryAction(),
      ],
    );
  }

  Widget _buildAnalyticsPeriodControls(
    bool compact, {
    bool includeAction = true,
  }) {
    if (_mode == _WorkspaceMode.monthly) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: compact ? double.infinity : 170,
            child: DropdownButtonFormField<int>(
              initialValue: _reportYear,
              isExpanded: true,
              decoration: _inputDecoration(),
              items: [
                for (var year = DateTime.now().year; year >= 2018; year--)
                  DropdownMenuItem(value: year, child: Text('$year 年')),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _reportYear = value;
                          _hasSearched = false;
                          _summaryRows = const [];
                        });
                      }
                    },
            ),
          ),
          SizedBox(
            width: compact ? double.infinity : 170,
            child: DropdownButtonFormField<int>(
              initialValue: _reportMonthNumber,
              isExpanded: true,
              decoration: _inputDecoration(),
              items: [
                for (var month = 1; month <= 12; month++)
                  DropdownMenuItem(value: month, child: Text('$month 月')),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _reportMonthNumber = value;
                          _hasSearched = false;
                          _summaryRows = const [];
                        });
                      }
                    },
            ),
          ),
          if (includeAction)
            SizedBox(
              width: compact ? double.infinity : 188,
              child: _buildQueryAction(),
            ),
        ],
      );
    }
    if (_mode == _WorkspaceMode.summary) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          SizedBox(
            width: compact ? double.infinity : 220,
            child: DropdownButtonFormField<int>(
              initialValue: _summaryYear,
              isExpanded: true,
              decoration: _inputDecoration(),
              items: [
                for (var year = DateTime.now().year; year >= 2018; year--)
                  DropdownMenuItem(value: year, child: Text('$year 年')),
              ],
              onChanged: _isLoading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _summaryYear = value;
                          _hasSearched = false;
                          _summaryRows = const [];
                        });
                      }
                    },
            ),
          ),
          if (includeAction)
            SizedBox(
              width: compact ? double.infinity : 188,
              child: _buildQueryAction(),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: compact ? double.infinity : 390,
          child: Row(
            children: [
              Expanded(
                child: _DateField(
                  label: '开始',
                  date: _allStartDate,
                  onTap: _isLoading ? null : () => _pickAllDate(isStart: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: TospinoHrColors.ink4,
                ),
              ),
              Expanded(
                child: _DateField(
                  label: '结束',
                  date: _allEndDate,
                  onTap: _isLoading ? null : () => _pickAllDate(isStart: false),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: TextButton.icon(
            onPressed: _isLoading ? null : _resetAllDateRange,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('全部日期'),
          ),
        ),
        if (includeAction)
          SizedBox(
            width: compact ? double.infinity : 188,
            child: _buildQueryAction(),
          ),
      ],
    );
  }

  Widget _buildSummaryListFilters(bool compact) {
    final query = _summarySearchController.text;
    return Wrap(
      spacing: 10,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: compact ? double.infinity : 330,
          child: TextField(
            controller: _summarySearchController,
            decoration: InputDecoration(
              hintText: '成员筛选',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除筛选',
                      onPressed: () {
                        _summarySearchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildQueryAction() {
    final isDetails = _mode == _WorkspaceMode.details;
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : _search,
        style: FilledButton.styleFrom(
          backgroundColor: TospinoHrColors.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        icon: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                isDetails ? Icons.search_rounded : Icons.analytics_rounded,
                size: 18,
              ),
        label: Text(
          _isLoading
              ? '正在读取…'
              : isDetails
              ? '查询本地记录'
              : '查看本地汇总',
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    return switch (_mode) {
      _WorkspaceMode.details => _buildDetailResultPanel(),
      _WorkspaceMode.monthly => _buildMonthlyResultPanel(),
      _WorkspaceMode.summary => _buildSummaryResultPanel(),
      _WorkspaceMode.all => _buildAllTimeResultPanel(),
    };
  }

  Widget _buildDetailResultPanel() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeading(
                  icon: Icons.fact_check_outlined,
                  title: '查询结果',
                  subtitle: '数据按打卡时间倒序展示',
                ),
              ),
              if (_hasSearched && !_isLoading)
                Text(
                  '${DateFormat('MM-dd HH:mm').format(DateTime.now())} 更新',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
          if (_hasSearched) ...[
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final items = [
                  _MetricTile(
                    label: '打卡记录',
                    value: '$_totalRecordCount',
                    icon: Icons.done_all_rounded,
                    accent: _brandBlue,
                  ),
                  _MetricTile(
                    label: '涉及成员',
                    value: '$_totalMemberCount',
                    icon: Icons.groups_2_outlined,
                    accent: TospinoHrColors.success,
                  ),
                  _MetricTile(
                    label: '异常记录',
                    value: '$_totalExceptionCount',
                    icon: Icons.warning_amber_rounded,
                    accent: _totalExceptionCount == 0
                        ? TospinoHrColors.success
                        : TospinoHrColors.brand,
                  ),
                ];
                if (compact) {
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        items[i],
                        if (i != items.length - 1) const SizedBox(height: 9),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(child: items[i]),
                      if (i != items.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          if (_isLoading)
            const _LoadingState()
          else if (!_hasSearched)
            const _EmptyState(
              icon: Icons.manage_search_rounded,
              title: '填写条件后开始查询',
              description: '查询结果将在这里按时间线展示，便于核对考勤异常。',
            )
          else if (_records.isEmpty)
            const _EmptyState(
              icon: Icons.event_available_rounded,
              title: '没有查到打卡记录',
              description: '请确认日期范围，或前往设置同步打卡记录。',
            )
          else
            Column(
              children: [
                for (var i = 0; i < _records.length; i++) ...[
                  _RecordCard(record: _records[i]),
                  if (i != _records.length - 1) const SizedBox(height: 11),
                ],
                if (_records.length < _totalRecordCount) ...[
                  const SizedBox(height: 14),
                  Text(
                    '已显示 ${_records.length} / $_totalRecordCount 条',
                    style: TospinoHrText.meta,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _isLoadingMoreRecords
                          ? null
                          : _loadMoreRecords,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TospinoHrColors.ink,
                        side: const BorderSide(color: TospinoHrColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: _isLoadingMoreRecords
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded, size: 19),
                      label: const Text('加载更多本地记录'),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMonthlyResultPanel() {
    return _buildAnalyticsResultPanel(
      title: '月度考勤汇总',
      subtitle: '从所选范围逐月汇总，首条记录视为该成员的统计起点',
      icon: Icons.calendar_view_month_outlined,
      periodColumnLabel: '月份',
      showYearFilter: false,
    );
  }

  Widget _buildSummaryResultPanel() {
    return _buildAnalyticsResultPanel(
      title: '分年考勤汇总',
      subtitle: '同一成员同一年度合并，底部合计随筛选更新',
      icon: Icons.table_chart_outlined,
      periodColumnLabel: '年份',
      showYearFilter: false,
    );
  }

  Widget _buildAllTimeResultPanel() {
    return _buildAnalyticsResultPanel(
      title: '历史打卡汇总',
      subtitle: '按所选日期精确汇总所有成员的打卡明细',
      icon: Icons.history_outlined,
      periodColumnLabel: '范围',
      showYearFilter: false,
    );
  }

  Widget _buildAnalyticsResultPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required String periodColumnLabel,
    bool showYearFilter = true,
    bool showSourceRecordColumn = false,
    List<AttendanceMetric>? visibleMetrics,
  }) {
    final totalExceptionDays = _summaryRows.fold<double>(
      0,
      (total, row) => total + row.valueOf(AttendanceMetric.exceptionDays),
    );
    final totalCheckinRecords = _summaryRows.fold<double>(
      0,
      (total, row) => total + row.valueOf(AttendanceMetric.checkinRecordCount),
    );
    final memberCount = _summaryRows
        .map((row) => row.userId.isEmpty ? row.name : row.userId)
        .toSet()
        .length;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SectionHeading(
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                ),
              ),
              if (_hasSearched && !_isLoading)
                Text(
                  '${DateFormat('MM-dd HH:mm').format(DateTime.now())} 更新',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
          if (_hasSearched) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 560;
                final items = [
                  _MetricTile(
                    label: '汇总行',
                    value: '${_summaryRows.length}',
                    icon: Icons.table_rows_rounded,
                    accent: _brandBlue,
                  ),
                  _MetricTile(
                    label: '涉及成员',
                    value: '$memberCount',
                    icon: Icons.groups_2_outlined,
                    accent: TospinoHrColors.success,
                  ),
                  _MetricTile(
                    label: '打卡记录',
                    value: _formatSummaryNumber(totalCheckinRecords, 0),
                    icon: Icons.fact_check_outlined,
                    accent: TospinoHrColors.info,
                  ),
                  _MetricTile(
                    label: '异常天数合计',
                    value: _formatSummaryNumber(totalExceptionDays, 0),
                    icon: Icons.warning_amber_rounded,
                    accent: totalExceptionDays == 0
                        ? TospinoHrColors.success
                        : TospinoHrColors.brand,
                  ),
                ];
                if (compact) {
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        items[i],
                        if (i != items.length - 1) const SizedBox(height: 9),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: (constraints.maxWidth - 30) / 4,
                        child: item,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 70),
              child: Column(
                children: [
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _summaryProgress ?? '正在读取 TiDB 数据…',
                    textAlign: TextAlign.center,
                    style: TospinoHrText.meta,
                  ),
                ],
              ),
            )
          else if (!_hasSearched)
            const _EmptyState(
              icon: Icons.table_chart_rounded,
              title: '选择范围后开始统计',
              description: '请先在设置中同步打卡记录，再查看离线统计结果。',
            )
          else if (_summaryRows.isEmpty)
            const _EmptyState(
              icon: Icons.event_busy_rounded,
              title: '没有查到汇总数据',
              description: '请检查年月范围和成员权限，或前往设置重新获取打卡记录。',
            )
          else
            AttendanceSummaryTable(
              rows: _summaryRows,
              query: _summarySearchController.text,
              periodColumnLabel: periodColumnLabel,
              showYearFilter: showYearFilter,
              showSourceRecordColumn: showSourceRecordColumn,
              visibleMetrics: visibleMetrics,
            ),
        ],
      ),
    );
  }

  String _formatSummaryNumber(double value, int decimalPlaces) {
    if (decimalPlaces == 0) {
      return value.round().toString();
    }
    return value.toStringAsFixed(decimalPlaces);
  }

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TospinoHrText.meta.copyWith(color: TospinoHrColors.ink4),
      filled: true,
      fillColor: TospinoHrColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _brandBlue, width: 1.2),
        borderRadius: BorderRadius.circular(14),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: isStart ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _errorMessage = null;
    });
  }

  Future<void> _pickAllDate({required bool isStart}) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _allStartDate : _allEndDate,
      firstDate: _allEarliestDate,
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: isStart ? '选择开始日期' : '选择结束日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _allDateRangeAuto = false;
      if (isStart) {
        _allStartDate = picked;
        if (_allEndDate.isBefore(picked)) {
          _allEndDate = picked;
        }
      } else {
        _allEndDate = picked;
        if (picked.isBefore(_allStartDate)) {
          _allStartDate = picked;
        }
      }
      _errorMessage = null;
    });
    await _loadLocalData();
  }

  Future<void> _resetAllDateRange() async {
    setState(() => _allDateRangeAuto = true);
    await _loadLocalData();
  }

  Future<void> _search() {
    if (_mode == _WorkspaceMode.details) {
      return _searchDetails();
    }
    return _loadLocalData();
  }

  Future<void> _searchDetails() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final userIds = _parseUserIds(_userIdsController.text);
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day);
    if (start.isAfter(end)) {
      setState(() => _errorMessage = '开始日期不能晚于结束日期');
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
      _records = const [];
      _totalRecordCount = 0;
      _totalMemberCount = 0;
      _totalExceptionCount = 0;
    });
    try {
      await _ensureDatabaseConnection();
      final page = await _database.loadCheckinRecords(
        startDate: start,
        endDate: end,
        dataType: _dataType,
        userIds: userIds.toSet(),
        limit: _checkinPageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records = page.records;
        _totalRecordCount = page.totalCount;
        _totalMemberCount = page.totalUserCount;
        _totalExceptionCount = page.totalExceptionCount;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _records = const [];
        _totalRecordCount = 0;
        _totalMemberCount = 0;
        _totalExceptionCount = 0;
        _errorMessage = '读取本地打卡明细失败：$error';
      });
      _showOperationPrompt('读取本地打卡明细失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMoreRecords() async {
    if (_isLoadingMoreRecords || _records.length >= _totalRecordCount) {
      return;
    }
    final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final end = DateTime(_endDate.year, _endDate.month, _endDate.day);
    setState(() => _isLoadingMoreRecords = true);
    try {
      await _ensureDatabaseConnection();
      final page = await _database.loadCheckinRecords(
        startDate: start,
        endDate: end,
        dataType: _dataType,
        userIds: _parseUserIds(_userIdsController.text).toSet(),
        limit: _checkinPageSize,
        offset: _records.length,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records = [..._records, ...page.records];
        _totalRecordCount = page.totalCount;
        _totalMemberCount = page.totalUserCount;
        _totalExceptionCount = page.totalExceptionCount;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = '加载更多打卡明细失败：$error');
        _showOperationPrompt('加载更多打卡明细失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreRecords = false);
      }
    }
  }

  Future<void> _loadLocalData({bool showLoading = true}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final userIds = <String>[];
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _hasSearched = true;
        _errorMessage = null;
        _summaryProgress = '正在读取 TiDB 数据…';
      });
    }
    try {
      if (mounted) {
        setState(() => _summaryProgress = '正在检测 TiDB 连接…');
      }
      await _ensureDatabaseConnection();
      if (_mode == _WorkspaceMode.all && _allDateRangeAuto) {
        final bounds = await _database.loadCheckinDateBounds();
        if (bounds != null && mounted) {
          final today = DateTime.now();
          setState(() {
            _allEarliestDate = bounds.firstDate;
            _allStartDate = bounds.firstDate;
            _allEndDate = DateTime(today.year, today.month, today.day);
          });
        }
      }
      final (start, end) = _analyticsRange();
      final rows = await _loadAnalyticsRows(
        database: _database,
        start: start,
        end: end,
        userIds: userIds.toSet(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _summaryRows = rows;
        _summaryProgress = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _summaryProgress = null;
        _errorMessage = '读取本地考勤数据失败：$error';
      });
      _showOperationPrompt('读取本地考勤数据失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _syncAllData(
    AttendanceSyncMode mode, {
    ValueChanged<String>? onProgress,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    var syncStart = DateTime(2018);
    DateTime? incrementalStart;
    final syncEnd = DateTime(now.year, now.month);

    var userIds = <String>[];
    void updateProgress(String message) {
      if (mounted) {
        setState(() => _summaryProgress = message);
      }
      onProgress?.call(message);
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
    });
    updateProgress('正在加载应用可见范围内的全部成员…');

    try {
      updateProgress('正在检测企业微信连接…');
      final wecomStatus = await _apiClient.checkConnection();
      if (!wecomStatus.connected) {
        throw WeComException(wecomStatus.message);
      }
      updateProgress('正在检测 TiDB 连接…');
      final databaseStatus = await _database.checkConnection();
      if (!databaseStatus.connected) {
        throw StateError(databaseStatus.message);
      }
      if (mode == AttendanceSyncMode.incremental) {
        final latestCheckinAt = await _database.loadLatestCheckinTime();
        if (latestCheckinAt != null) {
          incrementalStart = DateTime(
            latestCheckinAt.year,
            latestCheckinAt.month,
            latestCheckinAt.day >= 16 ? 16 : 1,
          );
          syncStart = DateTime(latestCheckinAt.year, latestCheckinAt.month);
          updateProgress(
            '数据库最新打卡：'
            '${DateFormat('yyyy-MM-dd HH:mm:ss').format(latestCheckinAt)}，'
            '从 ${DateFormat('yyyy-MM-dd').format(incrementalStart)} 开始增量',
          );
        } else {
          updateProgress('数据库暂无打卡记录，增量将补全历史数据…');
        }
      }
      userIds = await _resolveAnalyticsUserIds(userIds);

      final result = await _syncService.syncAll(
        firstMonth: syncStart,
        lastMonth: syncEnd,
        userIds: userIds,
        startAt: incrementalStart,
        mode: mode,
        onProgress: (progress) {
          updateProgress(progress.message);
        },
      );
      if (_mode == _WorkspaceMode.all && _allDateRangeAuto) {
        final bounds = await _database.loadCheckinDateBounds();
        if (bounds != null && mounted) {
          setState(() {
            _allEarliestDate = bounds.firstDate;
            _allStartDate = bounds.firstDate;
            _allEndDate = DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            );
          });
        }
      }
      final (viewStart, viewEnd) = _analyticsRange();
      final rows = await _loadAnalyticsRows(
        database: _database,
        start: viewStart,
        end: viewEnd,
        userIds: const {},
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _summaryRows = rows;
        _summaryProgress = null;
      });
      updateProgress(
        '${mode == AttendanceSyncMode.full ? '全量' : '增量'}同步完成：'
        '${result.userCount} 名成员，'
        '${result.checkinRecordCount} 条明细，'
        '${result.windowCount} 个周期',
      );
      return true;
    } on WeComException catch (error) {
      updateProgress('同步失败：${error.message}');
      if (mounted) {
        setState(() {
          _summaryProgress = null;
          _errorMessage = error.toString();
        });
      }
      return false;
    } catch (error) {
      updateProgress('同步失败：$error');
      if (mounted) {
        setState(() {
          _summaryProgress = null;
          _errorMessage = '同步失败：$error';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<SyncApiExecution> _handleApiSync(RemoteSyncMode remoteMode) async {
    if (_apiSyncInProgress) {
      return const SyncApiExecution(
        statusCode: 409,
        success: false,
        message: '已有同步任务正在执行，请稍后重试',
      );
    }
    _apiSyncInProgress = true;
    var lastMessage = '';
    try {
      final mode = remoteMode == RemoteSyncMode.full
          ? AttendanceSyncMode.full
          : AttendanceSyncMode.incremental;
      final success = await _syncAllData(
        mode,
        onProgress: (message) => lastMessage = message,
      );
      return SyncApiExecution(
        statusCode: success ? 200 : 500,
        success: success,
        message: lastMessage.isEmpty
            ? success
                  ? '同步完成'
                  : '同步失败'
            : lastMessage,
      );
    } finally {
      _apiSyncInProgress = false;
    }
  }

  Future<List<AttendanceSummaryRow>> _loadAnalyticsRows({
    required AttendanceDatabase database,
    required DateTime start,
    required DateTime end,
    required Set<String> userIds,
  }) {
    return switch (_mode) {
      _WorkspaceMode.monthly => database.loadRawMonthlySummary(
        firstMonth: start,
        lastMonth: end,
        userIds: userIds,
      ),
      _WorkspaceMode.summary => database.loadRawYearSummary(
        firstYear: start.year,
        lastYear: end.year,
        userIds: userIds,
      ),
      _WorkspaceMode.all => database.loadRawAllTimeSummary(
        startDate: start,
        endDate: end,
        userIds: userIds,
      ),
      _WorkspaceMode.details => Future.value(const []),
    };
  }

  (DateTime, DateTime) _analyticsRange() {
    return switch (_mode) {
      _WorkspaceMode.monthly => (
        DateTime(_reportYear, _reportMonthNumber),
        DateTime(_reportYear, _reportMonthNumber),
      ),
      _WorkspaceMode.summary => (
        DateTime(_summaryYear),
        DateTime(_summaryYear, 12),
      ),
      _WorkspaceMode.all => (_allStartDate, _allEndDate),
      _WorkspaceMode.details => (
        DateTime(_startDate.year, _startDate.month),
        DateTime(_endDate.year, _endDate.month),
      ),
    };
  }

  Future<List<String>> _resolveAnalyticsUserIds(
    List<String> requestedUserIds,
  ) async {
    if (requestedUserIds.isNotEmpty) {
      return requestedUserIds;
    }
    if (_members.isEmpty) {
      _members = await _apiClient.getMemberIdList();
    }
    final userIds = _members.map((member) => member.userId).toList();
    if (userIds.isEmpty) {
      throw const WeComException('应用可见范围内没有可统计的成员');
    }
    return userIds;
  }

  Future<void> _ensureDatabaseConnection() async {
    final status = await _database.checkConnection();
    if (!status.connected) {
      throw StateError(status.message);
    }
  }

  void _showOperationPrompt(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> _parseUserIds(String raw) {
    final seen = <String>{};
    return raw
        .split(RegExp(r'[,，;；\s]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .toList();
  }

  void _showSettingsDialog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          config: widget.config,
          database: _database,
          onSync: (mode, onProgress) {
            return _syncAllData(mode, onProgress: onProgress);
          },
          onCheckWeCom: _apiClient.checkConnection,
          syncApiServer: _syncApiServer,
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _confirmFullSync() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var matches = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('确认全量获取'),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '全量获取会重新拉取全部成员从 2018-01 至当前月份的打卡记录，'
                    '耗时较长，执行期间不能关闭进度窗口或离开页面。',
                    style: TextStyle(height: 1.55),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '请原样输入以下文案以继续：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 7),
                  SelectableText(
                    _fullSyncConfirmation,
                    style: const TextStyle(
                      color: Color(0xFFB64E22),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: _inputDecoration(hintText: '输入确认文案'),
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
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (confirmed == true && mounted) {
      await _runSyncMode(AttendanceSyncMode.full);
    }
  }

  Future<void> _runSyncMode(AttendanceSyncMode mode) async {
    final progress = ValueNotifier<String>(
      mode == AttendanceSyncMode.full ? '正在准备全量获取…' : '正在准备增量获取…',
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(
            mode == AttendanceSyncMode.full ? '正在全量获取打卡记录' : '正在增量获取打卡记录',
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
                      color: Color(0xFFB64E22),
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
    final succeeded = await _syncAllData(
      mode,
      onProgress: (message) => progress.value = message,
    );
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (navigator.canPop()) {
      navigator.pop();
    }
    progress.dispose();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? '${mode == AttendanceSyncMode.full ? '全量' : '增量'}获取已完成'
                : '打卡记录获取失败，请查看页面错误提示',
          ),
        ),
      );
    }
  }

  // ignore: unused_element
  void _showConfigDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('企业微信配置'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConfigLine(
                  label: '企业ID',
                  value: widget.config.maskedCorpId,
                  configured: widget.config.corpId.isNotEmpty,
                ),
                _ConfigLine(
                  label: 'AgentId',
                  value: widget.config.maskedAgentId,
                  configured: widget.config.agentId.isNotEmpty,
                ),
                _ConfigLine(
                  label: 'Secret',
                  value: widget.config.hasCheckinSecret ? '已安全加载' : '未配置',
                  configured: widget.config.hasCheckinSecret,
                ),
                _ConfigLine(
                  label: '通讯录Secret（可选）',
                  value: widget.config.hasContactSecret
                      ? '已安全加载'
                      : '未配置，使用应用可见范围',
                  configured: widget.config.hasContactSecret,
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '配置方式',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const SelectableText(
                  '1. 编辑 config/app.local.yaml\n'
                  '2. 在 wecom 和 database 节点填写配置\n'
                  '3. 运行 dart run tool/dart_defines.dart，'
                  '再使用 .dart_tool/local_dart_defines.json 启动或构建',
                  style: TextStyle(height: 1.6, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '通讯录同步 Secret 是可选配置；企业使用第三方通讯录同步时，'
                    '应用会自动改用当前自建应用的可见范围。'
                    '凭据会被编译进客户端，只适合内部调试。'
                    '生产环境建议将企业微信请求放到服务端代理。',
                    style: TextStyle(
                      color: Color(0xFF79551C),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _TospinoLogoMark extends StatelessWidget {
  const _TospinoLogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: TospinoHrColors.surface,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: TospinoHrColors.line),
        boxShadow: TospinoHrShadows.card,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.45,
            child: Container(
              width: size * 0.52,
              height: size * 0.23,
              decoration: BoxDecoration(
                color: TospinoHrColors.ink,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Positioned(
            bottom: size * 0.17,
            child: Container(
              width: size * 0.56,
              height: size * 0.18,
              decoration: BoxDecoration(
                color: TospinoHrColors.brandLight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
              Text(
                title,
                style: TospinoHrText.cardTitle.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: TospinoHrText.meta),
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TospinoHrText.eyebrow.copyWith(
        color: TospinoHrColors.ink3,
        letterSpacing: 0.2,
        fontSize: 11,
      ),
    );
  }
}

class _QueryField extends StatelessWidget {
  const _QueryField({required this.label, required this.child, this.width});

  final String label;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [_FieldLabel(label), const SizedBox(height: 6), child],
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TospinoHrColors.surfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TospinoHrText.meta.copyWith(fontSize: 10)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 15,
                    color: TospinoHrColors.ink4,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(date),
                      style: TospinoHrText.body.copyWith(
                        color: TospinoHrColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TospinoHrColors.dangerTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TospinoHrColors.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: TospinoHrColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TospinoHrText.meta.copyWith(
                color: TospinoHrColors.danger,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigStatusChip extends StatelessWidget {
  const _ConfigStatusChip({required this.isConfigured});

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfigured ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isConfigured ? '配置已完成' : '等待配置',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TospinoHrText.number.copyWith(fontSize: 19)),
              const SizedBox(height: 5),
              Text(label, style: TospinoHrText.meta.copyWith(fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 70),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('正在从企业微信获取数据…', style: TospinoHrText.meta),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 58, horizontal: 18),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: TospinoHrColors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 27, color: TospinoHrColors.ink4),
          ),
          const SizedBox(height: 17),
          Text(title, style: TospinoHrText.cardTitle),
          const SizedBox(height: 7),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TospinoHrText.meta,
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final CheckinRecord record;

  @override
  Widget build(BuildContext context) {
    final statusColor = record.hasException
        ? TospinoHrColors.danger
        : TospinoHrColors.success;
    final statusBackground = record.hasException
        ? TospinoHrColors.dangerTint
        : TospinoHrColors.successTint;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TospinoHrColors.surface,
        border: Border.all(color: TospinoHrColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: TospinoHrColors.brandTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    record.userId.isEmpty
                        ? '?'
                        : record.userId.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: TospinoHrColors.brand,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        Text(record.userId, style: TospinoHrText.cardTitle),
                        _MiniBadge(
                          text: record.checkinType.isEmpty
                              ? '打卡'
                              : record.checkinType,
                          color: TospinoHrColors.brand,
                          background: TospinoHrColors.brandTint,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      record.formattedCheckinTime,
                      style: TospinoHrText.meta.copyWith(
                        color: TospinoHrColors.ink2,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              _MiniBadge(
                text: record.hasException ? '异常' : '正常',
                color: statusColor,
                background: statusBackground,
              ),
            ],
          ),
          if (record.exceptionType.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              record.exceptionType,
              style: TospinoHrText.body.copyWith(
                color: TospinoHrColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_hasDetail(record)) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (record.groupName.isNotEmpty)
                  _InfoPill(
                    icon: Icons.rule_folder_outlined,
                    text: record.groupName,
                  ),
                if (record.locationTitle.isNotEmpty)
                  _InfoPill(
                    icon: Icons.location_on_outlined,
                    text: record.locationTitle,
                  ),
                if (record.wifiName.isNotEmpty)
                  _InfoPill(icon: Icons.wifi_rounded, text: record.wifiName),
                if (record.formattedScheduleTime.isNotEmpty)
                  _InfoPill(
                    icon: Icons.schedule_rounded,
                    text: '标准 ${record.formattedScheduleTime}',
                  ),
                if (record.notes.isNotEmpty)
                  _InfoPill(icon: Icons.notes_rounded, text: record.notes),
              ],
            ),
            if (record.locationDetail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                record.locationDetail,
                style: const TextStyle(
                  color: Color(0xFF768297),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
            if (record.coordinates != null) ...[
              const SizedBox(height: 7),
              Text(
                '坐标 ${record.coordinates}',
                style: const TextStyle(color: Color(0xFF929CAE), fontSize: 10),
              ),
            ],
          ],
        ],
      ),
    );
  }

  bool _hasDetail(CheckinRecord record) {
    return record.groupName.isNotEmpty ||
        record.locationTitle.isNotEmpty ||
        record.wifiName.isNotEmpty ||
        record.notes.isNotEmpty ||
        record.locationDetail.isNotEmpty ||
        record.formattedScheduleTime.isNotEmpty;
  }
}

// Kept for compact single-member report rendering in custom integrations.
// ignore: unused_element
class _MonthlyReportCard extends StatelessWidget {
  const _MonthlyReportCard({required this.report});

  final MonthlyReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8EDF4)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEAF2FF), Color(0xFFF2F7FF)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    report.displayName.isEmpty
                        ? '?'
                        : report.displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF1677FF),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          report.displayName,
                          style: const TextStyle(
                            color: Color(0xFF17223B),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (report.baseInfo.accountId.isNotEmpty)
                          _MiniBadge(
                            text: report.baseInfo.accountId,
                            color: const Color(0xFF1677FF),
                            background: const Color(0xFFEAF2FF),
                          ),
                      ],
                    ),
                    if (report.baseInfo.departmentsName.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        report.baseInfo.departmentsName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF65728A),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (report.baseInfo.groupName.isNotEmpty)
                _MiniBadge(
                  text: report.baseInfo.groupName,
                  color: const Color(0xFF53647D),
                  background: const Color(0xFFF2F5F9),
                ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ReportStat(label: '应出勤', value: '${summary.workDays} 天'),
              _ReportStat(label: '正常', value: '${summary.regularDays} 天'),
              _ReportStat(label: '休息', value: '${summary.restDays} 天'),
              _ReportStat(
                label: '异常',
                value: '${summary.exceptionDays} 天',
                warning: summary.exceptionDays > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: Color(0xFF65728A),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '实际工时 ${summary.regularWorkText}'
                    ' / 标准 ${summary.standardWorkText}',
                    style: const TextStyle(
                      color: Color(0xFF536078),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (report.exceptions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _ReportSubTitle('异常统计'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in report.exceptions)
                  _ReportDetailChip(
                    text:
                        '${item.label} ${item.count} 次'
                        '${item.durationSeconds > 0 ? ' · ${formatWorkDuration(item.durationSeconds)}' : ''}',
                    warning: true,
                  ),
              ],
            ),
          ],
          if (report.specialItems.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _ReportSubTitle('假勤统计'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in report.specialItems)
                  _ReportDetailChip(
                    text:
                        '${item.label} ${item.count} 次'
                        '${item.durationText.isEmpty ? '' : ' · ${item.durationText}'}',
                  ),
              ],
            ),
          ],
          if (report.overwork != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF8F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.more_time_rounded,
                    size: 17,
                    color: Color(0xFF087D61),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '加班合计 ${report.overwork!.totalText}',
                    style: const TextStyle(
                      color: Color(0xFF087D61),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '工作日 ${formatWorkDuration(report.overwork!.workdaySeconds)}',
                    style: const TextStyle(
                      color: Color(0xFF5B756F),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  const _ReportStat({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF2ED) : const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: const TextStyle(color: Color(0xFF778398), fontSize: 10),
          ),
          Text(
            value,
            style: TextStyle(
              color: warning
                  ? const Color(0xFFC85B31)
                  : const Color(0xFF33415C),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSubTitle extends StatelessWidget {
  const _ReportSubTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF45536B),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ReportDetailChip extends StatelessWidget {
  const _ReportDetailChip({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF3EF) : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: warning ? const Color(0xFFB84F2D) : const Color(0xFF5D6A80),
          fontSize: 10,
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: TospinoHrColors.surfaceMuted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: TospinoHrColors.ink4),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TospinoHrText.meta.copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigLine extends StatelessWidget {
  const _ConfigLine({
    required this.label,
    required this.value,
    required this.configured,
  });

  final String label;
  final String value;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: TospinoHrText.meta)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(
            configured ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18,
            color: configured
                ? const Color(0xFF0B9471)
                : const Color(0xFFC45945),
          ),
        ],
      ),
    );
  }
}
