/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- This checker deliberately renders every discovered key. */
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createI18n } from 'vue-i18n';
import { runInNewContext } from 'node:vm';

export const NS = 'EMAIL_CAMPAIGN_PROTECTION';
export const localeRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../app/javascript/dashboard/i18n/locale'
);

// Audited visible surfaces: list, create/edit and details dialogs, import feedback,
// campaign reports and their rendered children. No builder/editor expansion.
export const VISIBLE_SURFACES = [
  'helper/emailCampaignImport.js',
  'store/modules/emailCampaigns.js',
  'api/emailCampaigns.js',
  'components-next/Campaigns/CampaignLayout.vue',
  'routes/dashboard/campaigns/pages/EmailCampaignsPage.vue',
  'routes/dashboard/crm/pages/CrmCampaignManagementPage.vue',
  'components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDetailsDialog.vue',
  'components-next/Campaigns/Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue',
  'components-next/Campaigns/Pages/CampaignPage/EmailCampaign/EmailCampaignDialog.vue',
  'components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/PlaceholderChips.vue',
  'components-next/Campaigns/EmailProtection/EmailCampaignHealth.vue',
  'components-next/Campaigns/EmailProtection/EmailHygieneSummary.vue',
  'components-next/Campaigns/EmailProtection/EmailImportIssues.vue',
  'components-next/Campaigns/EmailProtection/EmailProtectionPanel.vue',
  'components-next/Campaigns/EmailProtection/EmailRecipients.vue',
  'components-next/Campaigns/EmailProtection/EmailStatusBadge.vue',
  'components-next/Campaigns/EmailProtection/EmailStatusFilter.vue',
  'components-next/Campaigns/EmailProtection/presentation.js',
];

