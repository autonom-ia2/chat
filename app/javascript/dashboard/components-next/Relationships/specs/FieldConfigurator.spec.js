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
// #2435: a chave de uma área pelo nome dela; "Mostrar na tela" é a que tem título.
const areaSwitch = (wrapper, surface) =>
  wrapper.find(
    `[role="switch"][aria-label="RELATIONSHIPS.SURFACES.${surface}"]`
  );
const mostrarNaTela = wrapper =>
  wrapper.find('[role="switch"][aria-labelledby$="-titulo"]');
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
  expect(wrapper.text()).not.toContain('RELATIONSHIPS.KEY');
  expect(
    wrapper.find('button[type="submit"]').attributes('disabled')
  ).toBeDefined();
  await wrapper.find('textarea').setValue('Função na empresa');
  await areaSwitch(wrapper, 'contact_sidebar').trigger('click');
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

it('shows a contextual title and save label when the shared dialog changes from selection to creation', async () => {
  const wrapper = await mountEditor();
  expect(wrapper.find('dialog h3').text()).toBe('RELATIONSHIPS.CONFIGURE');
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  expect(wrapper.find('dialog h3').text()).toBe('RELATIONSHIPS.CREATE');
  expect(wrapper.find('button[type="submit"]').text()).toBe(
    'RELATIONSHIPS.SAVE_ATTRIBUTE'
  );
  // As duas áreas do contato e o "Mostrar na tela" (#2435).
  expect(wrapper.findAll('[role="switch"]')).toHaveLength(3);
  wrapper.unmount();
});

it('lets the central header own its actions without rendering duplicate creation buttons', async () => {
  const wrapper = mount(FieldConfigurator, {
    props: { entity: 'company', showActions: false },
    global: { stubs: { teleport: true } },
  });
  await flushPromises();
  expect(
    wrapper
      .findAll('button')
      .filter(button => !button.element.closest('dialog'))
  ).toHaveLength(0);
  await wrapper.vm.open(null, true);
  await flushPromises();
  expect(wrapper.find('dialog h3').text()).toBe(
    'RELATIONSHIPS.CREATE_COMPANY_ATTRIBUTE'
  );
  // A área da empresa e o "Mostrar na tela" (#2435).
  expect(wrapper.findAll('[role="switch"]')).toHaveLength(2);
  expect(areaSwitch(wrapper, 'company_details').exists()).toBe(true);
  wrapper.unmount();
});

// #2435: o editor de Relacionamentos também liga e desliga "Mostrar na tela".
it('sends oculto_na_tela when "Mostrar na tela" is turned off', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  await wrapper.find('input[type="text"]').setValue('Contador');
  await wrapper.find('textarea').setValue('Usado pela automação');
  const mostrar = mostrarNaTela(wrapper);
  expect(mostrar.attributes('aria-checked')).toBe('true');
  await mostrar.trigger('click');
  axios.patch.mockResolvedValue({
    data: { configuration: { revision: 5, surfaces: {} }, definition: {} },
  });
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(
    axios.patch.mock.calls[0][1].configuration.definition.oculto_na_tela
  ).toBe(true);
  wrapper.unmount();
});

it('opens a hidden attribute with "Mostrar na tela" off', async () => {
  axios.get.mockResolvedValue({
    data: {
      configuration: { version: 1, revision: 4, surfaces: {} },
      definitions: [
        {
          id: 21,
          attribute_key: 'contador',
          attribute_model: 'contact_attribute',
          attribute_display_name: 'Contador',
          attribute_description: 'Usado pela automação',
          attribute_display_type: 'number',
          revision: '2026-11-12T12:00:00.000001Z',
          attribute_values: [],
          oculto_na_tela: true,
        },
      ],
      can_manage: true,
    },
  });
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.EDIT');
  expect(mostrarNaTela(wrapper).attributes('aria-checked')).toBe('false');
  wrapper.unmount();
});

// #2435: uma regra só na tela. Com "Mostrar na tela" desligado, as áreas somem
// e uma frase diz que o campo está fora de todas; ligado de novo, elas voltam.
it('hides the per-area switches while "Mostrar na tela" is off', async () => {
  const wrapper = await mountEditor();
  await click(wrapper, 'RELATIONSHIPS.CREATE');
  expect(areaSwitch(wrapper, 'contact_sidebar').exists()).toBe(true);
  await mostrarNaTela(wrapper).trigger('click');
  expect(areaSwitch(wrapper, 'contact_sidebar').exists()).toBe(false);
  expect(wrapper.text()).toContain(
    'ATTRIBUTES_MGMT.MOSTRAR_NA_TELA.ESCONDIDO_DE_TODAS'
  );
  await mostrarNaTela(wrapper).trigger('click');
  expect(areaSwitch(wrapper, 'contact_sidebar').exists()).toBe(true);
  expect(wrapper.text()).not.toContain(
    'ATTRIBUTES_MGMT.MOSTRAR_NA_TELA.ESCONDIDO_DE_TODAS'
  );
  wrapper.unmount();
});

// #2435: na lista do Configurar, o campo fora da tela leva o selo e fica com a
// chave desligada e travada, mesmo marcado na área (a conta "X de Y" usa a
// mesma regra, `shown`).
it('marks a hidden attribute in the configure list and leaves it out of the count', async () => {
  const definicao = (id, nome, extra = {}) => ({
    id,
    attribute_key: nome.toLowerCase(),
    attribute_model: 'contact_attribute',
    attribute_display_name: nome,
    attribute_description: '',
    attribute_display_type: 'text',
    revision: '2026-11-12T12:00:00.000001Z',
    attribute_values: [],
    ...extra,
  });
  axios.get.mockResolvedValue({
    data: {
      configuration: {
        version: 1,
        revision: 4,
        surfaces: { contact_sidebar: { mode: 'custom', ids: [31, 32] } },
      },
      definitions: [
        definicao(31, 'Plano'),
        definicao(32, 'Contador', { oculto_na_tela: true }),
      ],
      can_manage: true,
    },
  });
  const wrapper = await mountEditor();
  const linhas = wrapper.findAll('section .rounded-lg.border');
  const contador = linhas.find(linha => linha.text().includes('Contador'));
  const plano = linhas.find(linha => linha.text().includes('Plano'));
  expect(contador.text()).toContain('ATTRIBUTES_MGMT.BADGES.OCULTO');
  expect(plano.text()).not.toContain('ATTRIBUTES_MGMT.BADGES.OCULTO');
  const chave = contador.find('[role="switch"]');
  expect(chave.attributes('aria-checked')).toBe('false');
  expect(chave.attributes('disabled')).toBeDefined();
  expect(plano.find('[role="switch"]').attributes('aria-checked')).toBe('true');
  wrapper.unmount();
});
