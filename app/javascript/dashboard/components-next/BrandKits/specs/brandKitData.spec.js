import {
  formFromKit,
  formLogoUrl,
  kitPayload,
  siteHost,
} from '../brandKitData';

const proposal = {
  name: 'Hub2You',
  source_url: 'https://hub2you.ai/',
  appearance: {
    palettes: { light: { primary: '#c8102e' }, dark: { primary: '#ff1f2d' } },
    site_palette: { primary: '#ff1f2d' },
    typography: { heading_font: 'MuseoModerno', body_font: 'Roboto' },
    social_links: [],
    footer: { company_name: 'Hub2You', website: 'hub2you.ai' },
  },
  logo_candidates: [
    { url: 'https://hub2you.ai/logo.png', source: 'page_logo' },
  ],
};

describe('identity form (#1076)', () => {
  it('saves a site reading with the chosen logo for the server to download', () => {
    const payload = kitPayload(formFromKit(proposal));

    expect(payload).toMatchObject({
      name: 'Hub2You',
      source_url: 'https://hub2you.ai/',
      logo_source_url: 'https://hub2you.ai/logo.png',
    });
    expect(payload.appearance.footer.website).toBe('https://hub2you.ai');
    expect(payload.appearance.palettes.dark.primary).toBe('#ff1f2d');
  });

  it('keeps the stored logo of a saved identity (no download)', () => {
    const form = formFromKit({
      id: 3,
      name: 'Hub2You',
      appearance: proposal.appearance,
      logo: { url: '/rails/active_storage/blobs/x/logo.png' },
    });

    expect(form.logoChoice).toBe('current');
    expect(formLogoUrl(form)).toBe('/rails/active_storage/blobs/x/logo.png');
    expect(kitPayload(form).logo_source_url).toBeUndefined();
  });

  it('shows the site by its host', () => {
    expect(siteHost('https://www.hub2you.ai/home')).toBe('hub2you.ai');
    expect(siteHost('')).toBe('');
  });
});
