import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import { createStore } from 'vuex';
import MoreActions from '../MoreActions.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

// vitest loads @vueuse/core with its own copy of Vue, so its refs would not re-render the menu.
vi.mock('@vueuse/core', () => ({
  useToggle: () => {
    const value = ref(false);
    const toggle = next => {
      value.value = typeof next === 'boolean' ? next : !value.value;
    };
    return [value, toggle];
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

const DropdownMenuStub = {
  props: { menuItems: { type: Array, default: () => [] } },
  emits: ['action'],
  template: `
    <div>
      <button
        v-for="item in menuItems"
        :key="item.action"
        :data-action="item.action"
        @click="$emit('action', item)"
      >
        {{ item.label }}
        <slot name="trailing-icon" :item="item" />
      </button>
    </div>
  `,
};

const ItensDoTopoStub = {
  template: '<div />',
  setup(_, { expose }) {
    expose({ itens: [], agir: () => false });
    return {};
  },
};

const mountMoreActions = ({ autoTranslate, setAutoTranslate = vi.fn() }) => {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ id: 1, status: 'open', muted: false }),
      getAutoTranslate: () => ({
        enabled: true,
        language: 'Turkish',
        disabledInConversation: false,
        ...autoTranslate,
      }),
    },
    actions: { setConversationAutoTranslate: setAutoTranslate },
  });

  return mount(MoreActions, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      directives: { onClickaway: {}, tooltip: {} },
      stubs: {
        ResolveAction: true,
        EmailTranscriptModal: true,
        ButtonV4: { template: '<button data-more />' },
        DropdownMenu: DropdownMenuStub,
        // Fork (upgrade 4.20.1, #3120): the fork's contact-panel items (#2138) read the store;
        // stubbed with no items so only the upstream menu is under test.
        ItensDoTopo: ItensDoTopoStub,
      },
    },
  });
};

const openMenu = async wrapper => {
  await wrapper.find('[data-more]').trigger('click');
};

// Fork (upgrade 4.20.1, #3120): the per-conversation switch stays out of the menu (see MoreActions.vue).
describe('MoreActions auto-translate switch', () => {
  beforeEach(() => {
    useAlert.mockClear();
  });

  it('stays out of the menu while auto-translate is on for the account', async () => {
    const wrapper = mountMoreActions({});
    await openMenu(wrapper);

    expect(wrapper.find('[data-action="auto_translate"]').exists()).toBe(false);
    expect(wrapper.find('[data-action="send_transcript"]').exists()).toBe(true);
  });

  it('stays out of the menu while auto-translate is off for the account', async () => {
    const wrapper = mountMoreActions({ autoTranslate: { enabled: false } });
    await openMenu(wrapper);

    expect(wrapper.find('[data-action="auto_translate"]').exists()).toBe(false);
  });
});