// Explicit legacy contract. Includes all management/tracked-link leaves and
// dynamic campaign/import states; protection statuses are checked separately.
export const REQUIRED_LEGACY_KEYS = [
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.CANCEL_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DELETE_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.DUPLICATE_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.EDIT',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.MANAGE_RECIPIENTS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.OPEN_BUILDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.PAUSE_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SCHEDULE',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SCHEDULE_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_NOW',
  'CAMPAIGN.EMAIL_CAMPAIGN.ACTIONS.SEND_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.FAILED',
  'CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.PROCESSING',
  'CAMPAIGN.EMAIL_CAMPAIGN.AI.BADGE.READY',
  'CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.FAILED',
  'CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.RECIPIENTS',
  'CAMPAIGN.EMAIL_CAMPAIGN.COUNTS.SENT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DESCRIPTION',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_HINT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_IMPORTING',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_PICK',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.BASE_SELECTED',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CANCEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CREATE_AND_OPEN',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.CREATE_TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.DIRECT_OPTION',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.DIRECT_WARNING',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.EDIT_TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_DIRECT_HINT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_HINT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_HINT_NO_DOMAIN',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_INVALID',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_PLACEHOLDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_PLACEHOLDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_PLACEHOLDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NO_VERIFIED_DOMAIN',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_HINT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_INVALID',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_PLACEHOLDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SAVE_DRAFT',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SENDER_PLACEHOLDER',
  'CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.SUBTITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.EMPTY_STATE.TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.HEADER_TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.COMPLETED',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.EMPTY_FILE',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.EXPIRED',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.FAILED',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.FILE_TOO_LARGE',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.HEADERS',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.INVALID_FILE',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.IN_PROGRESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.ROW_LIMIT',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.UPLOAD_FAILED',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.PROCESSING',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.QUEUED',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.RETRY',
  'CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.SUMMARY',
  'CAMPAIGN.EMAIL_CAMPAIGN.NEW',
  'CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.COPY_SUCCESS',
  'CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.EMPTY',
  'CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.SUBTITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.PLACEHOLDERS.TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.ADD_MORE',
  'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.ADD_MORE_HINT',
  'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.SUBTITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.RECIPIENTS.TITLE',
  'CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.CANCEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.DATETIME_ERROR',
  'CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.DATETIME_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.SCHEDULE_DIALOG.SUBMIT',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.CANCELED',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.DRAFT',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.FAILED',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.PAUSED',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SCHEDULED',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SENDING',
  'CAMPAIGN.EMAIL_CAMPAIGN.STATUS.SENT',
  'CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.BLANK_ITEM',
  'CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.BLANK_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.MISSING_LABEL',
  'CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.OK',
  'CAMPAIGN.EMAIL_CAMPAIGN.VALIDATION.TITLE',
  'CAMPAIGN_MANAGEMENT.APPROXIMATE',
  'CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.EMPTY',
  'CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TITLE',
  'CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.TOTAL',
  'CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.UNIQUE',
  'CAMPAIGN_MANAGEMENT.CLICKS_BY_LINK.URL',
  'CAMPAIGN_MANAGEMENT.COMPARISON.TITLE',
  'CAMPAIGN_MANAGEMENT.EMPTY_STATE.SUBTITLE',
  'CAMPAIGN_MANAGEMENT.EMPTY_STATE.TITLE',
  'CAMPAIGN_MANAGEMENT.ERROR',
  'CAMPAIGN_MANAGEMENT.EXPORT_CSV',
  'CAMPAIGN_MANAGEMENT.FILTER.ALL',
  'CAMPAIGN_MANAGEMENT.FILTER.LABEL',
  'CAMPAIGN_MANAGEMENT.HEADER.DESCRIPTION',
  'CAMPAIGN_MANAGEMENT.HEADER.TITLE',
  'CAMPAIGN_MANAGEMENT.KPIS.BOUNCED',
  'CAMPAIGN_MANAGEMENT.KPIS.CLICKED',
  'CAMPAIGN_MANAGEMENT.KPIS.COMPLAINED',
  'CAMPAIGN_MANAGEMENT.KPIS.DELIVERED',
  'CAMPAIGN_MANAGEMENT.KPIS.OPENED',
  'CAMPAIGN_MANAGEMENT.KPIS.SENT',
  'CAMPAIGN_MANAGEMENT.KPIS.UNSUBSCRIBED',
  'CAMPAIGN_MANAGEMENT.OPEN_APPROXIMATE_HINT',
  'CAMPAIGN_MANAGEMENT.PAYWALL.DESCRIPTION',
  'CAMPAIGN_MANAGEMENT.PAYWALL.TITLE',
  'CAMPAIGN_MANAGEMENT.RATES.BOUNCE_RATE',
  'CAMPAIGN_MANAGEMENT.RATES.CLICK_RATE',
  'CAMPAIGN_MANAGEMENT.RATES.COMPLAINT_RATE',
  'CAMPAIGN_MANAGEMENT.RATES.OPEN_RATE',
  'CAMPAIGN_MANAGEMENT.RATES.OVER_DELIVERED',
  'CAMPAIGN_MANAGEMENT.RATES.UNSUBSCRIBE_RATE',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.EMPTY',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.NEXT',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.PAGE_OF',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.PREV',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.SEARCH_PLACEHOLDER',
  'CAMPAIGN_MANAGEMENT.RECIPIENTS.TITLE',
  'CAMPAIGN_MANAGEMENT.TABLE.ATTEMPTS',
  'CAMPAIGN_MANAGEMENT.TABLE.CLICKS',
  'CAMPAIGN_MANAGEMENT.TABLE.EMAIL',
  'CAMPAIGN_MANAGEMENT.TABLE.LAST_EVENT_AT',
  'CAMPAIGN_MANAGEMENT.TABLE.NAME',
  'CAMPAIGN_MANAGEMENT.TABLE.OPENS',
  'CAMPAIGN_MANAGEMENT.TABLE.STATUS',
  'CAMPAIGN_MANAGEMENT.TIMELINE.EMPTY',
  'CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.DAY',
  'CAMPAIGN_MANAGEMENT.TIMELINE.INTERVAL.HOUR',
  'CAMPAIGN_MANAGEMENT.TIMELINE.TITLE',
  'CRM_KANBAN.TRACKED_LINKS.ADD',
  'CRM_KANBAN.TRACKED_LINKS.CLICKS',
  'CRM_KANBAN.TRACKED_LINKS.CODE',
  'CRM_KANBAN.TRACKED_LINKS.CONVERSATIONS',
  'CRM_KANBAN.TRACKED_LINKS.COPIED',
  'CRM_KANBAN.TRACKED_LINKS.COPY_LINK',
  'CRM_KANBAN.TRACKED_LINKS.CREATE_ERROR',
  'CRM_KANBAN.TRACKED_LINKS.CREATE_SUCCESS',
  'CRM_KANBAN.TRACKED_LINKS.DELETE',
  'CRM_KANBAN.TRACKED_LINKS.DELETE_CONFIRM',
  'CRM_KANBAN.TRACKED_LINKS.DOWNLOAD_QR',
  'CRM_KANBAN.TRACKED_LINKS.EMPTY',
  'CRM_KANBAN.TRACKED_LINKS.INBOX',
  'CRM_KANBAN.TRACKED_LINKS.NAME',
  'CRM_KANBAN.TRACKED_LINKS.NAME_PLACEHOLDER',
  'CRM_KANBAN.TRACKED_LINKS.PREFILLED',
  'CRM_KANBAN.TRACKED_LINKS.PREFILLED_PLACEHOLDER',
  'CRM_KANBAN.TRACKED_LINKS.SUBTITLE',
  'CRM_KANBAN.TRACKED_LINKS.TITLE',
];

