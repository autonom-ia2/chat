// #2067: "ficar com a conversa ao enviar" e "Devolver para <agente>".
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { defineComponent, nextTick } from 'vue';
import {
  QUEM_ESTA,
  ficarVemLigada,
  quemEstaComAConversa,
} from '../atribuir/quemEstaComAConversa';
import { useFicarComAConversa } from '../atribuir/useFicarComAConversa';
import FicarComAConversa from '../atribuir/FicarComAConversa.vue';
import DevolverParaIa from '../atribuir/DevolverParaIa.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores?.nome ? `${chave}(${valores.nome})` : chave,
  }),
}));

const EU = 7;
const ANA = { id: 9, name: 'Ana' };
const LIA = { id: 3, name: 'Lia' };

const conversa = (meta = {}) => ({
  id: 1,
  meta: { sender: { id: 2 }, ...meta },
});
const semNinguem = () => conversa();
const comIa = () => conversa({ assignee: LIA, assignee_type: 'AgentBot' });
const comColega = () => conversa({ assignee: ANA, assignee_type: 'User' });
const minha = () =>
  conversa({ assignee: { id: EU, name: 'Eu' }, assignee_type: 'User' });

describe('quemEstaComAConversa', () => {
  it('diz com quem a conversa está, do ponto de vista de quem escreve', () => {
    expect(quemEstaComAConversa(semNinguem(), EU)).toBe(QUEM_ESTA.NINGUEM);
    expect(quemEstaComAConversa(comIa(), EU)).toBe(QUEM_ESTA.IA);
    expect(quemEstaComAConversa(comColega(), EU)).toBe(QUEM_ESTA.COLEGA);
    expect(quemEstaComAConversa(minha(), EU)).toBe(QUEM_ESTA.MINHA);
  });

  it('IA e robô são a mesma coisa: qualquer dono que não é pessoa', () => {
    const assistente = conversa({
      assignee: { id: 4, name: 'Assistente' },
      assignee_type: 'Captain::Assistant',
    });
    expect(quemEstaComAConversa(assistente, EU)).toBe(QUEM_ESTA.IA);
  });

  it('vem ligado sem ninguém ou com a IA, desligado na conversa de colega', () => {
    expect(ficarVemLigada(QUEM_ESTA.NINGUEM)).toBe(true);
    expect(ficarVemLigada(QUEM_ESTA.IA)).toBe(true);
    expect(ficarVemLigada(QUEM_ESTA.COLEGA)).toBe(false);
  });
});

const montarRegra = chat => {
  const store = createStore({
    state: { chat },
    mutations: {
      trocar: (s, c) => {
        s.chat = c;
      },
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: EU }),
    },
  });
  let ficar;
  const Raiz = defineComponent({
    setup() {
      ficar = useFicarComAConversa();
      return () => null;
    },
  });
  mount(Raiz, { global: { plugins: [store] } });
  return { ficar, store };
};

describe('useFicarComAConversa', () => {
  it.each([
    ['sem ninguém', semNinguem(), true, true],
    ['com a IA', comIa(), true, true],
    ['com colega', comColega(), true, false],
    ['minha', minha(), false, false],
  ])('%s', (_nome, chat, aplica, ligada) => {
    const { ficar } = montarRegra(chat);
    expect(ficar.aplica).toBe(aplica);
    expect(ficar.ligada).toBe(ligada);
  });

  it('a frase diz o que acontece ao enviar', () => {
    expect(montarRegra(semNinguem()).ficar.frase).toBe(
      'CONVERSA_CANAL.FICAR.FICA_COM_VOCE'
    );
    expect(montarRegra(comIa()).ficar.frase).toBe(
      'CONVERSA_CANAL.FICAR.FICA_COM_VOCE_SAI_DE(Lia)'
    );
    expect(montarRegra(comColega()).ficar.frase).toBe(
      'CONVERSA_CANAL.FICAR.CONTINUA_COM(Ana)'
    );
  });

  it('desmarcar vale só para a próxima mensagem: depois de enviar volta ao padrão', () => {
    const { ficar } = montarRegra(comIa());
    ficar.alternar();
    expect(ficar.ligada).toBe(false);
    expect(ficar.frase).toBe('CONVERSA_CANAL.FICAR.CONTINUA_COM(Lia)');

    expect(ficar.decidir()).toBe(false);
    expect(ficar.ligada).toBe(true);
    expect(ficar.decidir()).toBe(true);
  });

  it('ligar na conversa de colega vale para aquela mensagem', () => {
    const { ficar } = montarRegra(comColega());
    expect(ficar.decidir()).toBe(false);
    ficar.alternar();
    expect(ficar.decidir()).toBe(true);
    expect(ficar.ligada).toBe(false);
  });

  it('trocar de conversa volta ao padrão', async () => {
    const { ficar, store } = montarRegra(comIa());
    ficar.alternar();
    store.commit('trocar', { ...semNinguem(), id: 2 });
    await nextTick();
    expect(ficar.ligada).toBe(true);
  });

  it('nota privada nunca fica, e a conversa que já é minha não pede nada', () => {
    expect(montarRegra(semNinguem()).ficar.decidir({ privada: true })).toBe(
      false
    );
    expect(montarRegra(minha()).ficar.decidir()).toBe(false);
  });
});

