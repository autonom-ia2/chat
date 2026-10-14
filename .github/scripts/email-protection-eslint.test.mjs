import test from 'node:test';
import assert from 'node:assert/strict';
import {
  localeConfig,
  standaloneApps,
  violations,
} from './email-protection-eslint.mjs';
const result = (...messages) => [{ messages }];
test('keeps the native dynamic-key warning without suppressing errors', () => {
  assert.deepEqual(
    violations(
      result({ severity: 1, ruleId: '@intlify/vue-i18n/no-dynamic-keys' })
    ),
    []
  );
  assert.equal(
    violations(
      result({ severity: 2, ruleId: '@intlify/vue-i18n/no-dynamic-keys' })
    ).length,
    1
  );
});
test('rejects missing keys, raw labels and every other warning', () => {
  for (const ruleId of [
    '@intlify/vue-i18n/no-missing-keys',
    '@intlify/vue-i18n/no-raw-text',
    'vue/no-root-v-if',
    null,
  ]) {
    assert.equal(violations(result({ severity: 1, ruleId })).length, 1);
  }
});
test('rejects fatal parser errors and ordinary lint errors', () => {
  assert.equal(
    violations(result({ severity: 2, ruleId: null, fatal: true })).length,
    1
  );
  assert.equal(
    violations(result({ severity: 2, ruleId: 'no-undef' })).length,
    1
  );
});
test('checks each standalone app against its own catalog only', () => {
  const config = localeConfig(['public_booking_v2']);
  assert.equal(
    config.settings['vue-i18n'].localeDir,
    './app/javascript/dashboard/i18n/locale/en/*.json'
  );
  assert.deepEqual(config.overrides, [
    {
      files: ['app/javascript/public_booking_v2/**'],
      settings: {
        'vue-i18n': {
          localeDir: './app/javascript/public_booking_v2/i18n/en.json',
        },
      },
    },
  ]);
});
test('finds the standalone apps that carry their own catalog', () => {
  const apps = standaloneApps();
  assert.ok(apps.includes('public_booking_v2'));
  assert.ok(!apps.includes('dashboard'));
});
