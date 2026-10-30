// #2138 — apoio dos specs do painel: um store Vuex só com o que o painel lê e o
// catálogo pt_BR do painel (as frases são conferidas como a pessoa lê).
import { createStore } from 'vuex';
import { getters as gettersDosCampos } from 'dashboard/store/modules/attributes';
import { createI18n } from 'vue-i18n';
import painelPtBR from 'dashboard/i18n/locale/pt_BR/painelDoContato.json';

export const FUSO = 'America/Sao_Paulo';

export const criarI18n = () =>
  createI18n({
    legacy: false,
    locale: 'pt_BR',
    missingWarn: false,
    fallbackWarn: false,
    messages: {
      pt_BR: {
        ...painelPtBR,
        CRM_CARD: {
          URGENCIA: {
            LOW: 'baixa',
            MEDIUM: 'média',
            HIGH: 'alta',
            URGENT: 'urgente',
          },
        },
        CONVERSATION_PARTICIPANTS: {
          API: { SELF_ADD_RESTRICTED: 'Você não pode se incluir aqui.' },
        },
      },
    },
  });

// `estado` muda o que os getters devolvem; `acoes` recebe as chamadas.
// `maisGetters`: getters a mais de um spec (ex.: o ContactPanel lê o painel antigo).
// `modulos`: módulos de verdade do store (ex.: conversationLabels); o que eles
// trazem sai dos getters fingidos daqui.
export const criarStore = (estado = {}, maisGetters = {}, modulos = {}) => {
  const dados = {
    contaId: 1,
    eu: { id: 7, name: 'Bia' },
    features: { painel_contato_enxuto: true },
    times: [],
    agentes: [],
    acompanhantes: {},
    conversas: {},
    etiquetas: {},
    anexos: [],
    definicoes: [],
    uiContatos: { isFetchingItem: false },
    papel: 'agent',
    funcao: null,
    permissoes: [],
    conta: {},
    ...estado,
  };
  const acoes = [];
  // Os getters leem o estado reativo do store (r), para a tela acompanhar as mudanças.
  let r = dados;
  const registrar = nome => (_ctx, payload) => {
    acoes.push([nome, payload]);
    return r.respostas?.[nome]?.(payload, r);
  };
  const doModulo = nome => Object.keys(modulos).includes(nome.split('/')[0]);
  const semOsDosModulos = lista =>
    Object.fromEntries(
      Object.entries(lista).filter(([nome]) => !doModulo(nome))
    );
  const store = createStore({
    state: () => ({ dados }),
    modules: modulos,
    getters: semOsDosModulos({
      getCurrentAccountId: () => r.contaId,
      // Sem função personalizada, o agente tem tudo; com ela, valem as chaves.
      getCurrentRole: () => r.papel,
      getCurrentCustomRoleId: () => r.funcao,
      getCurrentUser: () => ({
        ...r.eu,
        accounts: [
          {
            id: r.contaId,
            role: r.papel,
            custom_role_id: r.funcao,
            permissions: r.permissoes,
            availability_status: 'online',
          },
        ],
      }),
      getCurrentUserID: () => r.eu.id,
      getSelectedChat: () => r.conversaSelecionada || {},
      getConversationById: () => id => r.conversas[id],
      'accounts/isFeatureEnabledonAccount': () => (id, nome) =>
        id === r.contaId && Boolean(r.features[nome]),
      'accounts/getAccount': () => () => ({
        ...r.conta,
        id: r.contaId,
        timezone: FUSO,
        custom_attributes: { timezone: FUSO },
      }),
      'teams/getTeams': () => r.times,
      'conversationWatchers/getByConversationId': () => id =>
        r.acompanhantes[id],
      'contactLabels/getContactLabels': () => id => r.etiquetas[id] || [],
      // #2202 (PR 3): etiquetas da conta e da conversa; `podeOperar` imita o
      // getter canOperateConversation (quem só lê não etiqueta).
      'labels/getLabels': () => r.etiquetasDaConta || [],
      'conversationLabels/getConversationLabels': () => id =>
        r.etiquetasDaConversa?.[id] || [],
      canOperateConversation: () => () => r.podeOperar !== false,
      'inboxAssignableAgents/getAssignableAgents': () => () => r.agentes,
      'contacts/getUIFlags': () => r.uiContatos,
      getSelectedChatAttachments: () => r.anexos,
      // O getter de verdade: é ele que esconde os campos internos da WAHA.
      'attributes/getAttributesByModel': () =>
        gettersDosCampos.getAttributesByModel({ records: r.definicoes }),
      'globalConfig/get': () => ({ crmKanbanEnabled: true }),
      ...maisGetters,
    }),
    mutations: {
      'conversationWatchers/SET_CONVERSATION_PARTICIPANTS'(
        _s,
        { conversationId, data }
      ) {
        r.acompanhantes = { ...r.acompanhantes, [conversationId]: data };
      },
    },
    actions: Object.fromEntries(
      [
        'assignAgent',
        'assignTeam',
        'assignPriority',
        'conversationWatchers/show',
        'conversationWatchers/update',
        'contactLabels/get',
        'contacts/show',
        'contacts/update',
        'contacts/deleteCustomAttributes',
      ].map(nome => [nome, registrar(nome)])
    ),
  });
  r = store.state.dados;
  return { store, dados: r, acoes };
};