// Resolve the compiler through vue-i18n's installed dependency tree (pnpm).
const require = createRequire(import.meta.url);
const i18nRequire = createRequire(require.resolve('vue-i18n'));
const coreRequire = createRequire(i18nRequire.resolve('@intlify/core-base'));
const { baseCompile } = coreRequire('@intlify/message-compiler');

export function flattenMessages(messages, prefix = '') {
  assert(
    messages && typeof messages === 'object' && !Array.isArray(messages),
    `${prefix || 'root'}: expected an object`
  );
  assert(Object.keys(messages).length, `${prefix || 'root'}: empty object`);
  return Object.fromEntries(
    Object.entries(messages).flatMap(([key, value]) => {
      const path = prefix ? `${prefix}.${key}` : key;
      if (typeof value === 'string') {
        assert(value.trim(), `${path}: empty translation`);
        return [[path, value]];
      }
      return Object.entries(flattenMessages(value, path));
    })
  );
}

export const placeholders = message =>
  [
    ...new Set([...message.matchAll(/\{([a-zA-Z_][\w]*)\}/g)].map(m => m[1])),
  ].sort();

export function readLocale(locale) {
  return JSON.parse(
    readFileSync(
      resolve(localeRoot, locale, 'emailCampaignProtection.json'),
      'utf8'
    )
  );
}

const messageAt = (messages, key) =>
  key.split('.').reduce((value, part) => value?.[part], messages);

export function readVisibleLocale(locale) {
  return Object.assign(
    {},
    ...['crm.json', 'campaign.json'].map(file =>
      JSON.parse(readFileSync(resolve(localeRoot, locale, file), 'utf8'))
    )
  );
}

