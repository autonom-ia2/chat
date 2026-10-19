import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import AddLabel from '../AddLabel.vue';
import EditLabel from '../EditLabel.vue';

vi.mock('dashboard/api/nomesDeEtiquetas', () => ({
  default: { listar: vi.fn(), gravar: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

let contaDoTeste = 200;

// Store mínima: as etiquetas, a flag e as ações que o formulário dispara.
const montar = (Componente, { ligada = true, props = {} } = {}) => {
  contaDoTeste += 1;
  const conta = contaDoTeste;
  const etiquetas = [{ id: 7, title: 'aguardando_retorno' }];
  const acoes = {
    create: vi.fn((_, novo) => etiquetas.push({ id: 8, ...novo })),
    update: vi.fn(),
  };
  const store = createStore({
    getters: {
      getCurrentAccountId: () => conta,
      'accounts/isFeatureEnabledonAccount': () => () => ligada,
      'labels/getLabels': () => etiquetas,
      'labels/getUIFlags': () => ({}),
    },
    actions: {
      'labels/create': acoes.create,
      'labels/update': acoes.update,
    },
  });
  const wrapper = mount(Componente, {
    props,
    global: {
      plugins: [store],
      stubs: { WootInput: true, WootColorPicker: true },
    },
  });
  return { wrapper, acoes };
};

describe('label form with the free name (#1823)', () => {
  beforeEach(() => {
    NomesDeEtiquetasAPI.listar.mockResolvedValue({ data: { payload: [] } });
    NomesDeEtiquetasAPI.gravar.mockImplementation((id, nome) =>
      Promise.resolve({ data: { payload: { label_id: id, nome } } })
    );
  });

  it('creates the label with the technical title and saves the free name', async () => {
    const { wrapper, acoes } = montar(AddLabel, {
      props: { prefillTitle: 'Novo Cliente 🔥' },
    });
    await flushPromises();

    expect(wrapper.vm.tituloTecnico).toBe('novo_cliente');
    await wrapper.vm.addLabel();
    await flushPromises();

    expect(acoes.create.mock.calls[0][1].title).toBe('novo_cliente');
    expect(NomesDeEtiquetasAPI.gravar).toHaveBeenCalledWith(
      8,
      'Novo Cliente 🔥'
    );
  });

  const ETIQUETA = { id: 7, title: 'aguardando_retorno', color: '#000' };

  it('saves nothing but the label fields when the name is untouched', async () => {
    const { wrapper, acoes } = montar(EditLabel, {
      props: { selectedResponse: ETIQUETA },
    });
    await flushPromises();

    expect(wrapper.vm.title).toBe('Aguardando retorno');
    await wrapper.vm.editLabel();
    await flushPromises();

    expect(acoes.update.mock.calls[0][1]).not.toHaveProperty('title');
    expect(NomesDeEtiquetasAPI.gravar).not.toHaveBeenCalled();
  });

  it('edits only the free name and never sends the title', async () => {
    const { wrapper, acoes } = montar(EditLabel, {
      props: { selectedResponse: ETIQUETA },
    });
    await flushPromises();

    wrapper.vm.title = 'Esperando o cliente';
    await wrapper.vm.editLabel();
    await flushPromises();

    expect(acoes.update.mock.calls[0][1]).toEqual({
      id: 7,
      color: '#000',
      description: undefined,
      show_on_sidebar: undefined,
    });
    expect(NomesDeEtiquetasAPI.gravar).toHaveBeenCalledWith(
      7,
      'Esperando o cliente'
    );
  });

  it('renames the title like Chatwoot with the flag off', async () => {
    const { wrapper, acoes } = montar(EditLabel, {
      ligada: false,
      props: { selectedResponse: ETIQUETA },
    });
    await flushPromises();

    expect(wrapper.vm.title).toBe('aguardando_retorno');
    wrapper.vm.title = 'Esperando';
    await wrapper.vm.editLabel();
    await flushPromises();

    expect(acoes.update.mock.calls[0][1].title).toBe('esperando');
    expect(NomesDeEtiquetasAPI.gravar).not.toHaveBeenCalled();
  });

  it('keeps the Chatwoot form with the flag off', async () => {
    const { wrapper, acoes } = montar(AddLabel, {
      ligada: false,
      props: { prefillTitle: 'Lead' },
    });
    await flushPromises();

    expect(wrapper.vm.title).toBe('lead');
    await wrapper.vm.addLabel();
    await flushPromises();

    expect(acoes.create.mock.calls[0][1].title).toBe('lead');
    expect(NomesDeEtiquetasAPI.gravar).not.toHaveBeenCalled();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });
});
