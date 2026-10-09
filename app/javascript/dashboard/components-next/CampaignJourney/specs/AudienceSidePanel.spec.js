import { flushPromises, mount } from '@vue/test-utils';
import AudienceSidePanel from '../AudienceSidePanel.vue';
import SidePanel from '../../side-panel/SidePanel.vue';
import { audiencesAPI } from 'dashboard/api/campaignJourney';

vi.mock('dashboard/api/campaignJourney', () => ({
  audiencesAPI: {
    show: vi.fn(),
    contacts: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params = {}) =>
      params.count === undefined ? key : `${key}:${params.count}`,
    locale: { value: 'en' },
  }),
}));

const ButtonStub = {
  inheritAttrs: false,
  props: {
    label: { type: [String, Number], default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['click'],
  template:
    '<button v-bind="$attrs" :disabled="disabled" type="button" @click="$emit(\'click\')">{{ label }}</button>',
};

const detail = {
  name: 'Público da campanha',
  valid_rows: 3,
  channels: [],
  linked_campaigns: [],
  extra_columns: [],
  reachability: null,
  can_delete: true,
  status: 'completed',
};

const mountAudience = (props = {}) => {
  audiencesAPI.show.mockResolvedValue({ data: { payload: detail } });
  return mount(AudienceSidePanel, {
    props: { audienceId: 7, canManage: true, ...props },
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: ButtonStub,
        Spinner: true,
        AudienceChannelBadges: true,
        RouterLink: { template: '<a><slot /></a>' },
        TeleportWithDirection: { template: '<div><slot /></div>' },
        Transition: false,
      },
    },
  });
};

const openAudience = async wrapper => {
  await flushPromises();
  await vi.waitFor(() => {
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
  });
  return wrapper.get('[role="dialog"]');
};

describe('AudienceSidePanel shared SidePanel adapter (D9/F0)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('mounts the real shared panel while preserving legacy width and the 44px close target', async () => {
    const wrapper = mountAudience();
    const dialog = await openAudience(wrapper);

    const panel = wrapper.findComponent(SidePanel);
    expect(panel.exists()).toBe(true);
    expect(dialog.classes()).toContain('sm:w-[37rem]');
    expect(wrapper.props()).toMatchObject({ audienceId: 7, canManage: true });
    const closeButton = wrapper.get('[data-test="panel-close"]');
    expect(closeButton.attributes('data-autofocus')).toBeDefined();
    expect(closeButton.classes()).toEqual(
      expect.arrayContaining(['!min-h-11', '!min-w-11'])
    );
    await vi.waitFor(() =>
      expect(document.activeElement).toBe(closeButton.element)
    );
    wrapper.unmount();
  });

  it('emits public close only after real afterLeave and restores the opener once', async () => {
    const opener = document.createElement('button');
    document.body.appendChild(opener);
    opener.focus();
    const wrapper = mountAudience();
    await openAudience(wrapper);
    const panel = wrapper.findComponent(SidePanel);
    const closeButton = wrapper.get('[data-test="panel-close"]');

    expect(panel.exists()).toBe(true);
    await vi.waitFor(() =>
      expect(document.activeElement).toBe(closeButton.element)
    );

    panel.vm.close();
    await flushPromises();
    expect(wrapper.emitted('close')).toBeUndefined();

    await vi.waitFor(() => {
      expect(panel.emitted('afterLeave')).toHaveLength(1);
      expect(wrapper.emitted('close')).toEqual([[]]);
    });
    expect(document.activeElement).toBe(opener);
    await flushPromises();
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
    opener.remove();
  });

  it('preserves use and delete events with the audience id and name', async () => {
    const wrapper = mountAudience();
    await openAudience(wrapper);

    await wrapper.get('[data-test="panel-delete"]').trigger('click');
    await wrapper.get('[data-test="panel-use"]').trigger('click');

    expect(wrapper.emitted('delete')).toEqual([
      [{ id: 7, name: 'Público da campanha' }],
    ]);
    expect(wrapper.emitted('use')).toEqual([[{ id: 7 }]]);
    wrapper.unmount();
  });
});
