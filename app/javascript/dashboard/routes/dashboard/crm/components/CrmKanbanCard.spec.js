import { mount } from '@vue/test-utils';
import CrmKanbanCard from './CrmKanbanCard.vue';

// The card renders i18n keys + account labels from the store; stub both so we can
// mount in isolation and assert the click routing the "open conversation from the
// bubble" feature introduced (bubble -> openConversation, rest of card -> open).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));

const CONVERSATION_CARD = {
  id: 5,
  title: 'Card A',
  last_message_at: 1700000000,
  conversation: { id: 99, display_id: 42 },
};

const NO_CONVERSATION_CARD = {
  id: 6,
  title: 'Card B',
  last_message_at: 1700000000,
};

const mountCard = (card = CONVERSATION_CARD, props = {}) =>
  mount(CrmKanbanCard, {
    props: { card, stageColor: '#2563eb', ...props },
    global: {
      stubs: {
        Avatar: true,
        ChannelIcon: true,
        CardPriorityIcon: true,
        CardLabels: true,
        SLACardLabel: true,
        CrmCardPill: true,
      },
    },
  });

describe('CrmKanbanCard bubble shortcut', () => {
  it('renders the last-message bubble as a conversation button when a linked conversation exists', () => {
    const wrapper = mountCard();

    expect(wrapper.find('button.crm-card-open-conversation').exists()).toBe(
      true
    );
  });

  it('emits openConversation (and NOT open) when the bubble is clicked', async () => {
    const wrapper = mountCard();

    await wrapper.find('button.crm-card-open-conversation').trigger('click');

    expect(wrapper.emitted('openConversation')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')[0]).toEqual([CONVERSATION_CARD]);
    expect(wrapper.emitted('open')).toBeUndefined();
  });

  it('emits open when the card content is clicked', async () => {
    const wrapper = mountCard();

    // Content wrapper carries the drawer @click; clicking a content element
    // must bubble to it and open the drawer.
    await wrapper.find('div.relative.z-10').trigger('click');

    expect(wrapper.emitted('open')).toHaveLength(1);
    expect(wrapper.emitted('open')[0]).toEqual([CONVERSATION_CARD]);
    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  it('emits open from the stretched primary button', async () => {
    const wrapper = mountCard();

    await wrapper
      .find('button[aria-label^="CRM_KANBAN.CARD.OPEN_DETAILS"]')
      .trigger('click');

    expect(wrapper.emitted('open')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });

  const scoreChip = wrapper =>
    wrapper.find('button[aria-label^="CRM_KANBAN.CARD.SCORE_ARIA"]');

  it('renders no score chip when the card has no score', () => {
    expect(scoreChip(mountCard(CONVERSATION_CARD)).exists()).toBe(false);
  });

  it('renders the urgent tier filled, with the reason in the aria label', () => {
    const wrapper = mountCard({
      ...CONVERSATION_CARD,
      score: 95,
      metadata: {
        ai: {
          score: { source: 'ai', reason: 'Link prometido e nunca enviado' },
        },
      },
    });
    const chip = scoreChip(wrapper);

    expect(chip.text()).toContain('95');
    expect(chip.classes()).toContain('bg-n-ruby-9');
    expect(chip.attributes('aria-label')).toContain(
      'Link prometido e nunca enviado'
    );
  });

  it('picks the tier by value: 12 cold, 45 warm, 62 hot', () => {
    const tierClass = score =>
      scoreChip(mountCard({ ...CONVERSATION_CARD, score })).classes();

    expect(tierClass(12)).toContain('bg-n-alpha-2');
    expect(tierClass(45)).toContain('bg-n-blue-3');
    expect(tierClass(62)).toContain('bg-n-amber-3');
  });

  it('outlines the chip when the score was set by a human', () => {
    const wrapper = mountCard({
      ...CONVERSATION_CARD,
      score: 40,
      metadata: { ai: { score: { source: 'manual' } } },
    });
    const chip = scoreChip(wrapper);

    expect(chip.classes()).toContain('ring-n-blue-8');
    expect(chip.classes()).not.toContain('bg-n-blue-3');
  });

  it('keeps the bubble as a plain label (no shortcut) when the card has no conversation', async () => {
    const wrapper = mountCard(NO_CONVERSATION_CARD);

    expect(wrapper.find('button.crm-card-open-conversation').exists()).toBe(
      false
    );

    // The plain label click still bubbles up to the content wrapper -> open.
    await wrapper.find('div.relative.z-10').trigger('click');
    expect(wrapper.emitted('open')).toHaveLength(1);
    expect(wrapper.emitted('openConversation')).toBeUndefined();
  });
});
