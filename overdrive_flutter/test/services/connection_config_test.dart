import 'package:flutter_test/flutter_test.dart';

import 'package:overdrive_flutter/services/connection_config.dart';

void main() {
  group('ConnectionConfig', () {
    test('empty by default', () {
      const c = ConnectionConfig();
      expect(c.isConfigured, isFalse);
      expect(c.baseUrl, '');
      expect(c.normalizedBaseUrl, '');
    });

    test('isConfigured becomes true when baseUrl non-empty', () {
      const c = ConnectionConfig(baseUrl: 'http://1.2.3.4:8080');
      expect(c.isConfigured, isTrue);
    });

    test('normalizedBaseUrl strips whitespace and trailing slashes', () {
      const c = ConnectionConfig(baseUrl: '  http://1.2.3.4:8080/  ');
      expect(c.normalizedBaseUrl, 'http://1.2.3.4:8080');

      const c2 = ConnectionConfig(baseUrl: 'https://x.example.com///');
      expect(c2.normalizedBaseUrl, 'https://x.example.com');
    });

    test('resolve joins base + path with exactly one slash', () {
      const c = ConnectionConfig(baseUrl: 'http://1.2.3.4:8080');
      expect(c.resolve('/api/status'), 'http://1.2.3.4:8080/api/status');
      expect(c.resolve('api/status'), 'http://1.2.3.4:8080/api/status');
    });

    test('resolve returns empty when not configured', () {
      const c = ConnectionConfig();
      expect(c.resolve('/api/status'), '');
    });

    test('copyWith preserves unspecified fields', () {
      const c = ConnectionConfig(baseUrl: 'http://1.2.3.4', label: 'LAN');
      final updated = c.copyWith(label: 'Zrok');
      expect(updated.baseUrl, 'http://1.2.3.4');
      expect(updated.label, 'Zrok');
    });

    test('equality based on baseUrl and label', () {
      const a = ConnectionConfig(baseUrl: 'http://x', label: 'L');
      const b = ConnectionConfig(baseUrl: 'http://x', label: 'L');
      const c = ConnectionConfig(baseUrl: 'http://y', label: 'L');
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });
  });
}
