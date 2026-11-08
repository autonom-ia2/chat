// #2067: "ficar com a conversa ao enviar" e "Devolver para <agente>".
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { computed, defineComponent, nextTick, ref } from 'vue';
import {
  QUEM_ESTA,
  chaveDoDono,
  donoVisto,
  ficarVemLigada,
  quemEstaComAConversa,
  veioDaIaPreservado,
} from '../atribuir/quemEstaComAConversa';
import {
  camposDoEnvio,
  useFicarComAConversa,
} from '../atribuir/useFicarComAConversa';
import FicarComAConversa from '../atribuir/FicarComAConversa.vue';
import DevolverParaIa from '../atribuir/DevolverParaIa.vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import PassarParaAPI from 'dashboard/api/passarPara';
import { useAlert } from 'dashboard/composables';
import draftMessages from 'dashboard/store/modules/draftMessages';

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
const FLAG = 'ficar_com_a_conversa_ao_enviar';

const conversa = (meta = {}, id = 1) => ({
  id,
  meta: { sender: { id: 2 }, ...meta },
});
const semNinguem = () => conversa();
const comIa = () => conversa({ assignee: LIA, assignee_type: 'AgentBot' });
const comColega = () => conversa({ assignee: ANA, assignee_type: 'User' });
const minha = () =>
  conversa({ assignee: { id: EU, name: 'Eu' }, assignee_type: 'User' });

// A loja de verdade do rascunho (onde a escolha fica guardada) e a flag da conta.
const criarStore = (chat, { ligada = true } = {}) =>
  createStore({
    state: { chat },
    mutations: {
      trocar: (s, c) => {
        s.chat = c;
      },
    },
    getters: {
      getSelectedChat: s => s.chat,
      getCurrentUser: () => ({ id: EU }),
      getCurrentAccountId: () => 1,
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        ligada && flag === FLAG,
    },
    modules: {
      draftMessages: {
        ...draftMessages,
        state: () => ({ records: {}, replyEditorMode: 'reply' }),
      },
    },
  });

describe('quemEstaComAConversa', () => {
  it('diz com quem a conversa está, do ponto de vista de quem escreve', () => {
    expect(quemEstaComAConversa(semNinguem(), EU)).toBe(QUEM_ESTA.NINGUEM);
    expect(quemEstaComAConversa(comIa(), EU)).toBe(QUEM_ESTA.IA);
    expect(quemEstaComAConversa(comColega(), EU)).toBe(QUEM_ESTA.COLEGA);
    expect(quemEstaComAConversa(minha(), EU)).toBe(QUEM_ESTA.MINHA);
  });

  // A Lia (Agente de Cotação) atende pelo robô espelho dela: é IA como as outras.
  it('IA e robô são a mesma coisa: qualquer dono que não é pessoa, inclusive a Lia', () => {
    const assistente = conversa({
      assignee: { id: 4, name: 'Assistente' },
      assignee_type: 'Captain::Assistant',
    });
    expect(quemEstaComAConversa(assistente, EU)).toBe(QUEM_ESTA.IA);
    expect(quemEstaComAConversa(comIa(), EU)).toBe(QUEM_ESTA.IA);
  });

  it('vem ligado sem ninguém ou com a IA, desligado na conversa de colega', () => {
    expect(ficarVemLigada(QUEM_ESTA.NINGUEM)).toBe(true);
    expect(ficarVemLigada(QUEM_ESTA.IA)).toBe(true);
    expect(ficarVemLigada(QUEM_ESTA.COLEGA)).toBe(false);
  });

  it('o dono que a tela viu, como vai no envio', () => {
    expect(donoVisto(semNinguem())).toEqual({ tipo: 'ninguem' });
    expect(donoVisto(comIa())).toEqual({ tipo: 'ia' });
    expect(donoVisto(comColega())).toEqual({ tipo: 'pessoa', id: 9 });
    expect(chaveDoDono(comColega())).toBe('pessoa:9');
    // IA e ninguém são a mesma situação, como no servidor (FicarAoEnviar::LIVRES).
    expect(chaveDoDono(comIa())).toBe('livre');
    expect(chaveDoDono(semNinguem())).toBe('livre');
  });
});

