/* eslint-disable @intlify/vue-i18n/no-dynamic-keys -- Exercise the actual status resolver across all runtime locales. */
import { createI18n } from 'vue-i18n';
import dashboardMessages from 'dashboard/i18n';
import {
  NS,
  REQUIRED_LEGACY_KEYS,
  assertCompiles,
  checkEmailProtectionLocales,
  flattenMessages,
  localeMetadata,
  placeholders,
  readLocale,
  readVisibleLocale,
  validateMessages,
  validateRuntime,
  validateVisibleMessages,
} from '../../../../../../../scripts/check-email-protection-i18n.mjs';
import { localeTag, reasonKey, statusKey, deliveryKey } from '../presentation';

const metadata = localeMetadata();
const localeModules = import.meta.glob('../../../../i18n/locale/*/index.js');
const visibleCanonical = readVisibleLocale('en');

describe('inactive simplified Chinese locale compatibility', () => {
  it('preserves every originally imported zh resource without activating the locale', async () => {
    const { default: messages } =
      await localeModules['../../../../i18n/locale/zh/index.js']();
    const ownResources = import.meta.glob('../../../../i18n/locale/zh/*.json');
    // webhooks.json already existed without an import; preserve that boundary.
    const ownNames = [
      'agentMgmt',
      'campaign',
      'cannedMgmt',
      'chatlist',
      'contact',
      'conversation',
      'crm',
      'emailCampaignProtection',
      'generalSettings',
      'inboxMgmt',
      'integrations',
      'labelsMgmt',
      'login',
      'report',
      'resetPassword',
      'setNewPassword',
      'settings',
      'signup',
    ];
    await Promise.all(
      ownNames.map(async name => {
        const { default: resource } =
          await ownResources[`../../../../i18n/locale/zh/${name}.json`]();
        Object.entries(resource).forEach(([root, value]) => {
          expect(messages[root]).toEqual(value);
        });
      })
    );
    expect(dashboardMessages).not.toHaveProperty('zh');
  });

  it('retains the missing namespaces using existing simplified Chinese resources', async () => {
    const { default: messages } =
      await localeModules['../../../../i18n/locale/zh/index.js']();
    const sharedResources = import.meta.glob(
      '../../../../i18n/locale/zh_CN/*.json'
    );
    const sharedNames = [
      'advancedFilters',
      'agentBots',
      'attributesMgmt',
      'auditLogs',
      'automation',
      'bulkActions',
      'components',
      'contactFilters',
      'csatMgmt',
      'customRole',
      'datePicker',
      'emoji',
      'general',
      'helpCenter',
      'inbox',
      'integrationApps',
      'macros',
      'search',
      'sla',
      'teamsSettings',
      'whatsappTemplates',
    ];
    await Promise.all(
      sharedNames.map(async name => {
        const { default: resource } =
          await sharedResources[`../../../../i18n/locale/zh_CN/${name}.json`]();
        Object.entries(resource).forEach(([root, value]) => {
          expect(messages[root]).toEqual(value);
        });
      })
    );
  });
});

