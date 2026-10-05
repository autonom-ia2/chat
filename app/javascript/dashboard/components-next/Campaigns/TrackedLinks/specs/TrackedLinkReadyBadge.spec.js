import { mount } from '@vue/test-utils';
import TrackedLinkReadyBadge from '../TrackedLinkReadyBadge.vue';

const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const website = (overrides = {}) => ({
  usage: 'website',
  allowed_origins: ['https://placement.com.br'],
  last_signal_at: new Date(Date.now() - 6 * 60 * 1000).toISOString(),
  ...overrides,
});
const badge = link => mount(TrackedLinkReadyBadge, { props: { link } });

describe('TrackedLinkReadyBadge', () => {
  it('says ready only when the site is already sending signals', () => {
    const wrapper = badge(website());

    expect(wrapper.text()).toBe(`${NS}.READY_WEBSITE`);
    expect(wrapper.classes()).toContain('text-n-slate-11');
  });

  it('also says ready when the last signal is old', () => {
    const wrapper = badge(website({ last_signal_at: '2020-01-01T00:00:00Z' }));

    expect(wrapper.text()).toBe(`${NS}.READY_WEBSITE`);
  });

  it('waits for the first click, in a neutral tone, before any signal', () => {
    const wrapper = badge(website({ last_signal_at: null }));

    expect(wrapper.text()).toBe(`${NS}.WEBSITE_WAITING`);
    expect(wrapper.text()).not.toContain('READY');
    expect(wrapper.classes()).toContain('text-n-slate-11');
  });

  it('asks to allow the site, in amber, when no origin is allowed', () => {
    const wrapper = badge(website({ allowed_origins: [] }));

    expect(wrapper.text()).toBe(`${NS}.WEBSITE_NEEDS_ORIGINS`);
    expect(wrapper.classes()).toContain('text-n-amber-11');
  });

  it('keeps the share wording for a QR code origin', () => {
    const wrapper = badge({ usage: 'direct' });

    expect(wrapper.text()).toBe(`${NS}.READY`);
    expect(wrapper.find('.i-lucide-qr-code').exists()).toBe(true);
  });
});
