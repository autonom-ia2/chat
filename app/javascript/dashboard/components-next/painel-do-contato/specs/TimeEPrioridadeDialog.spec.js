import { reactive } from 'vue';
import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import TimeEPrioridadeDialog from '../topo/TimeEPrioridadeDialog.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — "Time e prioridade": dois campos de escolha e "Salvar", com assignTeam e
// assignPriority. As actions não devolvem erro: o diálogo confere a conversa.
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useAlert: vi.fn(),
}));

enableAutoUnmount(afterEach);

const DialogStub = {
  props: ['title'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template: '<div><h3>{{ title }}</h3><slot /><slot name="footer" /></div>',
};
const ChoiceStub = {
  props: ['modelValue', 'options', 'ariaLabel'],
  emits: ['update:modelValue'],
  template:
    '<div :data-campo="ariaLabel"><span v-for="o in options" :key="String(o.value)">{{ o.label }}</span></div>',
};

const montar = ({ times = [], salva = true } = {}) => {
  const conversa = reactive({ id: 42, priority: null, meta: { team: null } });
  const apoio = criarStore({
    conversas: { 42: conversa },
    respostas: {
      assignTeam: ({ teamId }) => {
        if (salva)
          conversa.meta.team = times.find(item => item.id === teamId) || null;
      },
      assignPriority: ({ priority }) => {
        if (salva) conversa.priority = priority;
      },
    },
  });
  const wrapper = mount(TimeEPrioridadeDialog, {
    props: { conversa, times },
    global: {
      plugins: [apoio.store, criarI18n()],
      stubs: { Dialog: DialogStub, ChoiceSelect: ChoiceStub, Button: true },
    },
  });
  wrapper.vm.abrir();
  return { wrapper, conversa, ...apoio };
};
const campo = (wrapper, nome) =>
  wrapper.findComponent(`[data-campo="${nome}"]`);
const escolher = async (wrapper, nome, valor) => {
  wrapper
    .findAllComponents(ChoiceStub)
    .find(c => c.props('ariaLabel') === nome)
    .vm.$emit('update:modelValue', valor);
  await flushPromises();
};
const salvar = async wrapper => {
  wrapper.findComponent(DialogStub).vm.$emit('confirm');
  await flushPromises();
};

beforeEach(() => vi.clearAllMocks());

describe('TimeEPrioridadeDialog', () => {
  it('conta com time: título "Time e prioridade" e os dois campos, com "Sem time" e "Sem prioridade"', () => {
    const { wrapper } = montar({ times: [{ id: 1, name: 'Suporte' }] });
    expect(wrapper.find('h3').text()).toBe('Time e prioridade');
    expect(campo(wrapper, 'Time').text()).toBe('Sem timeSuporte');
    expect(campo(wrapper, 'Prioridade').text()).toBe(
      'Sem prioridadeBaixaMédiaAltaUrgente'
    );
  });

  it('conta sem time: só a prioridade', () => {
    const { wrapper } = montar();
    expect(wrapper.find('h3').text()).toBe('Prioridade');
    expect(campo(wrapper, 'Time').exists()).toBe(false);
  });

  it('salvar manda só o que mudou e diz "Pronto."', async () => {
    const { wrapper, acoes } = montar({ times: [{ id: 1, name: 'Suporte' }] });
    await escolher(wrapper, 'Prioridade', 'urgent');
    await salvar(wrapper);
    expect(acoes).toEqual([
      ['assignPriority', { conversationId: 42, priority: 'urgent' }],
    ]);
    expect(useAlert).toHaveBeenCalledWith('Pronto.');
  });

  it('time e prioridade juntos', async () => {
    const { wrapper, acoes, conversa } = montar({
      times: [{ id: 1, name: 'Suporte' }],
    });
    await escolher(wrapper, 'Time', 1);
    await escolher(wrapper, 'Prioridade', 'high');
    await salvar(wrapper);
    expect(acoes.map(([nome]) => nome)).toEqual([
      'assignTeam',
      'assignPriority',
    ]);
    expect(conversa.meta.team.name).toBe('Suporte');
    expect(conversa.priority).toBe('high');
  });

  it('se a conversa não mudou (a action falhou calada), avisa e não diz "Pronto."', async () => {
    const { wrapper } = montar({ salva: false });
    await escolher(wrapper, 'Prioridade', 'low');
    await salvar(wrapper);
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para salvar agora. Tente de novo.'
    );
    expect(useAlert).not.toHaveBeenCalledWith('Pronto.');
  });
});
