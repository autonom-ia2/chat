import test from 'node:test';
import assert from 'node:assert/strict';
import { violations } from './email-protection-eslint.mjs';
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
