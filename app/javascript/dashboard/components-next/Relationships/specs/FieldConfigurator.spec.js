import { mount, flushPromises } from '@vue/test-utils';
import { ref, defineComponent } from 'vue';
import axios from 'axios';
import historicalInbox from 'dashboard/helper/specs/inboxFixture';
import FieldConfigurator from '../FieldConfigurator.vue';

const context = vi.hoisted(() => ({ account: 100, commit: vi.fn() }));
vi.mock('axios', () => ({ default: { get: vi.fn(), patch: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
  useStore: () => ({
    commit: context.commit,
    subscribe: vi.fn(),
    getters: { getCurrentUserID: 1 },
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(context.account),
    currentAccount: ref({ id: context.account }),
    isCloudFeatureEnabled: () => true,
  }),
}));

beforeEach(() => {
  context.account += 1;
  vi.clearAllMocks();
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
  };
  axios.get.mockResolvedValue({
    data: {
      configuration: { version: 1, revision: 4, surfaces: {} },
      definitions: [],
      can_manage: true,
    },
  });
});
const mountEditor = async () => {
  const wrapper = mount(FieldConfigurator, {
    props: { entity: 'contact' },
    global: { stubs: { teleport: true } },
  });
  await flushPromises();
  await wrapper.find('button').trigger('click');
  await flushPromises();
  return wrapper;
};
const click = async (wrapper, text) => {
  await wrapper
    .findAll('button')
    .find(button => button.text() === text)
    .trigger('click');
  await flushPromises();
};

it('uses the real shared dialog, requires description, and saves definition and layout in one request', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  await wrapper.find('input[type="text"]').setValue('Cargo');
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.find('textarea').setValue('Função na empresa');
  await wrapper.find('input[type="checkbox"]').setValue(true);
  axios.patch.mockResolvedValue({
    data: {
      configuration: { version: 1, revision: 5, surfaces: {} },
      definition: { id: 7, attribute_key: 'cargo' },
    },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(axios.patch).toHaveBeenCalledTimes(1);
  expect(axios.patch.mock.calls[0][1].configuration).toMatchObject({
    revision: 4,
    definition: {
      attribute_key: 'cargo',
      attribute_model: 'contact_attribute',
      attribute_description: 'Função na empresa',
    },
    display_on: ['contact_sidebar'],
  });
  expect(wrapper.find('dialog').element.open).toBe(false);
  wrapper.unmount();
});
it('cancels a draft without creating a partial definition', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  await wrapper.find('input[type="text"]').setValue('Cargo');
  await click(wrapper, 'DIALOG.BUTTONS.CANCEL');
  expect(axios.patch).not.toHaveBeenCalled();
  wrapper.unmount();
});
it('keeps draft and dialog open after a conflict', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  await wrapper.find('input[type="text"]').setValue('Cargo');
  await wrapper.find('textarea').setValue('Função');
  axios.patch.mockRejectedValue({ response: { status: 409 } });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('dialog').element.open).toBe(true);
  expect(wrapper.find('input[type="text"]').element.value).toBe('Cargo');
  expect(wrapper.find('[role="alert"]').text()).toBe('RELATIONSHIPS.CONFLICT');
  wrapper.unmount();
});

