import 'package:material_ui/material_ui.dart';

import '../data/attendance_summary.dart';
import '../theme/tospino_hr_style.dart';

class AttendanceSummaryTable extends StatefulWidget {
  const AttendanceSummaryTable({
    super.key,
    required this.rows,
    this.periodColumnLabel = '年份',
    this.showYearFilter = true,
    this.showSourceRecordColumn = false,
    this.visibleMetrics,
    this.query = '',
  });

  final List<AttendanceSummaryRow> rows;
  final String periodColumnLabel;
  final bool showYearFilter;
  final bool showSourceRecordColumn;
  final List<AttendanceMetric>? visibleMetrics;
  final String query;

  @override
  State<AttendanceSummaryTable> createState() => _AttendanceSummaryTableState();
}

class _AttendanceSummaryTableState extends State<AttendanceSummaryTable> {
  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim().toLowerCase();
    final filteredRows = widget.rows
        .where((row) {
          return query.isEmpty || row.searchableText.contains(query);
        })
        .toList(growable: false);

    final metrics = widget.visibleMetrics ?? _compactMetrics;
    final totals = <AttendanceMetric, double>{
      for (final metric in metrics)
        metric: filteredRows.fold<double>(
          0,
          (total, row) => total + row.valueOf(metric),
        ),
    };
    final sourceRecordTotal = filteredRows.fold<int>(
      0,
      (total, row) => total + row.sourceRecordCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '实际出勤天数按真实上下班打卡的唯一日期计算，已排除企业微信标记为'
          '“未打卡”的排班占位记录；原始接口不含完整排班，因此不推算应出勤天数。'
          '点击姓名可查看全部 SQL 统计明细。',
          style: TospinoHrText.meta,
        ),
        const SizedBox(height: 14),
        if (filteredRows.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
            decoration: BoxDecoration(
              color: TospinoHrColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '当前筛选条件下没有汇总记录',
              textAlign: TextAlign.center,
              style: TospinoHrText.meta,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: TospinoHrColors.surface,
              border: Border.all(color: TospinoHrColors.line),
              borderRadius: BorderRadius.circular(16),
              boxShadow: TospinoHrShadows.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        TospinoHrColors.ink,
                      ),
                      dataRowColor: WidgetStateProperty.resolveWith((states) {
                        final index = states.contains(WidgetState.selected)
                            ? 1
                            : 0;
                        return index.isEven
                            ? TospinoHrColors.surface
                            : TospinoHrColors.background;
                      }),
                      headingTextStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      dataTextStyle: const TextStyle(
                        color: TospinoHrColors.ink2,
                        fontSize: 11,
                      ),
                      headingRowHeight: 58,
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: 52,
                      horizontalMargin: 8,
                      columnSpacing: 8,
                      border: const TableBorder(
                        horizontalInside: BorderSide(
                          color: TospinoHrColors.lineSoft,
                        ),
                      ),
                      columns: _columns,
                      rows: [
                        for (
                          var index = 0;
                          index < filteredRows.length;
                          index++
                        )
                          _dataRow(filteredRows[index], index),
                        _totalRow(
                          filteredRows.length,
                          sourceRecordTotal,
                          totals,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  List<DataColumn> get _columns => [
    _textColumn(widget.periodColumnLabel, 116),
    _textColumn('成员', 112),
    _textColumn('所属规则', 144),
    if (widget.showSourceRecordColumn) _numberColumn('源记录数', 72),
    for (final metric in visibleMetrics)
      _numberColumn(metric.label, _metricWidth(metric)),
  ];

  List<AttendanceMetric> get visibleMetrics =>
      widget.visibleMetrics ?? _compactMetrics;

  static const _compactMetrics = [
    AttendanceMetric.checkinRecordCount,
    AttendanceMetric.attendanceDays,
    AttendanceMetric.normalAttendanceDays,
    AttendanceMetric.exceptionDays,
    AttendanceMetric.regularWorkHours,
    AttendanceMetric.exceptionCount,
    AttendanceMetric.timeExceptionCount,
    AttendanceMetric.notCheckedInCount,
  ];

  static const _sqlDetailMetrics = [
    AttendanceMetric.checkinRecordCount,
    AttendanceMetric.attendanceDays,
    AttendanceMetric.normalAttendanceDays,
    AttendanceMetric.exceptionDays,
    AttendanceMetric.exceptionCount,
    AttendanceMetric.regularWorkHours,
    AttendanceMetric.timeExceptionCount,
    AttendanceMetric.notCheckedInCount,
    AttendanceMetric.locationExceptionCount,
    AttendanceMetric.wifiExceptionCount,
    AttendanceMetric.deviceExceptionCount,
  ];

  DataColumn _textColumn(String label, double width) {
    return DataColumn(
      label: SizedBox(
        width: width,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  DataColumn _numberColumn(String label, double width) {
    return DataColumn(
      numeric: true,
      label: SizedBox(
        width: width,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  DataRow _dataRow(AttendanceSummaryRow row, int index) {
    return DataRow(
      color: WidgetStateProperty.all(
        index.isEven ? TospinoHrColors.surface : TospinoHrColors.background,
      ),
      cells: [
        _textCell(row.periodLabel),
        _memberCell(row),
        _textCell(row.ruleNames),
        if (widget.showSourceRecordColumn)
          _numberCell('${row.sourceRecordCount}'),
        for (final metric in visibleMetrics)
          _numberCell(_formatMetric(row.valueOf(metric), metric)),
      ],
    );
  }

  DataRow _totalRow(
    int visibleRowCount,
    int sourceRecordTotal,
    Map<AttendanceMetric, double> totals,
  ) {
    return DataRow(
      color: WidgetStateProperty.all(TospinoHrColors.brandTint),
      cells: [
        _textCell('合计', bold: true),
        _textCell('$visibleRowCount 条', bold: true),
        _textCell('随筛选更新', bold: true),
        if (widget.showSourceRecordColumn)
          _numberCell('$sourceRecordTotal', bold: true),
        for (final metric in visibleMetrics)
          _numberCell(_formatMetric(totals[metric] ?? 0, metric), bold: true),
      ],
    );
  }

  DataCell _memberCell(AttendanceSummaryRow row) {
    return DataCell(
      TextButton(
        onPressed: () => _showRecordDetail(row),
        style: TextButton.styleFrom(
          foregroundColor: TospinoHrColors.brand,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.centerLeft,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (row.userId.isNotEmpty && row.userId != row.name)
              Text(
                row.userId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TospinoHrText.meta.copyWith(fontSize: 9),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRecordDetail(AttendanceSummaryRow row) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${row.periodLabel} · ${row.name}'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 7,
                  children: [
                    _DetailIdentity(label: '账号', value: row.userId),
                    _DetailIdentity(label: '所属规则', value: row.ruleNames),
                    _DetailIdentity(label: '部门', value: row.departments),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 600
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final metric in _sqlDetailMetrics)
                          SizedBox(
                            width: width,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: TospinoHrColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    metric.label,
                                    style: TospinoHrText.meta.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _formatMetric(row.valueOf(metric), metric),
                                    style: TospinoHrText.number.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
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

  DataCell _textCell(String value, {bool bold = false}) {
    return DataCell(
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: TospinoHrColors.ink2,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  DataCell _numberCell(String value, {bool bold = false}) {
    return DataCell(
      Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(
          color: TospinoHrColors.ink2,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  String _formatMetric(double value, AttendanceMetric metric) {
    if (metric.decimalPlaces == 0) {
      return value.round().toString();
    }
    return value.toStringAsFixed(metric.decimalPlaces);
  }

  double _metricWidth(AttendanceMetric _) {
    return 92;
  }
}

class _DetailIdentity extends StatelessWidget {
  const _DetailIdentity({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TospinoHrText.meta,
        children: [
          TextSpan(text: '$label：'),
          TextSpan(
            text: value,
            style: TospinoHrText.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
