import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import NomesDeEtiquetasAPI from 'dashboard/api/nomesDeEtiquetas';
import LabelDropdown from '../LabelDropdown.vue';

vi.mock('dashboard/api/nomesDeEtiquetas', () => ({
  default: { listar: vi.fn() },
}));

const ETIQUETAS = [
  { id: 1, title: 'aguardando_retorno', color: '#000' },
  { id: 2, title: 'vip', color: '#111' },
];

let contaDoTeste = 100;

const montar = ({ ligada }) => {
  contaDoTeste += 1;
  const conta = contaDoTeste;
  const store = createStore({
    getters: {
      getCurrentAccountId: () => conta,
      'accounts/isFeatureEnabledonAccount': () => () => ligada,
      'labels/getLabels': () => ETIQUETAS,
    },
  });
  return mount(LabelDropdown, {
    props: { accountLabels: ETIQUETAS, allowCreation: true },
    global: {
      plugins: [store],
      stubs: {
        Hotkey: true,
        LabelDropdownItem: true,
        AddLabelModal: true,
        WootDropdownMenu: { template: '<div><slot /></div>' },
        WootModal: true,
        NextButton: true,
      },
    },
  });
};

const digitar = async (wrapper, texto) => {
  wrapper.vm.search = texto;
  await wrapper.vm.$nextTick();
  await new Promise(resolve => {
    setTimeout(resolve, 0);
  });
};

describe('LabelDropdown with the free label name (#1823)', () => {
  beforeEach(() => {
    NomesDeEtiquetasAPI.listar.mockResolvedValue({
      data: { payload: [{ label_id: 2, nome: 'Cliente VIP' }] },
    });
  });

  it('does not offer to create a label that exists by its shown name', async () => {
    const wrapper = montar({ ligada: true });

    await digitar(wrapper, 'aguardando retorno');
    expect(wrapper.vm.hasExactMatchInResults).toBe(true);
    expect(wrapper.vm.shouldShowCreate).toBe(false);

    await digitar(wrapper, 'Cliente VIP');
    expect(wrapper.vm.shouldShowCreate).toBe(false);

    await digitar(wrapper, 'aguardando_retorno');
    expect(wrapper.vm.shouldShowCreate).toBe(false);
  });

  it('offers to create a new label with the typed free name', async () => {
    const wrapper = montar({ ligada: true });

    await digitar(wrapper, '  Novo Cliente ');

    expect(wrapper.vm.shouldShowCreate).toBe(true);
    expect(wrapper.vm.parsedSearch).toBe('Novo Cliente');
  });

  it('keeps the Chatwoot behavior with the flag off', async () => {
    const wrapper = montar({ ligada: false });

    await digitar(wrapper, 'Novo Cliente');

    expect(wrapper.vm.parsedSearch).toBe('novo-cliente');
    expect(wrapper.vm.hasExactMatchInResults).toBe(false);
  });
});
