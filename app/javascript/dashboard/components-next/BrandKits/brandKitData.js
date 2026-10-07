// Shapes of a visual identity on the screens (#1076). The server keeps the format
// (BrandKits::Appearance): palettes.light/dark with the roles below, site_palette, typography,
// logo_url, social_links and footer. URLs are read with the URL API — no regex.
export const NETWORKS = [
  'instagram',
  'facebook',
  'linkedin',
  'youtube',
  'tiktok',
  'x',
  'whatsapp',
];

// Short mark of each network in the lists (no third-party icon).
export const NETWORK_MARKS = {
  facebook: 'f',
  instagram: 'ig',
  linkedin: 'in',
  youtube: 'yt',
  tiktok: 'tt',
  x: 'x',
  whatsapp: 'wa',
};

export const NETWORK_LABELS = {
  facebook: 'Facebook',
  instagram: 'Instagram',
  linkedin: 'LinkedIn',
  youtube: 'YouTube',
  tiktok: 'TikTok',
  x: 'X',
  whatsapp: 'WhatsApp',
};

// The color rows the person sees, in this order (surface follows "Fundo", tint follows both).
export const COLOR_ROWS = [
  'primary',
  'accent',
  'ink',
  'muted',
  'background',
  'band',
];

export const siteHost = url => {
  if (!url) return '';
  try {
    const { hostname } = new URL(url);
    return hostname.startsWith('www.') ? hostname.slice(4) : hostname;
  } catch {
    return url;
  }
};

// "hub2you.ai" → "https://hub2you.ai"; already absolute stays.
export const withScheme = value => {
  const text = String(value || '').trim();
  if (!text) return '';
  return text.startsWith('http://') || text.startsWith('https://')
    ? text
    : `https://${text}`;
};

export const kitFonts = appearance => {
  const { heading_font: heading, body_font: body } =
    appearance?.typography || {};
  return [...new Set([heading, body].filter(Boolean))];
};

export const kitSwatches = appearance => {
  const light = appearance?.palettes?.light || {};
  return ['primary', 'accent', 'ink', 'background'].map(role => light[role]);
};

// Colors found on the site, once each (the "Cores achadas no site" strip).
export const siteColors = appearance => [
  ...new Set(Object.values(appearance?.site_palette || {}).filter(Boolean)),
];

export const kitLogoUrl = kit =>
  kit?.logo?.url || kit?.appearance?.logo_url || '';

// A proposal (site read) or a saved kit → the editable form of the screens.
export const formFromKit = kit => ({
  id: kit.id || null,
  name: kit.name || '',
  sourceUrl: kit.source_url || '',
  appearance: JSON.parse(JSON.stringify(kit.appearance || {})),
  suggested: kit.suggested_palettes || kit.appearance?.palettes || {},
  logoChoice: kit.logo?.url ? 'current' : 'candidate:0',
  logoCandidates: kit.logo_candidates || [],
  currentLogoUrl: kit.logo?.url || '',
  logoFile: null,
  logoPreviewUrl: '',
});

export const formLogoUrl = form => {
  if (form.logoChoice === 'current') return form.currentLogoUrl;
  if (form.logoChoice === 'upload') return form.logoPreviewUrl || '';
  if (form.logoChoice.startsWith('candidate:')) {
    const index = Number(form.logoChoice.split(':')[1]);
    return form.logoCandidates[index]?.url || '';
  }
  return '';
};

// The body of POST/PATCH brand_kits (without the uploaded file, sent as FormData separately).
export const kitPayload = form => {
  const payload = {
    name: form.name.trim(),
    source_url: form.sourceUrl || null,
    appearance: {
      palettes: form.appearance.palettes,
      site_palette: form.appearance.site_palette,
      typography: {
        heading_font: form.appearance.typography?.heading_font || null,
        body_font: form.appearance.typography?.body_font || null,
        google_font_url: form.appearance.typography?.google_font_url || null,
      },
      logo_url: form.appearance.logo_url || null,
      social_links: form.appearance.social_links || [],
      footer: {
        ...form.appearance.footer,
        website: withScheme(form.appearance.footer?.website) || null,
      },
    },
  };
  if (form.logoChoice.startsWith('candidate:')) {
    payload.logo_source_url = formLogoUrl(form) || undefined;
  }
  return payload;
};
