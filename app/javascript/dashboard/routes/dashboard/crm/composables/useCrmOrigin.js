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
};

const FALLBACK_SOURCE = 'meta_ctwa';
const UNKNOWN_SOURCE_META = {
  icon: 'i-lucide-circle-help',
  labelKey: 'CRM_KANBAN.ORIGIN.UNKNOWN',
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

  return {
    source,
    icon: meta.icon,
    labelKey: meta.labelKey,
    headline: String(campaign.headline || '').trim(),
    sourceId: campaign.source_id,
    sourceType: campaign.source_type,
    sourceUrl: String(campaign.source_url || '').trim(),
    // Landing page clicks (#1011) carry the Meta names through the UTMs pasted
    // in the ad: utm_campaign = campaign, utm_term = ad set, utm_content = ad.
    campaign: String(campaign.utm_campaign || '').trim(),
    adset: String(campaign.utm_term || '').trim(),
    ad: String(campaign.utm_content || '').trim(),
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
  const { t } = useI18n();

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
    const sourceUrl = origin?.sourceUrl;
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

  // One translated line per Meta level the ad sent: campaign, ad set, ad.
  const adHierarchyLines = origin =>
    [
      ['campaign', 'CRM_KANBAN.ORIGIN.CAMPAIGN_PART'],
      ['adset', 'CRM_KANBAN.ORIGIN.ADSET_PART'],
      ['ad', 'CRM_KANBAN.ORIGIN.AD_PART'],
    ]
      .filter(([field]) => origin?.[field])
      .map(([field, key]) => t(key, { name: origin[field] }));

  const adHierarchyLabel = origin => adHierarchyLines(origin).join(' · ');

  // The server writes a landing page headline as "<origin name> · <campaign>"
  // (docs/crm/ponte-lp-atribuicao.md §3). Where the campaign already has its
  // own line under the label, drop that suffix so the name is not repeated.
  const originLabelOverHierarchy = origin => {
    if (!origin?.campaign) return humanizedOriginLabel(origin);
    const suffix = ` · ${origin.campaign}`;
    const headline = origin.headline.endsWith(suffix)
      ? origin.headline.slice(0, -suffix.length)
      : origin.headline;
    return humanizedOriginLabel({ ...origin, headline });
  };

  const formatOriginTitle = origin => {
    if (!origin) return '';
    const origins = origin.origins || [origin];
    return origins
      .map(
        item =>
          adHierarchyLabel(item) || item.sourceUrl || humanizedOriginLabel(item)
      )
      .join(origins.some(adHierarchyLabel) ? '\n' : ' · ');
  };

  return {
    originFromCampaign: buildCrmOrigin,
    originFromCampaigns: buildCrmOriginFromCampaigns,
    humanizedOriginLabel,
    formatOriginTitle,
    adHierarchyLines,
    originLabelOverHierarchy,
  };
}