// Execute only the export expression with the actual imported JSON bindings.
// This preserves spread order and root merges instead of assuming JSON presence
// means the messages are wired. Vitest also imports the real ES modules.
export function loadLocaleIndex(locale) {
  const source = readFileSync(resolve(localeRoot, locale, 'index.js'), 'utf8');
  const imports = [
    ...source.matchAll(/import\s+(\w+)\s+from\s+['"](.+?\.json)['"];?/g),
  ];
  const bindings = Object.fromEntries(
    imports.map(([, name, file]) => [
      name,
      JSON.parse(readFileSync(resolve(localeRoot, locale, file), 'utf8')),
    ])
  );
  const exported = source.match(/export default\s*({[\s\S]*});?\s*$/);
  assert(exported, `${locale}: unsupported locale export`);
  return runInNewContext(`(${exported[1]})`, bindings, { timeout: 1000 });
}

export function assertVisibleInventory() {
  const required = new Set(REQUIRED_LEGACY_KEYS);
  assert.equal(
    required.size,
    REQUIRED_LEGACY_KEYS.length,
    'Duplicate required key'
  );
  VISIBLE_SURFACES.forEach(file => {
    const source = readFileSync(resolve(localeRoot, '../../', file), 'utf8');
    const references = source.matchAll(
      /['"]((?:CAMPAIGN\.EMAIL_CAMPAIGN|CAMPAIGN_MANAGEMENT|CRM_KANBAN\.TRACKED_LINKS)\.[A-Z_.]+)['"]/g
    );
    [...references].forEach(([, key]) => {
      assert(required.has(key), `${file}: unregistered visible key ${key}`);
    });
    if (file === 'helper/emailCampaignImport.js') {
      // The helper chooses its error key dynamically from a fixed code map.
      [...source.matchAll(/'([A-Z_]+)'/g)].forEach(([, suffix]) => {
        const key = `CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.${suffix}`;
        assert(required.has(key), `${file}: unregistered dynamic key ${key}`);
      });
    }
  });
}

export function localeMetadata() {
  const folders = readdirSync(localeRoot, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => entry.name)
    .sort();
  const dashboardIndex = readFileSync(
    resolve(localeRoot, '../index.js'),
    'utf8'
  );
  const imports = [
    ...dashboardIndex.matchAll(
      /import\s+(\w+)\s+from\s+['"]\.\/locale\/([^'"]+)['"]/g
    ),
  ];
  const exported = dashboardIndex.match(/export default\s*\{([^}]+)\}/s);
  assert(exported, 'Dashboard must export its locale registry');
  const exportedNames = exported[1]
    .split(',')
    .map(name => name.trim())
    .filter(Boolean);
  assert.deepEqual(
    imports.map(match => match[1]).sort(),
    exportedNames.sort(),
    'Runtime imports and exports must agree'
  );
  const runtimeLocales = imports.map(match => match[2]).sort();
  assert.equal(new Set(runtimeLocales).size, runtimeLocales.length);
  const missingIndexes = folders.filter(
    locale => !existsSync(resolve(localeRoot, locale, 'index.js'))
  );
  return { folders, runtimeLocales, missingIndexes };
}

export function assertLocaleIndex(locale) {
  const source = readFileSync(resolve(localeRoot, locale, 'index.js'), 'utf8');
  assert.equal(
    [
      ...source.matchAll(
        /^import emailCampaignProtection from ['"]\.\/emailCampaignProtection\.json['"];?$/gm
      ),
    ].length,
    1,
    `${locale}: expected one namespace import`
  );
  const exported = source.match(/export default\s*\{([\s\S]*?)\};?/);
  assert(exported, `${locale}: missing export object`);
  assert.equal(
    [...exported[1].matchAll(/\.\.\.emailCampaignProtection\s*[,}]/g)].length,
    1,
    `${locale}: expected one namespace spread`
  );
}

export function assertCompiles(message, label) {
  baseCompile(message, {
    onError(error) {
      throw new Error(`${label}: ${error.message}`);
    },
  });
}

export function validateVisibleMessages(locale, canonical, messages) {
  const actual = {};
  REQUIRED_LEGACY_KEYS.forEach(key => {
    const message = messageAt(messages, key);
    const expected = messageAt(canonical, key);
    assert.equal(typeof expected, 'string', `en: missing canonical key ${key}`);
    assert.equal(
      typeof message,
      'string',
      `${locale}: missing visible key ${key}`
    );
    assert(message.trim(), `${locale}/${key}: empty translation`);
    assert.notEqual(message, key, `${locale}/${key}: raw translation key`);
    assert.deepEqual(
      placeholders(message),
      placeholders(expected),
      `${locale}/${key}: interpolation parity`
    );
    assertCompiles(message, `${locale}/${key}`);
    if (locale !== 'en' && (expected.match(/[A-Za-z]+/g) || []).length >= 2) {
      assert.notEqual(
        message,
        expected,
        `${locale}/${key}: untranslated English phrase`
      );
    }
    actual[key] = message;
  });
  return actual;
}

export function validateMessages(locale, canonical, messages) {
  const expected = flattenMessages(canonical);
  const actual = flattenMessages(messages);
  assert.deepEqual(
    Object.keys(actual).sort(),
    Object.keys(expected).sort(),
    `${locale}: key parity`
  );
  Object.entries(actual).forEach(([key, message]) => {
    assert.deepEqual(
      placeholders(message),
      placeholders(expected[key]),
      `${locale}/${key}: interpolation parity`
    );
    assertCompiles(message, `${locale}/${key}`);
    // Identical loanwords are legitimate; complete English phrases are not.
    if (
      locale !== 'en' &&
      (expected[key].match(/[A-Za-z]+/g) || []).length >= 3
    ) {
      assert.notEqual(
        message,
        expected[key],
        `${locale}/${key}: untranslated English phrase`
      );
    }
  });
  const status = messages[NS].STATUS;
  assert(
    status.unknown && status.unknown !== 'unknown',
    `${locale}: humanized unknown status`
  );
  [
    ['permanent', 'nonexistent'],
    ['suppressed', 'failed'],
    ['suppressed', 'bounced'],
    ['complained', 'unsubscribed'],
  ].forEach(([left, right]) => {
    assert.notEqual(
      status[left],
      status[right],
      `${locale}: ${left} and ${right} must remain distinct`
    );
  });
  return actual;
}

export function validateRuntime(locale, messages, keys) {
  // Only the selected locale is installed: no other locale can mask missing keys.
  const i18n = createI18n({
    legacy: false,
    locale,
    fallbackLocale: false,
    messages: { [locale]: messages },
    missing(_locale, key) {
      throw new Error(`${locale}: missing translation ${key}`);
    },
  });
  try {
    const entries = keys
      ? keys.map(key => [key, messageAt(messages, key)])
      : Object.entries(flattenMessages(messages));
    entries.forEach(([key, message]) => {
      assert.equal(
        typeof message,
        'string',
        `${locale}: missing own key ${key}`
      );
      const values = Object.fromEntries(
        placeholders(message).map(name => [name, `__${name}__`])
      );
      const expected = message
        .replace(/\{'([^']*)'\}/g, '$1')
        .replace(/\{([a-zA-Z_][\w]*)\}/g, (_, name) => values[name]);
      assert(i18n.global.te(key, locale), `${locale}: missing own key ${key}`);
      assert.notEqual(
        i18n.global.t(key, values),
        key,
        `${locale}: raw fallback ${key}`
      );
      assert.equal(
        i18n.global.t(key, values),
        expected,
        `${locale}/${key}: compiled output`
      );
    });
  } finally {
    i18n.dispose();
  }
}

export function checkEmailProtectionLocales() {
  const metadata = localeMetadata();
  assert.equal(metadata.folders.length, 57, 'Expected 57 locale folders');
  assert.equal(
    metadata.runtimeLocales.length,
    43,
    'Expected 43 runtime locales'
  );
  assert.deepEqual(
    metadata.missingIndexes,
    [],
    'Every folder needs a loadable module'
  );
  assertVisibleInventory();
  const canonical = readLocale('en');
  const visibleCanonical = readVisibleLocale('en');
  const keysPerLocale = Object.keys(flattenMessages(canonical)).length;
  metadata.folders.forEach(locale => {
    const messages = readLocale(locale);
    validateMessages(locale, canonical, messages);
    assertLocaleIndex(locale);
    const loaded = loadLocaleIndex(locale);
    assert.deepEqual(
      loaded[NS],
      messages[NS],
      `${locale}: protection namespace wiring`
    );
    const visible = readVisibleLocale(locale);
    const expectedVisible = Object.fromEntries(
      REQUIRED_LEGACY_KEYS.map(key => [key, messageAt(visible, key)])
    );
    const effectiveVisible = validateVisibleMessages(
      locale,
      visibleCanonical,
      loaded
    );
    assert.deepEqual(
      effectiveVisible,
      expectedVisible,
      `${locale}: visible namespace wiring`
    );
    validateRuntime(locale, loaded, [
      ...Object.keys(flattenMessages(canonical)),
      ...REQUIRED_LEGACY_KEYS,
    ]);
  });
  metadata.runtimeLocales.forEach(locale => {
    assert(
      metadata.folders.includes(locale),
      `${locale}: runtime folder missing`
    );
    assert(
      !metadata.missingIndexes.includes(locale),
      `${locale}: runtime index missing`
    );
  });
  return {
    localeFolders: metadata.folders.length,
    runtimeLocales: metadata.runtimeLocales.length,
    indexesChecked: metadata.folders.length - metadata.missingIndexes.length,
    missingInactiveIndexes: metadata.missingIndexes,
    keysPerLocale,
    requiredLegacyKeysPerLocale: REQUIRED_LEGACY_KEYS.length,
    totalKeysPerLocale: keysPerLocale + REQUIRED_LEGACY_KEYS.length,
    compiledAndRenderedMessages:
      (keysPerLocale + REQUIRED_LEGACY_KEYS.length) * metadata.folders.length,
    fallbackLocale: false,
  };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
) {
  // This is a standalone offline validation command, not an application logger.
  process.stdout.write(
    `${JSON.stringify(checkEmailProtectionLocales(), null, 2)}\n`
  );
}
