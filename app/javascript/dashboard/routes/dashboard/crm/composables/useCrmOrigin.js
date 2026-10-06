import { useI18n } from 'vue-i18n';

export const CRM_ORIGIN_SOURCE_META = {
  meta_ctwa: {
    icon: 'i-lucide-message-circle',
    labelKey: 'CRM_KANBAN.ORIGIN.META_CTWA',
  },
  meta_organic: {
    icon: 'i-lucide-facebook',
    labelKey: 'CRM_KANBAN.ORIGIN.META_ORGANIC',
  },
  google_ads: {
    icon: 'i-lucide-search',
    labelKey: 'CRM_KANBAN.ORIGIN.GOOGLE_ADS',
  },
  tiktok_ads: {
    icon: 'i-lucide-music-2',
    labelKey: 'CRM_KANBAN.ORIGIN.TIKTOK_ADS',
  },
  meta_paid: {
    icon: 'i-lucide-megaphone',
    labelKey: 'CRM_KANBAN.ORIGIN.META_PAID',
  },
  tracked_link: {
    icon: 'i-lucide-link',
    labelKey: 'CRM_KANBAN.ORIGIN.TRACKED_LINK',
  },
  // Campaign marks (#1002): set when the recipient replies to the campaign.
  campaign_whatsapp: {
    icon: 'i-lucide-send',
    labelKey: 'CRM_KANBAN.ORIGIN.CAMPAIGN_WHATSAPP',
  },
  campaign_email: {
    icon: 'i-lucide-mail',
    labelKey: 'CRM_KANBAN.ORIGIN.CAMPAIGN_EMAIL',
  },
  // #993: who talked through a live chat campaign of the website.
  campaign_live_chat: {
    icon: 'i-lucide-app-window',
    labelKey: 'CRM_KANBAN.ORIGIN.CAMPAIGN_LIVE_CHAT',
  },
  // #1004: reply to an SMS campaign.
  campaign_sms: {
    icon: 'i-lucide-message-square-text',
    labelKey: 'CRM_KANBAN.ORIGIN.CAMPAIGN_SMS',
  },
};

export const CAMPAIGN_MARK_SOURCES = [
  'campaign_whatsapp',
  'campaign_email',
  'campaign_live_chat',
  'campaign_sms',
];

// The card keeps up to 20 touches (Ctwa::CampaignBuilder); never list more.
export const CRM_ORIGIN_MAX_TOUCHES = 20;

const FALLBACK_SOURCE = 'meta_ctwa';
const UNKNOWN_SOURCE_META = {
  icon: 'i-lucide-circle-help',
  labelKey: 'CRM_KANBAN.ORIGIN.UNKNOWN',
};

const text = value => String(value ?? '').trim();

// A Meta object ID (campaign, ad set, ad) is a string of 6 to 30 digits —
// the same rule as Crm::MetaAds::NameResolver (docs/crm/origens-nomes-meta.md §3).
// Checked character by character, never with a regular expression.
const META_ID_MIN = 6;
const META_ID_MAX = 30;
export const isMetaObjectId = value => {
  const candidate = text(value);
  return (
    candidate.length >= META_ID_MIN &&
    candidate.length <= META_ID_MAX &&
    [...candidate].every(char => char >= '0' && char <= '9')
  );
};

// "1202…0416": long IDs keep both ends, the full value goes in the title.
const ID_EDGE = 4;
export const shortMetaId = value => {
  const id = text(value);
  if (id.length <= ID_EDGE * 2 + 1) return id;
  return `${id.slice(0, ID_EDGE)}…${id.slice(-ID_EDGE)}`;
};

// source_url is external webhook input (the CTWA referral is only length-bound
// on the server). Keep it only as an http(s) address, so it can never become a
// javascript: or data: link in the CRM.
const LINK_PROTOCOLS = ['http:', 'https:'];
export const safeSourceUrl = value => {
  const candidate = text(value);
  if (!candidate) return '';
  try {
    return LINK_PROTOCOLS.includes(new URL(candidate).protocol)
      ? candidate
      : '';
  } catch {
    return '';
  }
};

const normalizeSource = source => String(source || FALLBACK_SOURCE).trim();

const sourceMetaFor = source =>
  CRM_ORIGIN_SOURCE_META[normalizeSource(source)] || UNKNOWN_SOURCE_META;

const sourceForCampaign = campaign => {
  const source = String(campaign?.source || '').trim();
  if (source) return source;

  return String(campaign?.source_type || '').toLowerCase() === 'post'
    ? 'meta_organic'
    : FALLBACK_SOURCE;
};