describe('FicarComAConversa (o ícone ao lado do Enviar)', () => {
  const montarIcone = ficar =>
    mount(FicarComAConversa, {
      props: { ficar },
      global: { directives: { tooltip: {} } },
    });

  it('é um interruptor com a frase inteira no nome acessível e alvo de 44 px', async () => {
    const alternar = vi.fn();
    const botao = montarIcone({
      ligada: true,
      frase: 'Ao enviar, a conversa fica com você',
      alternar,
    }).find('[data-ficar-com-a-conversa]');

    expect(botao.attributes('role')).toBe('switch');
    expect(botao.attributes('aria-checked')).toBe('true');
    expect(botao.attributes('aria-label')).toBe(
      'Ao enviar, a conversa fica com você. CONVERSA_CANAL.FICAR.DICA_LIGADA'
    );
    expect(botao.classes()).toContain('size-11');
    await botao.trigger('click');
    expect(alternar).toHaveBeenCalled();
  });

  it('desligado mostra a pessoa sem o check', () => {
    const icone = montarIcone({ ligada: false, frase: 'x', alternar: vi.fn() });
    expect(icone.find('[aria-checked="false"]').exists()).toBe(true);
    expect(icone.find('.i-lucide-user-round').exists()).toBe(true);
    expect(icone.find('.i-lucide-user-round-check').exists()).toBe(false);
  });
});

describe('DevolverParaIa', () => {
  const montarDevolver = conversation => {
    const store = createStore({ actions: { setCurrentChatAssignee: vi.fn() } });
    const dispatch = vi.spyOn(store, 'dispatch');
    const wrapper = mount(DevolverParaIa, {
      props: { conversation },
      global: { plugins: [store], directives: { tooltip: {} } },
    });
    return { wrapper, dispatch };
  };
  const linha = wrapper => wrapper.find('[data-devolver-para-ia]');
  const veioDaLia = { id: 30, name: 'Lia' };

  beforeEach(() => {
    vi.restoreAllMocks();
    useAlert.mockClear();
  });

  it('aparece com uma pessoa na conversa que veio de um agente de IA', () => {
    const { wrapper } = montarDevolver(
      conversa({ assignee: ANA, assignee_type: 'User', veio_da_ia: veioDaLia })
    );
    expect(linha(wrapper).isVisible()).toBe(true);
    expect(linha(wrapper).text()).toContain(
      'CONVERSA_CANAL.DEVOLVER.PARA(Lia)'
    );
  });

  it.each([
    [
      'com a IA',
      { assignee: LIA, assignee_type: 'AgentBot', veio_da_ia: veioDaLia },
    ],
    ['sem ninguém', { veio_da_ia: veioDaLia }],
    ['com pessoa que não veio da IA', { assignee: ANA, assignee_type: 'User' }],
  ])('não aparece %s', (_nome, meta) => {
    expect(linha(montarDevolver(conversa(meta)).wrapper).isVisible()).toBe(
      false
    );
  });

  it('devolve pela atribuição de robô e troca o dono na tela', async () => {
    const assign = vi
      .spyOn(ConversationApi, 'assignAgent')
      .mockResolvedValue({ data: { id: 30, name: 'Lia' } });
    const { wrapper, dispatch } = montarDevolver(
      conversa({ assignee: ANA, assignee_type: 'User', veio_da_ia: veioDaLia })
    );

    await wrapper.find('button').trigger('click');
    await nextTick();

    expect(assign).toHaveBeenCalledWith({
      conversationId: 1,
      agentId: 30,
      assigneeType: 'AgentBot',
    });
    expect(dispatch).toHaveBeenCalledWith('setCurrentChatAssignee', {
      conversationId: 1,
      assignee: { id: 30, name: 'Lia' },
      assigneeType: 'AgentBot',
    });
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSA_CANAL.DEVOLVER.DEVOLVIDA(Lia)'
    );
  });

  it('se o servidor recusar, avisa e a conversa fica como estava', async () => {
    vi.spyOn(ConversationApi, 'assignAgent').mockRejectedValue(new Error('x'));
    const { wrapper, dispatch } = montarDevolver(
      conversa({ assignee: ANA, assignee_type: 'User', veio_da_ia: veioDaLia })
    );

    await wrapper.find('button').trigger('click');
    await nextTick();
    await nextTick();

    expect(dispatch).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('CONVERSA_CANAL.DEVOLVER.FALHOU');
  });
});
