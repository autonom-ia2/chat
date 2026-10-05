import { mount } from '@vue/test-utils';
import TrackedLinkCampaignTable from '../TrackedLinkCampaignTable.vue';

const campaigns = [
  {
    campaign_key: 'c:1a2b3c4d5e',
    name: 'Europa 60+',
    clicks: 12,
    conversations: 9,
    won_cards: 1,
    won_value_by_currency: { BRL: 37780 },
  },
  {
    campaign_key: '120211',
    name: 'Viagem EUA Outubro',
    clicks: 40,
    conversations: 31,
    won_cards: 4,
    won_value_by_currency: { BRL: 151120 },
  },
  {
    campaign_key: 'none',
    name: null,
    clicks: 3,
    conversations: 2,
    won_cards: 0,
    won_value_by_currency: {},
  },
];

describe('TrackedLinkCampaignTable', () => {
  it('lists campaigns with clicks, conversations, won cards and value', () => {
    const wrapper = mount(TrackedLinkCampaignTable, {
      props: { campaigns, originName: 'LP Seguro Viagem' },
    });
    const items = wrapper.findAll('[data-testid="tracked-link-campaign"]');
    const cell = (item, id) =>
      item.get(`[data-testid="tracked-link-campaign-${id}"]`).text();

    expect(items).toHaveLength(3);
    expect(cell(items[0], 'name')).toBe('Viagem EUA Outubro');
    expect(cell(items[0], 'clicks')).toContain('40');
    expect(cell(items[0], 'conversations')).toContain('31');
    expect(cell(items[0], 'won')).toContain('4');
    expect(cell(items[0], 'value')).toContain('1,511.20');
    expect(cell(items[1], 'name')).toBe('Europa 60+');
    expect(cell(items[2], 'name')).toBe(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.NO_CAMPAIGN'
    );
    expect(cell(items[2], 'value')).toContain('—');
  });

  it('keeps every number visible without a wide, scrolling table', () => {
    const wrapper = mount(TrackedLinkCampaignTable, {
      props: { campaigns },
    });

    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.html()).not.toContain('overflow-x-auto');
    expect(wrapper.html()).not.toContain('min-w-[');
  });

  it('does not reorder the array it received', () => {
    const input = [...campaigns];
    mount(TrackedLinkCampaignTable, { props: { campaigns: input } });

    expect(input.map(campaign => campaign.campaign_key)).toEqual([
      'c:1a2b3c4d5e',
      '120211',
      'none',
    ]);
  });

  it('shows a designed empty state with no campaigns', () => {
    const wrapper = mount(TrackedLinkCampaignTable, {
      props: { campaigns: [] },
    });

    expect(wrapper.find('[data-testid="tracked-link-campaign"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.CAMPAIGNS_EMPTY_TITLE'
    );
  });
});