it('renames the legacy job_title without sending a replacement key, type or entity', async () => {
  const definition = {
    id: 17,
    attribute_key: 'job_title',
    attribute_model: 'contact_attribute',
    attribute_display_name: 'Job title',
    attribute_description: '',
    attribute_display_type: 'text',
    revision: '2026-09-29T12:00:00.000001Z',
    regex_pattern: historicalInbox.customAttributesWithRegex[0].regex_pattern,
    regex_cue: 'Historical instruction',
    attribute_values: [],
  };
  axios.get.mockResolvedValue({
    data: {
      configuration: { version: 1, revision: 4, surfaces: {} },
      definitions: [definition],
      can_manage: true,
    },
  });
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  await wrapper.find('input[type="text"]').setValue('Cargo');
  axios.patch.mockResolvedValue({
    data: {
      configuration: { revision: 5, surfaces: {} },
      definition: { ...definition, attribute_display_name: 'Cargo' },
    },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  const payload = axios.patch.mock.calls[0][1].configuration.definition;
  expect(payload.id).toBe(17);
  expect(payload.revision).toBe(definition.revision);
  expect(payload.attribute_display_name).toBe('Cargo');
  expect(payload).not.toHaveProperty('attribute_key');
  expect(payload).not.toHaveProperty('attribute_model');
  expect(payload).not.toHaveProperty('attribute_display_type');
  wrapper.unmount();
});

it('does not close a newly opened dialog when a previous save finishes late', async () => {
  let resolve;
  axios.patch.mockImplementation(
    () =>
      new Promise(done => {
        resolve = done;
      })
  );
  const wrapper = await mountEditor();
  await wrapper.find('form').trigger('submit');
  await click(wrapper, 'DIALOG.BUTTONS.CANCEL');
  await wrapper.find('button').trigger('click');
  await flushPromises();
  expect(wrapper.find('dialog').element.open).toBe(true);
  resolve({
    data: { configuration: { revision: 5, surfaces: {} }, definition: null },
  });
  await flushPromises();
  expect(wrapper.find('dialog').element.open).toBe(true);
  wrapper.unmount();
});

it('offers both direct actions and focuses the invoking surface in configure mode', async () => {
  const wrapper = mount(FieldConfigurator, {
    props: { entity: 'contact', surface: 'contact_details' },
    global: { stubs: { teleport: true } },
  });
  await flushPromises();
  const direct = wrapper
    .findAll('button')
    .filter(button => !button.element.closest('dialog'));
  expect(direct.map(button => button.text())).toEqual([
    'RELATIONSHIPS.CONFIGURE',
    'RELATIONSHIPS.CREATE',
  ]);
  await direct[0].trigger('click');
  await flushPromises();
  expect(wrapper.findAll('section h4').map(heading => heading.text())).toEqual([
    'RELATIONSHIPS.SURFACES.contact_details',
  ]);
  await click(wrapper, 'DIALOG.BUTTONS.CANCEL');
  await direct[1].trigger('click');
  await flushPromises();
  expect(wrapper.find('textarea').exists()).toBe(true);
  expect(wrapper.text()).not.toContain('RELATIONSHIPS.REGEX');
  wrapper.unmount();
});

// Match the dashboard bootstrap: feature requests use the configured global client.
const originalDashboardClient = window.axios;
beforeEach(() => {
  window.axios = axios;
});
afterEach(() => {
  window.axios = originalDashboardClient;
});

it('keeps an open creation draft during an offline focus refresh and a failed save, with retry', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  await wrapper.find('input[type="text"]').setValue('Draft name');
  await wrapper.find('textarea').setValue('Draft description');
  axios.get.mockRejectedValueOnce(new Error('offline'));
  window.dispatchEvent(new Event('focus'));
  await flushPromises();
  expect(wrapper.find('dialog').element.open).toBe(true);
  expect(wrapper.find('input[type="text"]').element.value).toBe('Draft name');
  expect(wrapper.find('textarea').element.value).toBe('Draft description');
  axios.patch.mockRejectedValueOnce(new Error('offline'));
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(wrapper.find('input[type="text"]').element.value).toBe('Draft name');
  expect(wrapper.text()).toContain('RELATIONSHIPS.ERROR');
  expect(wrapper.text()).toContain('RELATIONSHIPS.RETRY');
  wrapper.unmount();
});

it.each([401, 403])(
  'closes a draft when focus confirms %s and removes management buttons',
  async status => {
    const wrapper = await mountEditor();
    await click(wrapper, 'RELATIONSHIPS.CREATE');
    await wrapper.find('input[type="text"]').setValue('Draft name');
    axios.get.mockRejectedValueOnce({ response: { status } });
    window.dispatchEvent(new Event('focus'));
    await flushPromises();
    expect(wrapper.find('dialog').element.open).toBe(false);
    expect(wrapper.find('input[type="text"]').exists()).toBe(false);
    expect(
      wrapper
        .findAll('button')
        .some(button => button.text() === 'RELATIONSHIPS.CONFIGURE')
    ).toBe(false);
    wrapper.unmount();
  }
);

it('associates visible creation labels with unique real input IDs across surfaces', async () => {
  const parent = mount(
    defineComponent({
      components: { FieldConfigurator },
      template: '<div><FieldConfigurator /><FieldConfigurator /></div>',
    }),
    { global: { stubs: { teleport: true } } }
  );
  await flushPromises();
  const [first, second] = parent.findAllComponents(FieldConfigurator);
  await click(first, 'RELATIONSHIPS.CONFIGURE');
  await click(second, 'RELATIONSHIPS.CONFIGURE');
  await click(first, 'RELATIONSHIPS.CREATE');
  await click(second, 'RELATIONSHIPS.CREATE');
  const firstInput = first.find('input[type="text"]');
  const secondInput = second.find('input[type="text"]');
  expect(firstInput.attributes('id')).not.toBe(secondInput.attributes('id'));
  expect(
    first.find(`label[for="${firstInput.attributes('id')}"]`).text()
  ).toContain('RELATIONSHIPS.NAME');
  expect(
    first.find(`label[for="${first.find('textarea').attributes('id')}"]`).text()
  ).toContain('RELATIONSHIPS.DESCRIPTION');
  parent.unmount();
});
