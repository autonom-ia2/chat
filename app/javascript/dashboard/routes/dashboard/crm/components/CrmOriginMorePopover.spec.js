import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import CrmKanbanCard from './CrmKanbanCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: { value: 'en' },
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));

const card = {
  id: 9,
  title: 'Seguro viagem',
  campaigns: [
    { source: 'meta_ctwa', headline: 'Cotação Rápida' },
    {
      source: 'meta_paid',
      headline: 'LP Seguro Viagem',
      campaign_name: 'Viagem EUA Outubro',
    },
    { source: 'meta_paid', headline: 'LP Seguro Viagem' },
  ],
};

const flush = async () => {
  await nextTick();
  await nextTick();
};

let wrapper;
const mountCard = () => {
  wrapper = mount(CrmKanbanCard, {
    props: { card },
    attachTo: document.body,
    global: {
      stubs: {
        ChannelIcon: true,
        CardPriorityIcon: true,
        CardLabels: true,
        SLACardLabel: true,
        CrmCardPill: true,
      },
    },
  });
  return wrapper;
};
const trigger = () => wrapper.find('[data-crm-origin-more]');
const popover = () => document.querySelector('[data-crm-origin-popover]');

afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
});

describe('Kanban "+N" origins popover', () => {
  it('is a labelled, collapsed button showing how many more touches there are', () => {
    mountCard();

    expect(trigger().element.tagName).toBe('BUTTON');
    expect(trigger().text()).toBe('+2');
    expect(trigger().attributes('aria-expanded')).toBe('false');
    expect(trigger().attributes('aria-haspopup')).toBe('dialog');
    expect(trigger().attributes('aria-label')).toContain(
      'CRM_KANBAN.ORIGIN.LIST.MORE_ARIA'
    );
  });

  it('opens the list of every touch without opening the card', async () => {
    mountCard();

    await trigger().trigger('click');
    await flush();

    expect(trigger().attributes('aria-expanded')).toBe('true');
    expect(popover()).not.toBeNull();
    expect(popover().id).toBe(trigger().attributes('aria-controls'));
    expect(popover().querySelectorAll('[data-crm-origin-touch]')).toHaveLength(
      3
    );
    expect(wrapper.emitted('open')).toBeUndefined();
  });

  it('moves focus into the popover so its links are reachable', async () => {
    mountCard();

    await trigger().trigger('click');
    await flush();

    expect(document.activeElement).toBe(popover());
  });

  it('closes on Escape and gives the focus back to the "+N"', async () => {
    mountCard();
    await trigger().trigger('click');
    await flush();

    popover().dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    await flush();

    expect(popover()).toBeNull();
    expect(trigger().attributes('aria-expanded')).toBe('false');
    expect(document.activeElement).toBe(trigger().element);
  });

  describe('with the keyboard, Tab never leaves the board', () => {
    const linkedCard = {
      ...card,
      campaigns: [
        card.campaigns[0],
        {
          ...card.campaigns[1],
          source_url: 'https://www.instagram.com/p/C9xYz12AbCd/',
        },
        card.campaigns[2],
      ],
    };
    const tab = (target, shiftKey = false) => {
      const event = new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey,
        bubbles: true,
        cancelable: true,
      });
      target.dispatchEvent(event);
      return event;
    };
    const openWith = async cardProps => {
      wrapper = mount(CrmKanbanCard, {
        props: { card: cardProps },
        attachTo: document.body,
        global: {
          stubs: {
            ChannelIcon: true,
            CardPriorityIcon: true,
            CardLabels: true,
            SLACardLabel: true,
            CrmCardPill: true,
          },
        },
      });
      await trigger().trigger('click');
      await flush();
    };

    it('lets Tab move from the popover to its link', async () => {
      await openWith(linkedCard);

      const event = tab(popover());
      await flush();

      expect(event.defaultPrevented).toBe(false);
      expect(popover()).not.toBeNull();
    });

    it('closes on Tab past the last link and gives the focus back to the "+N"', async () => {
      await openWith(linkedCard);
      const link = popover().querySelector('a[href]');
      link.focus();

      const event = tab(link);
      await flush();

      expect(event.defaultPrevented).toBe(true);
      expect(popover()).toBeNull();
      expect(trigger().attributes('aria-expanded')).toBe('false');
      expect(document.activeElement).toBe(trigger().element);
    });

    it('closes on Shift+Tab from the start of the popover', async () => {
      await openWith(linkedCard);

      const event = tab(popover(), true);
      await flush();

      expect(event.defaultPrevented).toBe(true);
      expect(popover()).toBeNull();
      expect(document.activeElement).toBe(trigger().element);
    });

    it('closes on Tab when the popover has no link at all', async () => {
      await openWith(card);

      tab(popover());
      await flush();

      expect(popover()).toBeNull();
      expect(document.activeElement).toBe(trigger().element);
    });
  });

  it('closes on a click outside', async () => {
    mountCard();
    await trigger().trigger('click');
    await flush();

    document.body.dispatchEvent(
      new PointerEvent('pointerdown', { bubbles: true })
    );
    document.body.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await flush();

    expect(popover()).toBeNull();
  });

  it('has no "+N" when the contact has a single touch', () => {
    wrapper = mount(CrmKanbanCard, {
      props: { card: { ...card, campaigns: [card.campaigns[0]] } },
      global: {
        stubs: {
          ChannelIcon: true,
          CardPriorityIcon: true,
          CardLabels: true,
          SLACardLabel: true,
          CrmCardPill: true,
        },
      },
    });

    expect(trigger().exists()).toBe(false);
  });
});
