import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/config/wecom_config.dart';

void main() {
  group('WecomConfig', () {
    test('reports all missing fields for an empty config', () {
      const config = WecomConfig(corpId: ' ', agentId: '', secret: '');

      expect(config.isConfigured, isFalse);
      expect(config.missingFields, [
        '企业ID',
        'AgentId',
        'Secret',
        '通讯录同步Secret',
      ]);
      expect(config.isContactConfigured, isFalse);
    });

    test('treats template placeholders as missing', () {
      const config = WecomConfig(
        corpId: '请填写企业ID',
        agentId: '1234567',
        secret: 'real-secret',
      );

      expect(config.isConfigured, isFalse);
      expect(config.missingFields, ['企业ID', '通讯录同步Secret']);
      expect(config.isContactConfigured, isFalse);
    });

    test('masks configured identifiers', () {
      const config = WecomConfig(
        corpId: 'ww1234567890abcdef',
        agentId: '1000012',
        secret: 'real-secret',
        contactSecret: 'contact-secret',
      );

      expect(config.isConfigured, isTrue);
      expect(config.isContactConfigured, isTrue);
      expect(config.missingFields, isEmpty);
      expect(config.maskedCorpId, 'ww12****cdef');
      expect(config.maskedAgentId, '10****12');
    });

    test('contact permission is independent from check-in permission', () {
      const config = WecomConfig(
        corpId: 'ww1234567890abcdef',
        agentId: '1000012',
        secret: 'app-secret',
      );

      expect(config.isConfigured, isTrue);
      expect(config.isContactConfigured, isFalse);
      expect(config.missingCheckinFields, isEmpty);
      expect(config.missingFields, ['通讯录同步Secret']);
    });
  });
}