describe('email protection locale inventory', () => {
  it('compiles and renders every namespace and checks existing locale wiring', () => {
    const result = checkEmailProtectionLocales();
    expect(result).toMatchObject({
      localeFolders: 57,
      runtimeLocales: 43,
      indexesChecked: 57,
      missingInactiveIndexes: [],
      fallbackLocale: false,
    });
    expect(result.requiredLegacyKeysPerLocale).toBe(
      REQUIRED_LEGACY_KEYS.length
    );
    expect(result.compiledAndRenderedMessages).toBe(
      result.totalKeysPerLocale * 57
    );
  });

  it('keeps the actual dashboard registry at 43 languages', () => {
    expect(Object.keys(dashboardMessages).sort()).toEqual(
      metadata.runtimeLocales
    );
  });

  it('rejects missing keys, empty text, changed tokens and unsupported ICU syntax', () => {
    const canonical = readLocale('en');
    const missing = structuredClone(canonical);
    delete missing[NS].STATUS.unknown;
    expect(() => validateMessages('en', canonical, missing)).toThrow(
      'key parity'
    );
    const empty = structuredClone(canonical);
    empty[NS].STATUS.unknown = ' ';
    expect(() => validateMessages('en', canonical, empty)).toThrow(
      'empty translation'
    );
    const token = structuredClone(canonical);
    token[NS].CHECKED = 'Last checked: {datum}';
    expect(() => validateMessages('en', canonical, token)).toThrow(
      'interpolation parity'
    );
    expect(() =>
      assertCompiles(
        '{count, plural, one {retry} other {retries}}',
        `${NS}.RETRY_COUNT`
      )
    ).toThrow('Unterminated closing brace');
  });

  it('rejects English sentences copied into another language', () => {
    const canonical = readLocale('en');
    expect(() => validateMessages('fr', canonical, canonical)).toThrow(
      'untranslated English phrase'
    );
  });

  it('rejects missing or overwritten visible roots, raw keys, English copies and changed tokens', () => {
    const withoutCrm = structuredClone(visibleCanonical);
    delete withoutCrm.CAMPAIGN_MANAGEMENT;
    expect(() =>
      validateVisibleMessages('en', visibleCanonical, withoutCrm)
    ).toThrow('missing visible key');
    const partialRoot = structuredClone(visibleCanonical);
    partialRoot.CRM_KANBAN = { UNRELATED: 'preserved' };
    expect(() =>
      validateVisibleMessages('en', visibleCanonical, partialRoot)
    ).toThrow('missing visible key');
    const raw = structuredClone(visibleCanonical);
    raw.CAMPAIGN_MANAGEMENT.HEADER.TITLE = 'CAMPAIGN_MANAGEMENT.HEADER.TITLE';
    expect(() => validateVisibleMessages('en', visibleCanonical, raw)).toThrow(
      'raw translation key'
    );
    const token = structuredClone(visibleCanonical);
    token.CAMPAIGN_MANAGEMENT.RECIPIENTS.PAGE_OF = 'Page {page}';
    expect(() =>
      validateVisibleMessages('en', visibleCanonical, token)
    ).toThrow('interpolation parity');
    expect(() =>
      validateVisibleMessages('ar', visibleCanonical, visibleCanonical)
    ).toThrow('untranslated English phrase');
  });
});

describe.each(metadata.folders)(
  'visible legacy UI in the actual %s module',
  locale => {
    it('imports its real module and renders every required key without fallback', async () => {
      const modulePath = `../../../../i18n/locale/${locale}/index.js`;
      expect(localeModules[modulePath]).toBeTypeOf('function');
      const { default: messages } = await localeModules[modulePath]();
      expect(
        validateVisibleMessages(locale, visibleCanonical, messages)
      ).toEqual(
        validateVisibleMessages(
          locale,
          visibleCanonical,
          readVisibleLocale(locale)
        )
      );
      expect(messages[NS]).toEqual(readLocale(locale)[NS]);
      const { KPIS, RATES } = messages.CAMPAIGN_MANAGEMENT;
      expect(KPIS.BOUNCED).not.toBe(messages[NS].STATUS.permanent);
      expect(KPIS.BOUNCED).not.toBe(messages[NS].STATUS.nonexistent);
      expect(KPIS.COMPLAINED).not.toBe(KPIS.UNSUBSCRIBED);
      expect(RATES.COMPLAINT_RATE).not.toBe(RATES.UNSUBSCRIBE_RATE);
      validateRuntime(locale, messages, [
        ...REQUIRED_LEGACY_KEYS,
        ...Object.keys(flattenMessages(readLocale('en'))),
      ]);
    });
  }
);