export const buildCrmOrigin = campaign => {
  if (!campaign || typeof campaign !== 'object') return null;

  const source = sourceForCampaign(campaign);
  const meta = sourceMetaFor(source);
  const headline = text(campaign.headline);
  // A CTWA touch carries the ad itself (source_id = ad id); until its name is
  // resolved, the ad's own headline is the best name it has.
  const adName = text(campaign.ad_name);
  const adFromHeadline = !adName && source === 'meta_ctwa' && Boolean(headline);

  return {
    source,
    icon: meta.icon,
    labelKey: meta.labelKey,
    headline,
    sourceId: campaign.source_id,
    sourceType: campaign.source_type,
    sourceUrl: safeSourceUrl(campaign.source_url),
    // Prévia do anúncio na Meta e a miniatura do criativo (#1047, CA-1.11).
    adPreviewUrl: safeSourceUrl(campaign.ad_preview_url),
    adThumbnailUrl: safeSourceUrl(campaign.ad_thumbnail_url),
    touchedAt: campaign.touched_at || null,
    // Names resolved from the Meta API (#1034) win; otherwise the UTMs pasted in
    // the ad (#1011): utm_campaign = campaign, utm_term = ad set, utm_content = ad.
    // Meta's automatic parameters send IDs there — see hierarchyItems.
    campaign: text(campaign.campaign_name) || text(campaign.utm_campaign),
    adset: text(campaign.adset_name) || text(campaign.utm_term),
    ad: adName || (adFromHeadline ? headline : text(campaign.utm_content)),
    adFromHeadline,
    utmCampaign: text(campaign.utm_campaign),
  };
};

export const buildCrmOriginFromCampaigns = campaigns => {
  const origins = Array.isArray(campaigns)
    ? campaigns.map(buildCrmOrigin).filter(Boolean)
    : [];

  if (!origins.length) return null;

  return {
    ...origins[0],
    extraCount: origins.length - 1,
    origins,
  };
};