describe('veioDaIaPreservado (o evento ao vivo não traz de onde a conversa veio)', () => {
  const comAna = { assignee: ANA, assignee_type: 'User' };
  const veio = { tipo: 'ia', id: 30, name: 'Lia' };

  it('com o mesmo dono, guarda o que já sabia', () => {
    expect(
      veioDaIaPreservado({ ...comAna, veio_da_ia: veio }, { ...comAna })
    ).toEqual({ ...comAna, veio_da_ia: veio });
  });

  it('o dono mudou: esquece', () => {
    const depois = { assignee: { id: 10 }, assignee_type: 'User' };
    expect(veioDaIaPreservado({ ...comAna, veio_da_ia: veio }, depois)).toEqual(
      depois
    );
  });

  it('o evento diz (troca de dono): vale o que ele diz', () => {
    const depois = { ...comAna, veio_da_ia: null };
    expect(veioDaIaPreservado({ ...comAna, veio_da_ia: veio }, depois)).toBe(
      depois
    );
  });
});

const montarRegra = (chat, opcoes = {}) => {
  const store = criarStore(chat, opcoes);
  let ficar;
  const Raiz = defineComponent({
    setup() {
      ficar = useFicarComAConversa(
        opcoes.conversa ? { conversa: opcoes.conversa } : {}
      );
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

  // Pega a tela nova vazando com a flag desligada: nada aparece e nada vai no envio.
  it('com a flag da conta desligada, nada aparece e nada vai no envio', () => {
    const { ficar } = montarRegra(comIa(), { ligada: false });
    expect(ficar.aplica).toBe(false);
    expect(ficar.decidir()).toBeNull();
    expect(camposDoEnvio(ficar.decidir())).toEqual({});
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

  it('o envio leva a escolha e o dono que a tela viu', () => {
    expect(camposDoEnvio(montarRegra(comColega()).ficar.decidir())).toEqual({
      ficarComAConversa: false,
      ficarComAConversaDe: { tipo: 'pessoa', id: 9 },
    });
    expect(camposDoEnvio(montarRegra(comIa()).ficar.decidir())).toEqual({
      ficarComAConversa: true,
      ficarComAConversaDe: { tipo: 'ia' },
    });
  });

  it('desmarcar vale só para a próxima mensagem: depois de enviar volta ao padrão', () => {
    const { ficar } = montarRegra(comIa());
    ficar.alternar();
    expect(ficar.ligada).toBe(false);
    expect(ficar.frase).toBe('CONVERSA_CANAL.FICAR.CONTINUA_COM(Lia)');

    expect(ficar.decidir().fica).toBe(false);
    expect(ficar.ligada).toBe(true);
    expect(ficar.decidir().fica).toBe(true);
  });

  it('ligar na conversa de colega vale para aquela mensagem', () => {
    const { ficar } = montarRegra(comColega());
    expect(ficar.decidir().fica).toBe(false);
    ficar.alternar();
    expect(ficar.decidir().fica).toBe(true);
    expect(ficar.ligada).toBe(false);
  });

  // Pega o watch que zerava a escolha a cada evento ao vivo (objeto novo, mesmo id).
  it('a conversa chega de novo do servidor (objeto novo, mesmo dono): a escolha fica', async () => {
    const { ficar, store } = montarRegra(comIa());
    ficar.alternar();
    store.commit('trocar', { ...comIa(), unread_count: 3 });
    await nextTick();
    expect(ficar.ligada).toBe(false);
  });

  it('trocar de conversa e voltar mantém a escolha (guardada com o rascunho)', async () => {
    const { ficar, store } = montarRegra(comIa());
    ficar.alternar();
    store.commit('trocar', conversa({}, 2));
    await nextTick();
    expect(ficar.ligada).toBe(true);

    store.commit('trocar', comIa());
    await nextTick();
    expect(ficar.ligada).toBe(false);
  });

  it('o dono mudou: a escolha volta à regra padrão', async () => {
    const { ficar, store } = montarRegra(comColega());
    ficar.alternar();
    expect(ficar.ligada).toBe(true);
    store.commit('trocar', comIa());
    await nextTick();
    expect(ficar.ligada).toBe(true);
    store.commit('trocar', comColega());
    await nextTick();
    expect(ficar.ligada).toBe(false);
  });

  // Pega a escolha apagada quando a IA passa a conversa a ninguém (mesma situação para quem envia).
  it('desligo o ícone com a IA e a IA passa para ninguém: a escolha permanece', async () => {
    const { ficar, store } = montarRegra(comIa());
    ficar.alternar();
    store.commit('trocar', semNinguem());
    await nextTick();
    expect(ficar.ligada).toBe(false);
    expect(ficar.decidir()).toMatchObject({
      fica: false,
      de: { tipo: 'ninguem' },
    });
  });

  // Pega a escolha perdida quando a pessoa troca de conversa durante um envio que falha.
  it('o envio falhou depois de trocar de conversa: a escolha volta na conversa do envio', async () => {
    const { ficar, store } = montarRegra(comColega());
    ficar.alternar();
    const decisao = ficar.decidir();
    // A conversa 2 é de colega (padrão desligado): a escolha da 1 não vaza para ela.
    store.commit(
      'trocar',
      conversa({ assignee: ANA, assignee_type: 'User' }, 2)
    );
    await nextTick();
    ficar.restaurar(decisao);
    expect(ficar.ligada).toBe(false);

    store.commit('trocar', comColega());
    await nextTick();
    expect(ficar.ligada).toBe(true);
  });

  it('envio em partes da gaveta (uma de cada vez): só a 1ª pede para ficar', () => {
    const decisao = montarRegra(comIa()).ficar.decidir();
    expect(camposDoEnvio(decisao, { parte: 0 }).ficarComAConversa).toBe(true);
    expect(camposDoEnvio(decisao, { parte: 1 })).toEqual({
      ficarComAConversa: false,
      ficarComAConversaDe: { tipo: 'ia' },
    });
  });

  // Pega o envio que falhou levando a escolha embora.
  it('o envio não saiu: restaurar devolve a escolha', () => {
    const { ficar } = montarRegra(comIa());
    ficar.alternar();
    const decisao = ficar.decidir();
    expect(ficar.ligada).toBe(true);
    ficar.restaurar(decisao);
    expect(ficar.ligada).toBe(false);
  });

  it('nota privada nunca fica, e a conversa que já é minha não pede nada', () => {
    expect(
      montarRegra(semNinguem()).ficar.decidir({ privada: true }).fica
    ).toBe(false);
    expect(montarRegra(minha()).ficar.decidir().fica).toBe(false);
  });

  it('na gaveta, sem a conversa lida ainda, nada a decidir', () => {
    const daGaveta = ref(null);
    const { ficar } = montarRegra(null, {
      conversa: computed(() => daGaveta.value),
    });
    expect(ficar.aplica).toBe(false);
    expect(ficar.decidir()).toBeNull();
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
  const EU_USUARIO = { id: EU, name: 'Eu' };
  const veioDaLia = { tipo: 'ia', id: 30, name: 'Lia' };
  const doN8n = { tipo: 'robo', id: 40, name: 'Robô do n8n' };
  const minhaVindaDe = veio =>
    conversa({
      assignee: EU_USUARIO,
      assignee_type: 'User',
      veio_da_ia: veio,
    });

  const montarDevolver = (conversation, { ligada = true } = {}) => {
    const store = createStore({
      getters: {
        getCurrentUser: () => EU_USUARIO,
        getCurrentAccountId: () => 1,
        'accounts/isFeatureEnabledonAccount': () => (_c, flag) =>
          ligada && flag === FLAG,
      },
      actions: { setCurrentChatAssignee: vi.fn() },
    });
    const dispatch = vi.spyOn(store, 'dispatch');
    const wrapper = mount(DevolverParaIa, {
      props: { conversation },
      global: { plugins: [store], directives: { tooltip: {} } },
    });
    return { wrapper, dispatch };
  };
  const linha = wrapper => wrapper.find('[data-devolver-para-ia]');

  beforeEach(() => {
    vi.restoreAllMocks();
    useAlert.mockClear();
  });

  it('aparece na conversa que é minha e veio de um agente de IA', () => {
    const { wrapper } = montarDevolver(minhaVindaDe(veioDaLia));
    expect(linha(wrapper).exists()).toBe(true);
    expect(linha(wrapper).text()).toContain(
      'CONVERSA_CANAL.DEVOLVER.PARA(Lia)'
    );
  });

  // Decisão do Rodrigo (22/10): não aparece na conversa de colega.
  it.each([
    [
      'na conversa de colega',
      { assignee: ANA, assignee_type: 'User', veio_da_ia: veioDaLia },
    ],
    [
      'com a IA',
      { assignee: LIA, assignee_type: 'AgentBot', veio_da_ia: veioDaLia },
    ],
    ['sem ninguém', { veio_da_ia: veioDaLia }],
    [
      'na minha que não veio da IA',
      { assignee: EU_USUARIO, assignee_type: 'User' },
    ],
  ])('não aparece %s', (_nome, meta) => {
    expect(linha(montarDevolver(conversa(meta)).wrapper).exists()).toBe(false);
  });

  it('com a flag da conta desligada, não aparece', () => {
    const { wrapper } = montarDevolver(minhaVindaDe(veioDaLia), {
      ligada: false,
    });
    expect(linha(wrapper).exists()).toBe(false);
  });

  // Pega o "veio de a IA" quando o robô não tem nome.
  it('robô sem nome: "Esta conversa veio da IA" e "Devolver para a IA"', () => {
    const { wrapper } = montarDevolver(
      minhaVindaDe({ tipo: 'robo', id: 40, name: null })
    );
    expect(linha(wrapper).text()).toContain(
      'CONVERSA_CANAL.DEVOLVER.VEIO_DA_IA'
    );
    expect(linha(wrapper).text()).not.toContain(
      'CONVERSA_CANAL.DEVOLVER.VEIO_DE'
    );
    expect(linha(wrapper).text()).toContain(
      'CONVERSA_CANAL.DEVOLVER.PARA(CONVERSA_CANAL.DEVOLVER.A_IA)'
    );
  });

  // Pega a devolução por atribuição crua para o agente nosso (sem evento nem turno refeito).
  it('agente nosso: devolve pelo "Passar para" e troca o dono na tela', async () => {
    const passar = vi.spyOn(PassarParaAPI, 'passar').mockResolvedValue({
      data: { com_ia: { id: 30, bot_id: 31, name: 'Lia' } },
    });
    const assign = vi.spyOn(ConversationApi, 'assignAgent');
    const { wrapper, dispatch } = montarDevolver(minhaVindaDe(veioDaLia));

    await wrapper.find('button').trigger('click');
    await nextTick();

    expect(passar).toHaveBeenCalledWith(1, { tipo: 'ia', id: 30 });
    expect(assign).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('setCurrentChatAssignee', {
      conversationId: 1,
      assignee: { id: 31, name: 'Lia' },
      assigneeType: 'AgentBot',
    });
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSA_CANAL.DEVOLVER.DEVOLVIDA(Lia)'
    );
  });

  it('robô de outro sistema: devolve pela atribuição de robô', async () => {
    const assign = vi
      .spyOn(ConversationApi, 'assignAgent')
      .mockResolvedValue({ data: { id: 40, name: 'Robô do n8n' } });
    const passar = vi.spyOn(PassarParaAPI, 'passar');
    const { wrapper, dispatch } = montarDevolver(minhaVindaDe(doN8n));

    await wrapper.find('button').trigger('click');
    await nextTick();

    expect(passar).not.toHaveBeenCalled();
    expect(assign).toHaveBeenCalledWith({
      conversationId: 1,
      agentId: 40,
      assigneeType: 'AgentBot',
    });
    expect(dispatch).toHaveBeenCalledWith('setCurrentChatAssignee', {
      conversationId: 1,
      assignee: { id: 40, name: 'Robô do n8n' },
      assigneeType: 'AgentBot',
    });
  });

  it('o agente parou: a recusa diz por quê e a conversa fica como estava', async () => {
    vi.spyOn(PassarParaAPI, 'passar').mockRejectedValue({
      response: { data: { codigo: 'nao_atende_cliente' } },
    });
    const { wrapper, dispatch } = montarDevolver(minhaVindaDe(veioDaLia));

    await wrapper.find('button').trigger('click');
    await nextTick();
    await nextTick();

    expect(dispatch).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'CONVERSA_CANAL.DEVOLVER.RECUSA.NAO_ATENDE_CLIENTE(Lia)'
    );
  });

  it('erro sem motivo conhecido: avisa que não deu', async () => {
    vi.spyOn(ConversationApi, 'assignAgent').mockRejectedValue(new Error('x'));
    const { wrapper } = montarDevolver(minhaVindaDe(doN8n));

    await wrapper.find('button').trigger('click');
    await nextTick();
    await nextTick();

    expect(useAlert).toHaveBeenCalledWith('CONVERSA_CANAL.DEVOLVER.FALHOU');
  });

  it('o botão mantém o alvo de toque de 44 px', () => {
    const { wrapper } = montarDevolver(minhaVindaDe(veioDaLia));
    expect(wrapper.find('button').classes()).toContain('min-h-11');
  });
});
