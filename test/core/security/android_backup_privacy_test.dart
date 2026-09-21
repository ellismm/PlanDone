import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final projectRoot = Directory.current.path;
  final manifest = File(
    '$projectRoot/android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final legacyRules = File(
    '$projectRoot/android/app/src/main/res/xml/backup_rules.xml',
  ).readAsStringSync();
  final modernRules = File(
    '$projectRoot/android/app/src/main/res/xml/data_extraction_rules.xml',
  ).readAsStringSync();
  const excludedDomains = <String>{
    'root',
    'file',
    'database',
    'sharedpref',
    'external',
    'device_root',
    'device_file',
    'device_database',
    'device_sharedpref',
  };

  test('manifest disables OS backup and references both rule formats', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:fullBackupContent="@xml/backup_rules"'),
    );
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('legacy rules exclude every app-private storage domain', () {
    expect(legacyRules, contains('<full-backup-content>'));
    for (final domain in excludedDomains) {
      expect(
        legacyRules,
        contains('<exclude domain="$domain" path="." />'),
        reason: 'Legacy backup rules must exclude $domain.',
      );
    }
  });

  test('modern rules exclude cloud and device-transfer data', () {
    final cloudRules = _section(
      modernRules,
      startTag: '<cloud-backup>',
      endTag: '</cloud-backup>',
    );
    final transferRules = _section(
      modernRules,
      startTag: '<device-transfer>',
      endTag: '</device-transfer>',
    );
    for (final domain in excludedDomains) {
      final exclusion = '<exclude domain="$domain" path="." />';
      expect(
        cloudRules,
        contains(exclusion),
        reason: 'Cloud backup rules must exclude $domain.',
      );
      expect(
        transferRules,
        contains(exclusion),
        reason: 'Device-transfer rules must exclude $domain.',
      );
    }
  });

  test('boot receiver accepts only app and protected system broadcasts', () {
    final receiver = _section(
      manifest,
      startTag: '<receiver\n            android:name=".ReminderBootReceiver"',
      endTag: '</receiver>',
    );
    expect(receiver, contains('android:exported="false"'));
    expect(
      receiver,
      contains('android.intent.action.BOOT_COMPLETED'),
    );
    expect(
      receiver,
      contains('android.intent.action.MY_PACKAGE_REPLACED'),
    );
  });
}

String _section(
  String source, {
  required String startTag,
  required String endTag,
}) {
  final start = source.indexOf(startTag);
  if (start < 0) return '';
  final end = source.indexOf(endTag, start);
  if (end < 0) return '';
  return source.substring(start, end + endTag.length);
}
