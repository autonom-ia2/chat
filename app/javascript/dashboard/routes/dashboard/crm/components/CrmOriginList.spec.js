import { mount } from '@vue/test-utils';
import CrmOriginList from './CrmOriginList.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}(${params.name ?? params.id})` : key),
    locale: { value: 'pt_BR' },
  }),
}));

const ctwaTouch = {
  source: 'meta_ctwa',
  headline: 'Cotação Rápida',
  source_url: 'https://www.instagram.com/p/C9xYz12AbCd/',
  campaign_name: 'Seguro Viagem · Julho',
  touched_at: '2026-07-10T14:32:00Z',
};
const siteTouch = {
  source: 'meta_paid',
  headline: 'LP Seguro Viagem · 120254710067060416',
  source_url: 'https://placement.com.br/seguro-viagem',
  utm_campaign: '120254710067060416',
  utm_term: '120254710067060417',
  touched_at: '2026-07-14T19:05:00Z',
};

// Built in two parts: the lint forbids a literal script URL, even in a test.
const SCRIPT_SCHEME = ['java', 'script:'].join('');

const mountList = campaigns => mount(CrmOriginList, { props: { campaigns } });

describe('CrmOriginList', () => {
  it('lists every touch in the order received, marking first and last', () => {
    const wrapper = mountList([ctwaTouch, siteTouch]);
    const touches = wrapper.findAll('[data-crm-origin-touch]');

    expect(touches).toHaveLength(2);
    expect(touches[0].text()).toContain('CRM_KANBAN.ORIGIN.META_CTWA');
    expect(touches[0].text()).toContain('CRM_KANBAN.ORIGIN.LIST.FIRST');
    expect(touches[1].text()).toContain(
      'CRM_KANBAN.ORIGIN.META_PAID: LP Seguro Viagem'
    );
    expect(touches[1].text()).toContain('CRM_KANBAN.ORIGIN.LIST.LAST');
  });

  it('shows a short date with the full one in the title', () => {
    const time = mountList([ctwaTouch]).find('time');

    expect(time.attributes('datetime')).toBe('2026-07-10T14:32:00.000Z');
    expect(time.text()).toBe('10/07');
    expect(time.attributes('title')).toContain('2026');
  });

  it('shows only the levels the touch has, IDs shortened', () => {
    const wrapper = mountList([siteTouch]);
    const levels = wrapper.findAll('[data-crm-origin-level]');

    expect(
      levels.map(level => level.attributes('data-crm-origin-level'))
    ).toEqual(['campaign', 'adset']);
    expect(levels[0].text()).toBe('CRM_KANBAN.ORIGIN.META_ID(1202…0416)');
    expect(levels[0].attributes('title')).toBe('120254710067060416');
  });

  it('links the post in a new tab without giving it the opener', () => {
    const link = mountList([ctwaTouch]).find('a');

    expect(link.attributes('href')).toBe(ctwaTouch.source_url);
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toContain('noopener');
    expect(link.text()).toContain('CRM_KANBAN.ORIGIN.INSTAGRAM_POST');
  });

  it('has no link when the touch has no source_url, and no marker alone', () => {
    const wrapper = mountList([{ ...siteTouch, source_url: '' }]);

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('CRM_KANBAN.ORIGIN.LIST.FIRST');
  });

  it.each([
    `${SCRIPT_SCHEME}//x.com/%0aalert(1)`,
    `${SCRIPT_SCHEME}//instagram.com/%0aalert(1)`,
    'data:text/html,<script>alert(1)</script>',
  ])('never turns a non-http source_url into a link: %s', sourceUrl => {
    const wrapper = mountList([{ ...ctwaTouch, source_url: sourceUrl }]);

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.html()).not.toContain(SCRIPT_SCHEME);
  });

  it('never lists more than 20 touches', () => {
    const many = Array.from({ length: 25 }, (_, index) => ({
      ...siteTouch,
      source_id: `site:${index}`,
    }));

    expect(mountList(many).findAll('[data-crm-origin-touch]')).toHaveLength(20);
  });
});
