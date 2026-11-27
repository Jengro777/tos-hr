import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tospino_hr/config/wecom_config.dart';
import 'package:tospino_hr/data/checkin_record.dart';
import 'package:tospino_hr/data/monthly_report.dart';
import 'package:tospino_hr/data/wecom_exception.dart';
import 'package:tospino_hr/data/wecom_member.dart';
import 'package:tospino_hr/services/wecom_api_client.dart';

void main() {
  const config = WecomConfig(
    corpId: 'ww-test-corp',
    agentId: '1000012',
    secret: 'test-secret',
  );

  test('checks enterprise WeChat connection and authentication', () async {
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/cgi-bin/gettoken');
        return jsonResponse({
          'errcode': 0,
          'access_token': 'connection-token',
          'expires_in': 7200,
        });
      }),
    );
    addTearDown(client.close);

    final status = await client.checkConnection();

    expect(status.connected, isTrue);
    expect(status.message, contains('鉴权正常'));
  });

  test(
    'reports missing enterprise WeChat configuration before connecting',
    () async {
      final client = WeComApiClient(
        config: const WecomConfig(corpId: '', agentId: '', secret: ''),
        httpClient: MockClient((request) {
          fail('A request should not be sent without configuration.');
        }),
      );
      addTearDown(client.close);

      final status = await client.checkConnection();

      expect(status.connected, isFalse);
      expect(status.message, contains('配置不完整'));
    },
  );

  test(
    'gets a token, caches it, and posts the expected check-in payload',
    () async {
      var tokenCalls = 0;
      var checkinCalls = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/cgi-bin/gettoken') {
          tokenCalls++;
          expect(request.url.queryParameters['corpid'], 'ww-test-corp');
          expect(request.url.queryParameters['corpsecret'], 'test-secret');
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'access_token': 'token-1',
            'expires_in': 7200,
          });
        }

        checkinCalls++;
        expect(request.method, 'POST');
        expect(request.url.path, '/cgi-bin/checkin/getcheckindata');
        expect(request.url.queryParameters['access_token'], 'token-1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['opencheckindatatype'], 3);
        expect(
          body['useridlist'],
          checkinCalls == 1 ? ['james', 'paul'] : ['james'],
        );
        expect(body['starttime'], isA<int>());
        expect(body['endtime'], isA<int>());
        return jsonResponse({
          'errcode': 0,
          'errmsg': 'ok',
          'checkindata': [
            {
              'userid': 'james',
              'checkin_type': '上班打卡',
              'checkin_time': 1492617610,
            },
          ],
        });
      });
      final client = WeComApiClient(config: config, httpClient: mockClient);
      addTearDown(client.close);
      final start = DateTime(2026, 11, 1);
      final end = DateTime(2026, 11, 2);

      final first = await client.getCheckinData(
        dataType: CheckinDataType.all,
        start: start,
        end: end,
        userIds: const ['james', 'paul'],
      );
      final second = await client.getCheckinData(
        dataType: CheckinDataType.all,
        start: start,
        end: end,
        userIds: const ['james'],
      );

      expect(first.single.userId, 'james');
      expect(second.single.userId, 'james');
      expect(tokenCalls, 1);
      expect(checkinCalls, 2);
    },
  );

  test('refreshes an expired token and retries once', () async {
    var tokenCalls = 0;
    var checkinCalls = 0;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/cgi-bin/gettoken') {
        tokenCalls++;
        return jsonResponse({
          'errcode': 0,
          'errmsg': 'ok',
          'access_token': 'token-$tokenCalls',
          'expires_in': 7200,
        });
      }

      checkinCalls++;
      if (checkinCalls == 1) {
        return jsonResponse({
          'errcode': 42001,
          'errmsg': 'access_token expired',
        });
      }
      expect(request.url.queryParameters['access_token'], 'token-2');
      return jsonResponse({
        'errcode': 0,
        'errmsg': 'ok',
        'checkindata': [
          {
            'userid': 'paul',
            'checkin_type': '下班打卡',
            'checkin_time': 1492617620,
          },
        ],
      });
    });
    final client = WeComApiClient(config: config, httpClient: mockClient);
    addTearDown(client.close);

    final records = await client.getCheckinData(
      dataType: CheckinDataType.all,
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 2),
      userIds: const ['paul'],
    );

    expect(records.single.userId, 'paul');
    expect(tokenCalls, 2);
    expect(checkinCalls, 2);
  });

  test('rejects time spans longer than 30 days before a request', () async {
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) {
        fail('A request should not be sent for an invalid date range.');
      }),
    );
    addTearDown(client.close);

    expect(
      () => client.getCheckinData(
        dataType: CheckinDataType.all,
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 2, 1),
        userIds: const ['james'],
      ),
      throwsA(
        isA<WeComException>().having(
          (error) => error.message,
          'message',
          contains('30 天'),
        ),
      ),
    );
  });

  test('surfaces enterprise WeChat errcode and errmsg', () async {
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) async {
        return jsonResponse({
          'errcode': 60020,
          'errmsg': 'not allow to access from your ip',
        });
      }),
    );
    addTearDown(client.close);

    expect(
      () => client.getCheckinData(
        dataType: CheckinDataType.all,
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 2),
        userIds: const ['james'],
      ),
      throwsA(
        isA<WeComException>()
            .having((error) => error.errCode, 'errcode', 60020)
            .having(
              (error) => error.message,
              'message',
              contains('not allow to access'),
            ),
      ),
    );
  });

  test('loads all member ID pages with the contact sync secret', () async {
    const contactConfig = WecomConfig(
      corpId: 'ww-test-corp',
      agentId: '1000012',
      secret: 'app-secret',
      contactSecret: 'contact-secret',
    );
    var tokenCalls = 0;
    var memberCalls = 0;
    final client = WeComApiClient(
      config: contactConfig,
      httpClient: MockClient((request) async {
        if (request.url.path == '/cgi-bin/gettoken') {
          tokenCalls++;
          expect(request.url.queryParameters['corpid'], 'ww-test-corp');
          expect(request.url.queryParameters['corpsecret'], 'contact-secret');
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'access_token': 'contact-token',
            'expires_in': 7200,
          });
        }

        memberCalls++;
        expect(request.url.path, '/cgi-bin/user/list_id');
        expect(request.url.queryParameters['access_token'], 'contact-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['limit'], 2);
        if (memberCalls == 1) {
          expect(body.containsKey('cursor'), isFalse);
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'next_cursor': 'page-2',
            'dept_user': [
              {'userid': 'zhangsan', 'department': 1},
              {'userid': 'zhangsan', 'department': 2},
              {'userid': 'lisi', 'department': 3},
            ],
          });
        }

        expect(body['cursor'], 'page-2');
        return jsonResponse({
          'errcode': 0,
          'errmsg': 'ok',
          'next_cursor': '',
          'dept_user': [
            {'userid': 'lisi', 'department': 4},
            {'userid': 'wangwu', 'department': 1},
          ],
        });
      }),
    );
    addTearDown(client.close);

    final members = await client.getMemberIdList(limit: 2);

    expect(tokenCalls, 1);
    expect(memberCalls, 2);
    expect(members.map((member) => member.userId), [
      'lisi',
      'wangwu',
      'zhangsan',
    ]);
    expect(members[0].departmentIds, [3, 4]);
    expect(members[2].departmentIds, [1, 2]);
  });

  test('falls back to members visible to the self-built app', () async {
    var tokenCalls = 0;
    var departmentCalls = 0;
    var memberCalls = 0;
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) async {
        if (request.url.path == '/cgi-bin/gettoken') {
          tokenCalls++;
          expect(request.url.queryParameters['corpsecret'], 'test-secret');
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'access_token': 'app-token',
            'expires_in': 7200,
          });
        }
        if (request.url.path == '/cgi-bin/department/list') {
          departmentCalls++;
          expect(request.url.queryParameters['access_token'], 'app-token');
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'department': [
              {'id': 1, 'name': '根部门'},
              {'id': 2, 'name': '研发部'},
            ],
          });
        }

        memberCalls++;
        expect(request.url.path, '/cgi-bin/user/simplelist');
        final departmentId = request.url.queryParameters['department_id'];
        if (departmentId == '1') {
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'userlist': [
              {
                'userid': 'zhangsan',
                'department': [1, 2],
              },
              {
                'userid': 'lisi',
                'department': [1],
              },
            ],
          });
        }
        return jsonResponse({
          'errcode': 0,
          'errmsg': 'ok',
          'userlist': [
            {
              'userid': 'zhangsan',
              'department': [1, 2],
            },
            {
              'userid': 'wangwu',
              'department': [2],
            },
          ],
        });
      }),
    );
    addTearDown(client.close);

    final members = await client.getMemberIdList();

    expect(tokenCalls, 1);
    expect(departmentCalls, 1);
    expect(memberCalls, 2);
    expect(members.map((member) => member.userId), [
      'lisi',
      'wangwu',
      'zhangsan',
    ]);
    expect(members[2].departmentIds, [1, 2]);
  });

  test(
    'returns a friendly message for an invalid check-in user list',
    () async {
      final client = WeComApiClient(
        config: config,
        httpClient: MockClient((request) async {
          if (request.url.path == '/cgi-bin/gettoken') {
            return jsonResponse({
              'errcode': 0,
              'errmsg': 'ok',
              'access_token': 'token',
              'expires_in': 7200,
            });
          }
          return jsonResponse({
            'errcode': 301023,
            'errmsg': 'userlist is over threshold',
          });
        }),
      );
      addTearDown(client.close);

      expect(
        () => client.getCheckinData(
          dataType: CheckinDataType.all,
          start: DateTime(2026, 11, 1),
          end: DateTime(2026, 11, 2),
          userIds: const ['12'],
        ),
        throwsA(
          isA<WeComException>()
              .having((error) => error.errCode, 'errcode', 301023)
              .having(
                (error) => error.message,
                'message',
                contains('成员 UserID 列表非法'),
              ),
        ),
      );
    },
  );

  test('looks up a UserID by mobile and email', () async {
    var tokenCalls = 0;
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) async {
        if (request.url.path == '/cgi-bin/gettoken') {
          tokenCalls++;
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'access_token': 'lookup-token',
            'expires_in': 7200,
          });
        }
        expect(request.url.queryParameters['access_token'], 'lookup-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/cgi-bin/user/getuserid') {
          expect(body['mobile'], '13430388888');
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'userid': 'zhangsan',
          });
        }

        expect(request.url.path, '/cgi-bin/user/get_userid_by_email');
        expect(body['email'], 'zhangsan@example.com');
        expect(body['email_type'], 2);
        return jsonResponse({'errcode': 0, 'errmsg': 'ok', 'userid': 'lisi'});
      }),
    );
    addTearDown(client.close);

    final mobileUserId = await client.getUserIdByMobile('13430388888');
    final emailUserId = await client.getUserIdByEmail(
      'zhangsan@example.com',
      emailType: WeComEmailType.personal,
    );

    expect(mobileUserId, 'zhangsan');
    expect(emailUserId, 'lisi');
    expect(tokenCalls, 1);
  });

  test('requests monthly report data for the selected natural month', () async {
    late Map<String, dynamic> requestBody;
    final client = WeComApiClient(
      config: config,
      httpClient: MockClient((request) async {
        if (request.url.path == '/cgi-bin/gettoken') {
          return jsonResponse({
            'errcode': 0,
            'errmsg': 'ok',
            'access_token': 'monthly-token',
            'expires_in': 7200,
          });
        }

        expect(request.url.path, '/cgi-bin/checkin/getcheckin_monthdata');
        expect(request.url.queryParameters['access_token'], 'monthly-token');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({
          'errcode': 0,
          'errmsg': 'ok',
          'datas': [
            {
              'base_info': {'name': '张三', 'acctid': 'zhangsan'},
              'summary_info': {'work_days': 20, 'except_days': 1},
            },
          ],
        });
      }),
    );
    addTearDown(client.close);
    final start = DateTime(2026, 11);
    final end = DateTime(2026, 12);

    final reports = await client.getMonthlyReport(
      start: start,
      end: end,
      userIds: const ['zhangsan'],
    );

    expect(requestBody['starttime'], start.millisecondsSinceEpoch ~/ 1000);
    expect(requestBody['endtime'], end.millisecondsSinceEpoch ~/ 1000);
    expect(requestBody['useridlist'], ['zhangsan']);
    expect(reports, hasLength(1));
    expect(reports.single, isA<MonthlyReport>());
    expect(reports.single.summary.workDays, 20);
  });
}

http.Response jsonResponse(Map<String, Object?> body, {int statusCode = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
