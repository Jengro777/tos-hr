import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/wecom_config.dart';
import '../data/checkin_record.dart';
import '../data/connection_status.dart';
import '../data/monthly_report.dart';
import '../data/wecom_exception.dart';
import '../data/wecom_member.dart';

class WeComApiClient {
  WeComApiClient({
    required this.config,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _httpClient = httpClient ?? http.Client();

  static final Uri _apiBase = Uri.https('qyapi.weixin.qq.com', '/');
  static const Set<int> _tokenErrorCodes = {40014, 42001};
  static const Duration _tokenSafetyWindow = Duration(minutes: 5);

  final WecomConfig config;
  final http.Client _httpClient;
  final Duration requestTimeout;

  final _TokenManager _applicationTokens = _TokenManager();
  final _TokenManager _contactTokens = _TokenManager();

  Future<ConnectionStatus> checkConnection() async {
    final checkedAt = DateTime.now();
    if (!config.isConfigured) {
      return ConnectionStatus(
        connected: false,
        message: '企业微信配置不完整：${config.missingCheckinFields.join('、')}',
        checkedAt: checkedAt,
      );
    }
    final startedAt = DateTime.now();
    try {
      _applicationTokens.invalidate();
      await _applicationTokens.getToken(
        () => _fetchAccessToken(secret: config.secret),
      );
      return ConnectionStatus(
        connected: true,
        message: '企业微信连接与鉴权正常',
        checkedAt: checkedAt,
        latency: DateTime.now().difference(startedAt),
      );
    } on WeComException catch (error) {
      return ConnectionStatus(
        connected: false,
        message: '企业微信连接失败：${error.message}',
        checkedAt: checkedAt,
      );
    } catch (error) {
      return ConnectionStatus(
        connected: false,
        message: '企业微信连接失败：$error',
        checkedAt: checkedAt,
      );
    }
  }

  Future<List<CheckinRecord>> getCheckinData({
    required CheckinDataType dataType,
    required DateTime start,
    required DateTime end,
    required List<String> userIds,
  }) async {
    _validateRequest(start: start, end: end, userIds: userIds);
    try {
      final body = jsonEncode({
        'opencheckindatatype': dataType.apiValue,
        'starttime': start.millisecondsSinceEpoch ~/ 1000,
        'endtime': end.millisecondsSinceEpoch ~/ 1000,
        'useridlist': userIds,
      });

      final response = await _requestCheckin(body);
      return _parseCheckinResponse(response);
    } on WeComException {
      rethrow;
    } on TimeoutException {
      throw const WeComException('请求超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw WeComException('网络请求失败：${error.message}');
    } on FormatException catch (error) {
      throw WeComException('企业微信返回了无法解析的数据：${error.message}');
    }
  }

  Future<List<MonthlyReport>> getMonthlyReport({
    required DateTime start,
    required DateTime end,
    required List<String> userIds,
  }) async {
    if (!config.isConfigured) {
      throw WeComException('配置不完整，缺少：${config.missingCheckinFields.join('、')}');
    }
    if (!start.isBefore(end)) {
      throw const WeComException('月报开始月份必须早于结束月份');
    }
    if (userIds.isEmpty) {
      throw const WeComException('请至少填写一个成员 UserID');
    }
    if (userIds.length > 100) {
      throw const WeComException('单次最多查询 100 个成员，请分批查询');
    }

    try {
      final data = await _requestWithToken(
        tokenManager: _applicationTokens,
        secret: config.secret,
        sendToken: (token) {
          final uri = _apiBase.replace(
            path: '/cgi-bin/checkin/getcheckin_monthdata',
            queryParameters: {'access_token': token},
          );
          return _httpClient.post(
            uri,
            headers: const {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'starttime': start.millisecondsSinceEpoch ~/ 1000,
              'endtime': end.millisecondsSinceEpoch ~/ 1000,
              'useridlist': userIds,
            }),
          );
        },
      );
      _throwForApiError(data, action: '获取打卡月报');
      final reports = data['datas'];
      if (reports == null) {
        return const [];
      }
      if (reports is! List) {
        throw const FormatException('datas 不是数组');
      }
      return reports
          .whereType<Map>()
          .map(
            (report) =>
                MonthlyReport.fromJson(Map<String, dynamic>.from(report)),
          )
          .toList(growable: false);
    } on WeComException {
      rethrow;
    } on TimeoutException {
      throw const WeComException('获取打卡月报超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw WeComException('获取打卡月报失败：${error.message}');
    } on FormatException catch (error) {
      throw WeComException('企业微信返回了无法解析的月报数据：${error.message}');
    }
  }

  Future<List<WeComMember>> getMemberIdList({int limit = 10000}) async {
    if (limit < 1 || limit > 10000) {
      throw const WeComException('通讯录分页数量必须在 1～10000 之间');
    }
    if (!config.isConfigured) {
      throw WeComException('配置不完整，缺少：${config.missingCheckinFields.join('、')}');
    }
    if (config.isContactConfigured) {
      try {
        return await _getContactSyncMemberList(limit: limit);
      } on WeComException catch (error) {
        if (error.errCode != 48002) {
          rethrow;
        }
      }
    }
    return _getAppVisibleMemberList();
  }

  Future<String> getUserIdByMobile(String mobile) async {
    final normalized = mobile.trim();
    if (normalized.isEmpty) {
      throw const WeComException('请输入手机号');
    }
    if (utf8.encode(normalized).length > 32) {
      throw const WeComException('手机号长度不能超过 32 字节');
    }

    final data = await _requestUserLookup(
      path: '/cgi-bin/user/getuserid',
      body: {'mobile': normalized},
      action: '手机号获取 UserID',
    );
    return _readUserId(data, action: '手机号获取 UserID');
  }

  Future<String> getUserIdByEmail(
    String email, {
    WeComEmailType emailType = WeComEmailType.enterprise,
  }) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      throw const WeComException('请输入邮箱');
    }
    if (!normalized.contains('@')) {
      throw const WeComException('邮箱格式不正确');
    }

    final data = await _requestUserLookup(
      path: '/cgi-bin/user/get_userid_by_email',
      body: {'email': normalized, 'email_type': emailType.apiValue},
      action: '邮箱获取 UserID',
    );
    return _readUserId(data, action: '邮箱获取 UserID');
  }

  Future<List<WeComMember>> _getContactSyncMemberList({
    required int limit,
  }) async {
    final departmentIdsByUser = <String, Set<int>>{};
    final visitedCursors = <String>{};
    String? cursor;

    try {
      do {
        final requestBody = <String, Object>{
          'limit': limit,
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        };
        final data = await _requestWithToken(
          tokenManager: _contactTokens,
          secret: config.contactSecret,
          sendToken: (token) {
            final uri = _apiBase.replace(
              path: '/cgi-bin/user/list_id',
              queryParameters: {'access_token': token},
            );
            return _httpClient.post(
              uri,
              headers: const {
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: jsonEncode(requestBody),
            );
          },
        );
        _throwForApiError(data, action: '获取成员 ID 列表');

        final relations = data['dept_user'];
        if (relations is! List) {
          throw const FormatException('dept_user 不是数组');
        }
        for (final relation in relations) {
          if (relation is! Map) {
            continue;
          }
          final item = Map<String, dynamic>.from(relation);
          final userId = item['userid']?.toString().trim() ?? '';
          if (userId.isEmpty) {
            continue;
          }
          final departments = departmentIdsByUser.putIfAbsent(
            userId,
            () => <int>{},
          );
          final departmentId = _readInt(item['department']);
          if (departmentId != null) {
            departments.add(departmentId);
          }
        }

        final nextCursor = data['next_cursor']?.toString().trim() ?? '';
        if (nextCursor.isEmpty) {
          cursor = null;
          continue;
        }
        if (!visitedCursors.add(nextCursor)) {
          throw const FormatException('通讯录分页游标重复');
        }
        cursor = nextCursor;
      } while (cursor != null);
    } on WeComException {
      rethrow;
    } on TimeoutException {
      throw const WeComException('获取通讯录超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw WeComException('获取通讯录失败：${error.message}');
    } on FormatException catch (error) {
      throw WeComException('企业微信返回了无法解析的通讯录数据：${error.message}');
    }

    return departmentIdsByUser.entries
        .map(
          (entry) => WeComMember(
            userId: entry.key,
            departmentIds: entry.value.toList(growable: false)..sort(),
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => a.userId.compareTo(b.userId));
  }

  Future<List<WeComMember>> _getAppVisibleMemberList() async {
    try {
      final departmentData = await _requestWithToken(
        tokenManager: _applicationTokens,
        secret: config.secret,
        sendToken: (token) {
          final uri = _apiBase.replace(
            path: '/cgi-bin/department/list',
            queryParameters: {'access_token': token},
          );
          return _httpClient.get(uri);
        },
      );
      _throwForApiError(departmentData, action: '获取应用可见部门');

      final departmentList = departmentData['department'];
      if (departmentList is! List) {
        throw const FormatException('department 不是数组');
      }
      final departmentIds =
          departmentList
              .whereType<Map>()
              .map((item) => _readInt(item['id']))
              .whereType<int>()
              .toSet()
              .toList(growable: false)
            ..sort();
      if (departmentIds.isEmpty) {
        return const [];
      }

      final departmentIdsByUser = <String, Set<int>>{};
      for (final departmentId in departmentIds) {
        final userData = await _requestWithToken(
          tokenManager: _applicationTokens,
          secret: config.secret,
          sendToken: (token) {
            final uri = _apiBase.replace(
              path: '/cgi-bin/user/simplelist',
              queryParameters: {
                'access_token': token,
                'department_id': '$departmentId',
              },
            );
            return _httpClient.get(uri);
          },
        );
        _throwForApiError(userData, action: '获取应用可见成员');

        final userList = userData['userlist'];
        if (userList is! List) {
          throw const FormatException('userlist 不是数组');
        }
        for (final user in userList.whereType<Map>()) {
          final userId = user['userid']?.toString().trim() ?? '';
          if (userId.isEmpty) {
            continue;
          }
          final userDepartments = departmentIdsByUser.putIfAbsent(
            userId,
            () => <int>{},
          );
          final rawDepartments = user['department'];
          if (rawDepartments is List) {
            userDepartments.addAll(
              rawDepartments.map(_readInt).whereType<int>(),
            );
          }
          if (userDepartments.isEmpty) {
            userDepartments.add(departmentId);
          }
        }
      }

      return departmentIdsByUser.entries
          .map(
            (entry) => WeComMember(
              userId: entry.key,
              departmentIds: entry.value.toList(growable: false)..sort(),
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.userId.compareTo(b.userId));
    } on WeComException {
      rethrow;
    } on TimeoutException {
      throw const WeComException('获取应用可见成员超时，请检查网络后重试');
    } on http.ClientException catch (error) {
      throw WeComException('获取应用可见成员失败：${error.message}');
    } on FormatException catch (error) {
      throw WeComException('企业微信返回了无法解析的成员数据：${error.message}');
    }
  }

  void close() {
    _httpClient.close();
  }

  Future<Map<String, dynamic>> _requestCheckin(String body) async {
    return _requestWithToken(
      tokenManager: _applicationTokens,
      secret: config.secret,
      sendToken: (token) {
        final uri = _apiBase.replace(
          path: '/cgi-bin/checkin/getcheckindata',
          queryParameters: {'access_token': token},
        );
        return _httpClient.post(
          uri,
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: body,
        );
      },
    );
  }

  Future<Map<String, dynamic>> _requestUserLookup({
    required String path,
    required Map<String, Object> body,
    required String action,
  }) async {
    final data = await _requestWithToken(
      tokenManager: _applicationTokens,
      secret: config.secret,
      sendToken: (token) {
        final uri = _apiBase.replace(
          path: path,
          queryParameters: {'access_token': token},
        );
        return _httpClient.post(
          uri,
          headers: const {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(body),
        );
      },
    );
    _throwForApiError(data, action: action);
    return data;
  }

  String _readUserId(Map<String, dynamic> data, {required String action}) {
    final userId = data['userid']?.toString().trim() ?? '';
    if (userId.isEmpty) {
      throw WeComException('$action失败：企业微信未返回 UserID');
    }
    return userId;
  }

  Future<Map<String, dynamic>> _requestWithToken({
    required _TokenManager tokenManager,
    required String secret,
    required Future<http.Response> Function(String token) sendToken,
  }) async {
    var token = await tokenManager.getToken(
      () => _fetchAccessToken(secret: secret),
    );
    var response = await sendToken(token).timeout(requestTimeout);
    var data = _decodeResponse(response);
    if (_tokenErrorCodes.contains(_readInt(data['errcode']))) {
      tokenManager.invalidate();
      token = await tokenManager.getToken(
        () => _fetchAccessToken(secret: secret),
      );
      response = await sendToken(token).timeout(requestTimeout);
      data = _decodeResponse(response);
      if (_tokenErrorCodes.contains(_readInt(data['errcode']))) {
        throw WeComException(
          '企业微信凭证刷新后仍不可用',
          errCode: _readInt(data['errcode']),
        );
      }
    }
    return data;
  }

  Future<_AccessToken> _fetchAccessToken({required String secret}) async {
    final uri = _apiBase.replace(
      path: '/cgi-bin/gettoken',
      queryParameters: {
        'corpid': config.corpId.trim(),
        'corpsecret': secret.trim(),
      },
    );
    final response = await _httpClient.get(uri).timeout(requestTimeout);
    final data = _decodeResponse(response);
    _throwForApiError(data, action: '获取 access_token');

    final token = data['access_token']?.toString() ?? '';
    final expiresIn = _readInt(data['expires_in']) ?? 7200;
    if (token.isEmpty) {
      throw const WeComException('企业微信未返回 access_token');
    }
    return _AccessToken(
      token,
      DateTime.now()
          .add(Duration(seconds: expiresIn))
          .subtract(_tokenSafetyWindow),
    );
  }

  List<CheckinRecord> _parseCheckinResponse(Map<String, dynamic> data) {
    _throwForApiError(data, action: '获取打卡记录');
    final list = data['checkindata'];
    if (list == null) {
      return const [];
    }
    if (list is! List) {
      throw const FormatException('checkindata 不是数组');
    }
    return list
        .map(
          (item) =>
              CheckinRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WeComException('企业微信服务请求失败', httpStatus: response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('响应根节点不是对象');
    }
    return decoded;
  }

  void _throwForApiError(Map<String, dynamic> data, {required String action}) {
    final errCode = _readInt(data['errcode']) ?? 0;
    if (errCode == 0) {
      return;
    }
    final message = data['errmsg']?.toString().trim();
    final friendlyMessage = switch (errCode) {
      301023 => '成员 UserID 列表非法或超过 100 人。请检查账号是否存在、是否已离职，或改用通讯录成员选择。',
      301024 => '查询时间范围非法或超过 30 天。',
      48002 => '$action无权限调用。请检查应用权限、可见范围和 API 可调用应用配置。',
      60111 => '未找到匹配的企业成员，请检查手机号或邮箱是否正确。',
      _ => null,
    };
    throw WeComException(
      friendlyMessage ??
          '$action失败${message == null || message.isEmpty ? '' : '：$message'}',
      errCode: errCode,
    );
  }

  void _validateRequest({
    required DateTime start,
    required DateTime end,
    required List<String> userIds,
  }) {
    if (!config.isConfigured) {
      throw WeComException('配置不完整，缺少：${config.missingCheckinFields.join('、')}');
    }
    if (!start.isBefore(end)) {
      throw const WeComException('开始时间必须早于结束时间');
    }
    if (end.difference(start) > const Duration(days: 30)) {
      throw const WeComException('单次查询时间跨度不能超过 30 天');
    }
    if (userIds.isEmpty) {
      throw const WeComException('请至少填写一个成员 UserID');
    }
    if (userIds.length > 100) {
      throw const WeComException('单次最多查询 100 个成员，请分批查询');
    }
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class _AccessToken {
  const _AccessToken(this.value, this.expiresAt);

  final String value;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class _TokenManager {
  _AccessToken? _cachedToken;
  Future<_AccessToken>? _tokenRequest;

  Future<String> getToken(Future<_AccessToken> Function() fetch) async {
    final cached = _cachedToken;
    if (cached != null && cached.isValid) {
      return cached.value;
    }

    final pending = _tokenRequest;
    if (pending != null) {
      return (await pending).value;
    }

    final request = fetch();
    _tokenRequest = request;
    try {
      final token = await request;
      _cachedToken = token;
      return token.value;
    } finally {
      if (identical(_tokenRequest, request)) {
        _tokenRequest = null;
      }
    }
  }

  void invalidate() {
    _cachedToken = null;
  }
}