export function useCrmOrigin() {
  const { t, locale } = useI18n();

  const intlLocale = () =>
    text(locale?.value || 'en')
      .split('_')
      .join('-');

  // Short date of a touch ("10/07"; the year only when it is not this year),
  // with the full date and time for the title.
  const touchDate = origin => {
    const date = new Date(origin?.touchedAt || '');
    if (!origin?.touchedAt || Number.isNaN(date.getTime())) return null;
    const sameYear = date.getFullYear() === new Date().getFullYear();
    return {
      iso: date.toISOString(),
      label: new Intl.DateTimeFormat(intlLocale(), {
        day: '2-digit',
        month: '2-digit',
        ...(sameYear ? {} : { year: 'numeric' }),
      }).format(date),
      title: new Intl.DateTimeFormat(intlLocale(), {
        dateStyle: 'long',
        timeStyle: 'short',
      }).format(date),
    };
  };

  const sourceLabel = origin => {
    switch (origin?.source) {
      case 'meta_ctwa':
        return t('CRM_KANBAN.ORIGIN.META_CTWA');
      case 'meta_organic':
        return t('CRM_KANBAN.ORIGIN.META_ORGANIC');
      case 'google_ads':
        return t('CRM_KANBAN.ORIGIN.GOOGLE_ADS');
      case 'tiktok_ads':
        return t('CRM_KANBAN.ORIGIN.TIKTOK_ADS');
      case 'meta_paid':
        return t('CRM_KANBAN.ORIGIN.META_PAID');
      case 'tracked_link':
        return t('CRM_KANBAN.ORIGIN.TRACKED_LINK');
      case 'campaign_whatsapp':
        return t('CRM_KANBAN.ORIGIN.CAMPAIGN_WHATSAPP');
      case 'campaign_email':
        return t('CRM_KANBAN.ORIGIN.CAMPAIGN_EMAIL');
      case 'campaign_live_chat':
        return t('CRM_KANBAN.ORIGIN.CAMPAIGN_LIVE_CHAT');
      case 'campaign_sms':
        return t('CRM_KANBAN.ORIGIN.CAMPAIGN_SMS');
      default:
        return t('CRM_KANBAN.ORIGIN.UNKNOWN');
    }
  };

  // source_url is external webhook input: match the parsed hostname with a domain
  // boundary (never substring — instagram.com.evil.example must not classify as
  // Instagram).
  const hostnameMatches = (hostname, domain) =>
    hostname === domain || hostname.endsWith(`.${domain}`);

  const sourceUrlLabel = origin => {
    const sourceUrl = safeSourceUrl(origin?.sourceUrl);
    if (!sourceUrl) return '';

    let hostname;
    try {
      hostname = new URL(sourceUrl).hostname.toLowerCase();
    } catch {
      return '';
    }

    if (hostnameMatches(hostname, 'instagram.com')) {
      return t('CRM_KANBAN.ORIGIN.INSTAGRAM_POST');
    }
    if (
      hostnameMatches(hostname, 'facebook.com') ||
      hostnameMatches(hostname, 'fb.me')
    ) {
      return t('CRM_KANBAN.ORIGIN.FACEBOOK_POST');
    }

    return hostname;
  };

  const humanizedOriginLabel = origin => {
    if (!origin) return '';
    const label = sourceLabel(origin);
    if (origin.headline) return `${label}: ${origin.headline}`;

    return sourceUrlLabel(origin) || label;
  };

  // Shown value for one level: the name, or "ID 1202…0416" when Meta only sent
  // the number (the full ID stays in the title).
  const levelValue = value =>
    isMetaObjectId(value)
      ? {
          value: t('CRM_KANBAN.ORIGIN.META_ID', { id: shortMetaId(value) }),
          title: value,
        }
      : { value, title: value };

  // One item per Meta level the touch has: campaign, ad set, ad. Literal keys:
  // the project forbids building i18n keys at runtime.
  const LEVELS = [
    {
      field: 'campaign',
      level: () => t('CRM_KANBAN.ORIGIN.LEVEL.CAMPAIGN'),
      line: name => t('CRM_KANBAN.ORIGIN.CAMPAIGN_PART', { name }),
    },
    {
      field: 'adset',
      level: () => t('CRM_KANBAN.ORIGIN.LEVEL.ADSET'),
      line: name => t('CRM_KANBAN.ORIGIN.ADSET_PART', { name }),
    },
    {
      field: 'ad',
      level: () => t('CRM_KANBAN.ORIGIN.LEVEL.AD'),
      line: name => t('CRM_KANBAN.ORIGIN.AD_PART', { name }),
    },
  ];

  const hierarchyItems = origin =>
    LEVELS.filter(({ field }) => origin?.[field]).map(
      ({ field, level, line }) => {
        const shown = levelValue(origin[field]);
        return {
          field,
          level: level(),
          ...shown,
          line: line(shown.value),
        };
      }
    );

  // One translated line per Meta level: "Campaign: …", "Ad set: …", "Ad: …".
  const adHierarchyLines = origin =>
    hierarchyItems(origin).map(item => item.line);

  const adHierarchyLabel = origin => adHierarchyLines(origin).join(' · ');

  // The server writes a landing page headline as "<origin name> · <campaign>"
  // (docs/crm/ponte-lp-atribuicao.md §3). Where the campaign already has its
  // own line under the label, drop that suffix so the name is not repeated.
  const originLabelOverHierarchy = origin => {
    // The CTWA headline already shows as the "Ad" line.
    if (origin?.adFromHeadline) return sourceLabel(origin);
    if (!origin?.campaign) return humanizedOriginLabel(origin);
    // Before the name is resolved the suffix is the raw utm_campaign (an ID).
    const suffix = [origin.campaign, origin.utmCampaign]
      .filter(Boolean)
      .map(value => ` · ${value}`)
      .find(value => origin.headline.endsWith(value));
    const headline = suffix
      ? origin.headline.slice(0, -suffix.length)
      : origin.headline;
    return humanizedOriginLabel({ ...origin, headline });
  };

  // A CTWA touch whose only level is its own headline reads better as
  // "Meta Click-to-WhatsApp: <headline>" than as a lone "Ad: <headline>".
  const titleHierarchy = item =>
    item.adFromHeadline && !item.campaign && !item.adset
      ? ''
      : adHierarchyLabel(item);

  const formatOriginTitle = origin => {
    if (!origin) return '';
    const origins = origin.origins || [origin];
    return origins
      .map(
        item =>
          titleHierarchy(item) || item.sourceUrl || humanizedOriginLabel(item)
      )
      .join(origins.some(titleHierarchy) ? '\n' : ' · ');
  };

  // Campaign filter option (/ctwa_campaigns row): campaign marks read
  // "Campanha WhatsApp: <nome>" so they stand apart from ads and links.
  const campaignOptionLabel = option => {
    const name = option?.headline || String(option?.source_id ?? '');
    if (!CAMPAIGN_MARK_SOURCES.includes(option?.source)) return name;

    return `${sourceLabel(option)}: ${name}`;
  };

  return {
    originFromCampaign: buildCrmOrigin,
    originFromCampaigns: buildCrmOriginFromCampaigns,
    sourceLabel,
    sourceUrlLabel,
    humanizedOriginLabel,
    hierarchyItems,
    touchDate,
    formatOriginTitle,
    adHierarchyLines,
    originLabelOverHierarchy,
    campaignOptionLabel,
  };
}