describe.each(metadata.runtimeLocales)(
  'email protection in the actual %s module',
  locale => {
    it('renders all own translations with fallback disabled', () => {
      const namespace = dashboardMessages[locale][NS];
      expect(namespace).toEqual(readLocale(locale)[NS]);
      validateRuntime(locale, { [NS]: namespace });
      validateVisibleMessages(
        locale,
        visibleCanonical,
        dashboardMessages[locale]
      );
      validateRuntime(locale, dashboardMessages[locale], REQUIRED_LEGACY_KEYS);
    });

    it('humanizes unknown internal statuses and preserves meaningful distinctions', () => {
      const i18n = createI18n({
        legacy: false,
        locale,
        fallbackLocale: false,
        messages: { [locale]: { [NS]: dashboardMessages[locale][NS] } },
        missing(_locale, key) {
          throw new Error(`Missing own translation: ${key}`);
        },
      });
      const { t } = i18n.global;
      const raw = 'future_provider_enum_436';
      expect(statusKey({ status: raw })).toBe('unknown');
      expect(t(`${NS}.STATUS.${statusKey({ status: raw })}`)).toBe(
        dashboardMessages[locale][NS].STATUS.unknown
      );
      expect(t(`${NS}.REASON.${reasonKey(raw)}`)).toBe(
        dashboardMessages[locale][NS].REASON.unknown
      );
      expect(t(`${NS}.STATUS.permanent`)).not.toBe(
        t(`${NS}.STATUS.nonexistent`)
      );
      expect(t(`${NS}.STATUS.complained`)).not.toBe(
        t(`${NS}.STATUS.unsubscribed`)
      );
      expect(t(`${NS}.STATUS.suppressed`)).not.toBe(t(`${NS}.STATUS.bounced`));
      expect(() => t(`${NS}.MISSING_436`)).toThrow('Missing own translation');
      i18n.dispose();
    });
  }
);

describe.each(['ar', 'fa', 'he', 'ur', 'ur_IN'])(
  'RTL interpolation in %s',
  locale => {
    it('preserves every canonical named token and renders values intact', () => {
      const messages = readLocale(locale);
      const canonical = flattenMessages(readLocale('en'));
      Object.entries(flattenMessages(messages)).forEach(([key, message]) => {
        expect(placeholders(message)).toEqual(placeholders(canonical[key]));
      });
      validateRuntime(locale, messages);
    });
  }
);

it('preserves regional locale tags, Chinese scripts and distinct Serbian scripts', () => {
  expect(
    ['pt', 'pt_BR', 'zh', 'zh_CN', 'zh_TW', 'sr', 'sh', 'ur_IN'].map(localeTag)
  ).toEqual(['pt', 'pt-BR', 'zh', 'zh-CN', 'zh-TW', 'sr', 'sh', 'ur-IN']);
  expect(readLocale('zh')[NS].STATUS.delivered).toContain('服务器');
  expect(readLocale('zh_CN')[NS].STATUS.delivered).toContain('服务器');
  expect(readLocale('zh_TW')[NS].STATUS.delivered).toMatch(/伺服器|服務器/);
  expect(readLocale('sr')[NS].TITLE).toMatch(/\p{Script=Cyrillic}/u);
  expect(readLocale('sh')[NS].TITLE).not.toMatch(/\p{Script=Cyrillic}/u);
});

it.each(metadata.folders)(
  'renders delivery source semantics from the actual %s index without fallback',
  async locale => {
    const { default: messages } =
      await localeModules[`../../../../i18n/locale/${locale}/index.js`]();
    const i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: false,
      messages: { [locale]: messages },
    });
    const own = readLocale(locale)[NS];
    ['ses', 'direct_inbox', undefined].forEach(mode => {
      const key = deliveryKey({ delivery_mode: mode });
      expect(i18n.global.t(`${NS}.STATUS.${key}`)).toBe(own.STATUS[key]);
    });
    expect(own.STATUS.accepted_service).not.toBe(own.STATUS.delivered);
    expect(own.STATUS.acceptance_recorded).not.toBe(own.STATUS.delivered);
    expect(i18n.global.t(`${NS}.DELIVERY_HINT`)).toBe(own.DELIVERY_HINT);
    i18n.dispose();
  }
);
