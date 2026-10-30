import types from '../../mutation-types';
import ConversationApi from '../../../api/inbox/conversation';
import MessageApi from '../../../api/inbox/message';
import { MESSAGE_STATUS, MESSAGE_TYPE } from 'shared/constants/messages';
import { createPendingMessage } from 'dashboard/helper/commons';
import filterQueryGenerator from 'dashboard/helper/filterQueryGenerator';
import {
  buildConversationList,
  setContacts,
  isOnMentionsView,
  isOnParticipatingView,
  isOnUnattendedView,
  isOnFoldersView,
} from './helpers/actionHelpers';
import messageReadActions from './actions/messageReadActions';
import messageTranslateActions from './actions/messageTranslateActions';
import * as Sentry from '@sentry/vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import {
  filtrosDoEndereco,
  naCaixa,
} from 'dashboard/composables/chatlist/useFiltrosDoLinkNaCaixa';
import {
  isAbortError,
  useAbortableRequest,
} from 'dashboard/composables/useAbortableRequest';
import {
  handleVoiceCallCreated,
  handleVoiceCallUpdated,
  syncConversationCallVisibility,
} from 'dashboard/helper/voice';

// Page size MessageFinder uses when walking backwards through a conversation.
const MESSAGES_PER_PAGE = 20;

const pendingHistoryRequests = new Map();

const TERMINAL_CONTACT_INFO_REQUEST_STATES = ['shared', 'identity_conflict'];

const contactInfoSourceId = message =>
  message.conversation?.contact_inbox?.source_id;

const hasContactInfoSource = (conversation, sourceId) => {
  return (conversation.messages || []).some(message => {
    return contactInfoSourceId(message) === sourceId;
  });
};

const contactInfoRefreshConversationIds = (state, message) => {
  const conversationIds = new Set([message.conversation_id].filter(Boolean));
  const sourceId = contactInfoSourceId(message);
  if (!sourceId) return [...conversationIds];

  (state.allConversations || []).forEach(conversation => {
    if (hasContactInfoSource(conversation, sourceId)) {
      conversationIds.add(conversation.id);
    }
  });

  return [...conversationIds];
};

export const hasMessageFailedWithExternalError = pendingMessage => {
  // This helper is used to check if the message has failed with an external error.
  // We have two cases
  // 1. Messages that fail from the UI itself (due to large attachments or a failed network):
  //    In this case, the message will have a status of failed but no external error. So we need to create that message again
  // 2. Messages sent from Chatwoot but failed to deliver to the customer for some reason (user blocking or client system down):
  //    In this case, the message will have a status of failed and an external error. So we need to retry that message
  const { content_attributes: contentAttributes, status } = pendingMessage;
  const externalError = contentAttributes?.external_error ?? '';
  return status === MESSAGE_STATUS.FAILED && externalError !== '';
};

const conversationListRequest = useAbortableRequest();

// Filtro "Funil" (#1150) ligado na lista comum (pasta e filtro avançado não aplicam o funil).
const isFunnelFilterActive = state =>
  Boolean(state?.conversationFilters?.crmPipelineId) &&
  !state.appliedFilters?.length;

// Leitura mais recente dos funis de cada conversa: uma resposta mais velha que chega depois é descartada.
const funnelReads = {};

// A conversa do websocket entra (ou já está) na lista filtrada sem os funis: falta ler da API.
const needsCrmFunnel = (state, conversationId) => {
  if (!isFunnelFilterActive(state)) return false;
  const listed = state.allConversations.find(({ id }) => id === conversationId);
  return !Array.isArray(listed?.crm_pipeline_ids);
};

// Filtros pelo link (#1883): com eles ligados na lista comum, conversa nova ou mudada pelo websocket faz o servidor
// reler a lista, em vez de o painel decidir se ela entra. Throttle: a primeira mudança agenda uma releitura para 2,5 s
// depois, e as que chegam até lá vão nela. Sob tráfego contínuo, as releituras ficam a pelo menos 10 s uma da outra; os
// eventos do intervalo se juntam na releitura do fim dele, que já lê o último.
export const RELEITURA_AO_VIVO_MS = 2500;
export const PISO_ENTRE_RELEITURAS_MS = 10000;
// Uma releitura que passa disso é abandonada (a rede pendurou): libera a próxima.
export const TEMPO_LIMITE_DA_RELEITURA_MS = 20000;
// Até 5 páginas carregadas, a releitura relê todas e troca a lista no lugar (a paginação fica, a rolagem não vai ao
// topo); acima disso, volta à página 1.
export const PAGINAS_RELIDAS_NO_MAXIMO = 5;
const filtroDoLinkNosParametros = params =>
  Boolean(params?.daIa || params?.esperandoMin);
// Ligado = a lista pediu com o filtro, sem filtro avançado por cima, e quem está na tela é a caixa com o link. Fora da
// caixa (CRM, Contatos) os filtros guardados no store não fazem a lista ser relida por baixo.
const filtroDoLinkAtivo = (state, rootState) =>
  filtroDoLinkNosParametros(state?.conversationFilters) &&
  !state.appliedFilters?.length &&
  naCaixa(rootState?.route) &&
  filtroDoLinkNosParametros(filtrosDoEndereco(rootState.route));
let releituraAgendada = null;

// Geração da lista: sobe a cada leitura, esvaziamento ou troca de aba. A releitura das páginas e a leitura comum
// guardam a geração em que começaram; se outra leitura, um esvaziamento ou uma troca de aba vier no meio, a resposta
// é de uma lista que já não existe e é descartada.
let geracaoDaLista = 0;
const novaGeracaoDaLista = () => {
  geracaoDaLista += 1;
  return geracaoDaLista;
};
let ultimaReleituraEm = -Infinity;
// Uma releitura por vez: o evento que chega com uma em andamento fica para depois dela, em vez de começar outra que
// descartaria a primeira (sob tráfego contínuo, a lista nunca seria trocada).
let releituraEmCurso = false;
let releituraDaVez = 0;
let releituraPendente = false;
// Releitura descartada (rolagem contínua puxando páginas descarta todas) é refeita sozinha; a 5ª seguida agenda uma
// última, depois do piso, para a lista não ficar velha. Se essa também cair, a próxima vem do próximo evento ao vivo
// (ou da releitura de um minuto, que existe com "esperando"). Releitura que grava, ou filtro que sai, zera a contagem.
export const DESCARTES_SEGUIDOS_NO_MAXIMO = 5;
let descartesSeguidos = 0;
export const cancelarReleituraDoFiltroDoLink = () => {
  clearTimeout(releituraAgendada);
  releituraAgendada = null;
  ultimaReleituraEm = -Infinity;
  releituraEmCurso = false;
  releituraPendente = false;
  descartesSeguidos = 0;
  // A releitura em andamento, se houver, é da caixa que saiu: a resposta dela é descartada (só ela; a leitura comum em
  // andamento segue).
  releituraDaVez += 1;
};
const agendarReleituraDoFiltroDoLink = ({ state, rootState, dispatch }) => {
  if (!filtroDoLinkAtivo(state, rootState)) return;
  if (releituraEmCurso) {
    releituraPendente = true;
    return;
  }
  if (releituraAgendada) return;
  // Entre 2,5 s e o piso (relógio do sistema que volta não estica a espera).
  const espera = Math.min(
    PISO_ENTRE_RELEITURAS_MS,
    Math.max(
      RELEITURA_AO_VIVO_MS,
      ultimaReleituraEm + PISO_ENTRE_RELEITURAS_MS - Date.now()
    )
  );
  releituraAgendada = setTimeout(() => {
    releituraAgendada = null;
    dispatch('releerFiltroDoLink');
  }, espera);
};
// Corre a leitura com o tempo-limite: passado ele, a leitura é cancelada (signal) e a releitura termina com AbortError.
const comTempoLimite = async ler => {
  const controle = new AbortController();
  let relogio;
  const estouro = new Promise((_, rejeitar) => {
    relogio = setTimeout(() => {
      controle.abort();
      rejeitar(new DOMException('releitura sem resposta', 'AbortError'));
    }, TEMPO_LIMITE_DA_RELEITURA_MS);
  });
  try {
    return await Promise.race([ler(controle.signal), estouro]);
  } finally {
    clearTimeout(relogio);
  }
};

// Como no UPDATE_CONVERSATION: a conversa que o websocket já atualizou depois do pedido fica na versão da lista, e
// continua dentro ou fora do filtro como estava.
const separarPeloWebsocket = (payload, lista) => {
  const naLista = new Map(lista.map(conversa => [conversa.id, conversa]));
  const atrasada = conversa =>
    naLista.get(conversa.id)?.updated_at > conversa.updated_at;
  return {
    novas: payload.filter(conversa => !atrasada(conversa)),
    atrasadas: payload.filter(atrasada).map(({ id }) => naLista.get(id)),
  };
};
const semRepetidas = conversas => [
  ...new Map(conversas.map(conversa => [conversa.id, conversa])).values(),
];

// Com 2 a 5 páginas carregadas: relê as páginas 1..N e troca a lista de uma vez, só quando todas chegam. A paginação
// fica onde está (a próxima rolagem pede a página N+1) e a conversa que saiu do filtro sai. Devolve false quando a
// resposta é de uma lista que já não existe e a releitura precisa ser refeita.
const releerAsPaginasDoFiltroDoLink = async (
  { commit, dispatch, state, rootState },
  paginas
) => {
  const geracao = novaGeracaoDaLista();
  const vez = releituraDaVez;
  const params = state.conversationFilters;
  const request = await dispatch(
    'conversationStats/onListRequestStarted',
    params
  );
  const respostas = await comTempoLimite(signal =>
    Promise.all(
      Array.from({ length: paginas }, (_, indice) =>
        ConversationApi.get({ ...params, page: indice + 1 }, { signal })
      )
    )
  );
  if (geracao !== geracaoDaLista || vez !== releituraDaVez) return false;
  // O filtro deixou de valer enquanto as páginas vinham (filtro avançado por cima, saiu da caixa): nada a gravar nem a
  // refazer.
  if (!filtroDoLinkAtivo(state, rootState)) return true;
  const lidas = semRepetidas(
    respostas.flatMap(({ data: { data } }) => data.payload)
  );
  const { novas, atrasadas } = separarPeloWebsocket(
    lidas,
    state.allConversations
  );
  const atrasadasQueEstavam = atrasadas.filter(({ id }) =>
    state.idsDoFiltroDoLink.includes(id)
  );
  commit(types.SET_IDS_DO_FILTRO_DO_LINK, {
    ids: [...novas, ...atrasadasQueEstavam].map(({ id }) => id),
    substituir: true,
  });
  commit(types.REPLACE_CONVERSATION_LIST, [...novas, ...atrasadas]);
  // O mesmo que a leitura comum faz com o que chega (buildConversationList): etiquetas e contatos das conversas.
  dispatch('conversationLabels/setBulkConversationLabels', novas);
  setContacts(commit, [...novas, ...atrasadas]);
  dispatch('conversationStats/set', {
    meta: respostas[0].data.data.meta,
    request,
  });
  return true;
};

// Uma página só, ou mais de 5: volta à primeira página no lugar da lista, sem acender o carregando do rodapé. A rolagem
// vai ao topo só se a lista foi trocada. Passado o tempo-limite, a leitura é cancelada. Devolve se gravou a lista (uma
// rolagem que pede a próxima página no meio cancela esta leitura, ou outra leitura a descarta: conta como descartada).
const voltarAPrimeiraPaginaDoFiltroDoLink = async ({ dispatch }, paginas) => {
  await dispatch('updateChatListFilters', { page: 1, updatedWithin: null });
  let gravou;
  try {
    gravou = await comTempoLimite(() =>
      dispatch('fetchAllConversations', {
        replaceExisting: true,
        silenciosa: true,
      })
    );
  } catch (error) {
    if (isAbortError(error)) dispatch('invalidateConversationListRequests');
    throw error;
  }
  const trocou = gravou === true;
  if (paginas > PAGINAS_RELIDAS_NO_MAXIMO && trocou) {
    emitter.emit(BUS_EVENTS.LISTA_DO_FILTRO_DO_LINK_NO_TOPO);
  }
  return trocou;
};

// actions
const actions = {
  // Relê a lista com o filtro do link. Com uma página chegando (a rolagem pedindo a próxima), espera ela chegar e tenta
  // de novo, para não cancelar a rolagem. Com 2 a 5 páginas carregadas, relê todas e troca a lista sem mexer na rolagem.
  // Com uma só, ou mais de 5, volta à primeira página no lugar da lista (o mesmo que a releitura ao reconectar faz); a
  // conversa aberta continua aberta e, se a lista tinha mais de 5 páginas, a rolagem vai ao topo.
  releerFiltroDoLink: async contexto => {
    const { state, rootState, rootGetters } = contexto;
    if (!filtroDoLinkAtivo(state, rootState)) {
      descartesSeguidos = 0;
      return;
    }
    // Pedida direto (releitura de um minuto, aba visível de novo) com outra em andamento: fica para depois dela.
    if (releituraEmCurso) {
      releituraPendente = true;
      return;
    }
    if (state.listLoadingStatus) {
      agendarReleituraDoFiltroDoLink(contexto);
      return;
    }
    const paginas = rootGetters['conversationPage/getCurrentPageFilter'](
      state.conversationFilters.assigneeType
    );
    releituraDaVez += 1;
    const estaReleitura = releituraDaVez;
    releituraEmCurso = true;
    ultimaReleituraEm = Date.now();
    try {
      const trocou =
        paginas > 1 && paginas <= PAGINAS_RELIDAS_NO_MAXIMO
          ? await releerAsPaginasDoFiltroDoLink(contexto, paginas)
          : await voltarAPrimeiraPaginaDoFiltroDoLink(contexto, paginas);
      // Cancelada no meio (a caixa desmontou): não mexe na contagem nem pede outra.
      if (estaReleitura !== releituraDaVez) return;
      // Descartada (a lista foi lida, esvaziada ou trocou de aba no meio): relê de novo depois; a 5ª seguida agenda a
      // última.
      descartesSeguidos = trocou ? 0 : descartesSeguidos + 1;
      if (!trocou && descartesSeguidos <= DESCARTES_SEGUIDOS_NO_MAXIMO) {
        releituraPendente = true;
      }
    } catch (error) {
      // Tempo-limite ou leitura cancelada não é erro; o próximo evento do websocket (ou a releitura de um minuto) tenta
      // de novo.
      if (!isAbortError(error)) Sentry.captureException(error);
    } finally {
      // Cancelada no meio (a caixa desmontou): a releitura de agora não mexe nas marcas da que veio depois.
      if (estaReleitura === releituraDaVez) {
        releituraEmCurso = false;
        if (releituraPendente) {
          releituraPendente = false;
          agendarReleituraDoFiltroDoLink(contexto);
        }
      }
    }
  },

  // Filtro "Funil" da lista (#1150). O websocket não traz os funis da conversa (crm_pipeline_ids): o payload também vai
  // ao contato pelo widget. Com filtro de funil (e sem pasta ou filtro avançado), a conversa da lista que está sem os
  // funis, ou cujo card mudou, tem os funis lidos da API. Só o campo muda, e só em conversa que ainda está na lista: a
  // leitura não põe conversa em Menções ou Em que participo nem passa por cima de um update mais novo do websocket.
  // Se a leitura falhar: conversa que nunca teve os funis fica fora da lista filtrada e o próximo evento dela tenta de
  // novo; a que já tinha fica com os funis anteriores até a próxima mudança do card ou a próxima leitura da lista.
  refreshConversationFunnel: async (
    { state, getters, commit },
    conversationId
  ) => {
    if (!isFunnelFilterActive(state)) return;
    if (!getters.getConversationById(conversationId)) return;
    const read = (funnelReads[conversationId] || 0) + 1;
    funnelReads[conversationId] = read;
    try {
      const { data } = await ConversationApi.show(conversationId);
      if (funnelReads[conversationId] !== read) return;
      commit(types.SET_CONVERSATION_CRM_PIPELINE_IDS, {
        id: data.id,
        crmPipelineIds: data.crm_pipeline_ids,
        crmPipelineHidden: data.crm_pipeline_hidden,
      });
    } catch {
      // Sem acesso ou falha de rede: fica o que havia (ver acima).
    }
  },

  getConversation: async ({ commit, dispatch }, conversationId) => {
    try {
      const response = await ConversationApi.show(conversationId);
      // API refreshes can run in the background after reconnecting. Use the
      // list merge to preserve local message state without moving the agent's
      // scroll position or marking messages as read.
      commit(types.SET_ALL_CONVERSATION, [response.data]);
      commit(`contacts/${types.SET_CONTACT_ITEM}`, response.data.meta.sender);
      dispatch('conversationLabels/setConversationLabel', {
        id: response.data.id,
        data: response.data.labels,
      });
    } catch (error) {
      // Ignore error
    }
  },

  fetchAllConversations: async (
    { commit, state, dispatch },
    { replaceExisting = false, silenciosa = false } = {}
  ) => {
    const geracao = novaGeracaoDaLista();
    return conversationListRequest.run(async signal => {
      const params = state.conversationFilters;
      const countRequest = await dispatch(
        'conversationStats/onListRequestStarted',
        params
      );
      if (signal.aborted) return false;
      // #1883: a releitura do filtro do link troca a lista sem acender o carregando do rodapé.
      if (!silenciosa) commit(types.SET_LIST_LOADING_STATUS);
      try {
        const {
          data: { data },
        } = await ConversationApi.get(params, { signal });

        if (signal.aborted) return false;
        // #1883: a lista foi trocada no meio (releitura do filtro do link, esvaziamento, outra aba): esta página é da
        // lista anterior. A página não avança, e a próxima rolagem pede de novo.
        if (geracao !== geracaoDaLista) {
          commit(types.CLEAR_LIST_LOADING_STATUS);
          return false;
        }

        // Filtros pelo link (#1883): quem decide o que entra é o servidor; guarda o que ele mandou.
        if (filtroDoLinkNosParametros(params)) {
          commit(types.SET_IDS_DO_FILTRO_DO_LINK, {
            ids: data.payload.map(({ id }) => id),
            substituir: replaceExisting,
          });
        }
        buildConversationList(
          { commit, dispatch },
          params,
          data,
          params.assigneeType,
          { replaceExisting, countRequest }
        );
        return true;
      } catch (error) {
        if (!signal.aborted) {
          commit(types.CLEAR_LIST_LOADING_STATUS);
        }
        return false;
      }
    });
  },

  fetchFilteredConversations: async ({ commit, dispatch, state }, params) => {
    novaGeracaoDaLista();
    return conversationListRequest.run(async signal => {
      const {
        replaceExisting = false,
        sortBy = state.chatSortFilter,
        ...requestParams
      } = params;
      // The contact scope pins its own order to match the in-thread navigation.
      const filterRequestParams = {
        ...requestParams,
        sortBy: state.appliedFiltersSortBy || sortBy,
      };
      const countRequest = await dispatch(
        'conversationStats/onListRequestStarted',
        filterRequestParams
      );
      if (signal.aborted) return;
      commit(types.SET_LIST_LOADING_STATUS);
      try {
        const { data } = await ConversationApi.filter(filterRequestParams, {
          signal,
        });

        if (signal.aborted) return;

        buildConversationList(
          { commit, dispatch },
          filterRequestParams,
          data,
          'appliedFilters',
          { replaceExisting, countRequest }
        );
      } catch (error) {
        if (signal.aborted) return;

        commit(types.CLEAR_LIST_LOADING_STATUS);
        throw error;
      }
    });
  },

  emptyAllConversations({ commit }) {
    novaGeracaoDaLista();
    commit(types.EMPTY_ALL_CONVERSATION);
  },

  clearSelectedState({ commit }) {
    commit(types.CLEAR_CURRENT_CHAT_WINDOW);
  },

  fetchPreviousMessages: ({ commit }, data) => {
    const requestKey = JSON.stringify([
      MessageApi.url,
      data.conversationId,
      data.before,
      data.after,
    ]);
    if (pendingHistoryRequests.has(requestKey)) {
      return pendingHistoryRequests.get(requestKey);
    }

    const request = MessageApi.getPreviousMessages(data)
      .then(({ data: { meta, payload } }) => {
        commit(`conversationMetadata/${types.SET_CONVERSATION_METADATA}`, {
          id: data.conversationId,
          data: meta,
        });
        commit(types.SET_PREVIOUS_CONVERSATIONS, {
          id: data.conversationId,
          data: payload,
        });
        // A short backward page means the start is reached; `after` requests only prove it when empty.
        const hasReachedFirstMessage = data.after
          ? !payload.length
          : payload.length < MESSAGES_PER_PAGE;
        if (hasReachedFirstMessage) {
          commit(types.SET_ALL_MESSAGES_LOADED, data.conversationId);
        }
      })
      .finally(() => pendingHistoryRequests.delete(requestKey));

    pendingHistoryRequests.set(requestKey, request);
    return request;
  },

  fetchAllAttachments: async ({ commit }, conversationId) => {
    let attachments = [];

    try {
      const { data } = await ConversationApi.getAllAttachments(conversationId);
      attachments = data.payload;
    } catch (error) {
      // in case of error, log the error and continue
      Sentry.setContext('Conversation', {
        id: conversationId,
      });
      Sentry.captureException(error);
    } finally {
      // we run the commit even if the request fails
      // this ensures that the `attachment` variable is always present on chat
      commit(types.SET_ALL_ATTACHMENTS, {
        id: conversationId,
        data: attachments,
      });
    }
  },

  syncActiveConversationMessages: async (
    { commit, state, dispatch, getters },
    { conversationId }
  ) => {
    const { allConversations, syncConversationsMessages } = state;
    const lastMessageId = syncConversationsMessages[conversationId];
    const selectedChat = allConversations.find(
      conversation => conversation.id === conversationId
    );
    if (!selectedChat) return;
    try {
      const { messages } = selectedChat;
      // Fetch all the messages after the last message id
      const {
        data: { meta, payload },
      } = await MessageApi.getPreviousMessages({
        conversationId,
        after: lastMessageId,
      });
      commit(`conversationMetadata/${types.SET_CONVERSATION_METADATA}`, {
        id: conversationId,
        data: meta,
      });
      // Find the messages that are not already present in the store
      const missingMessages = payload.filter(
        message => !messages.find(item => item.id === message.id)
      );
      selectedChat.messages.push(...missingMessages);
      // Sort the messages by created_at
      const sortedMessages = selectedChat.messages.sort((a, b) => {
        return new Date(a.created_at) - new Date(b.created_at);
      });
      commit(types.SET_MISSING_MESSAGES, {
        id: conversationId,
        data: sortedMessages,
      });
      commit(types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION, {
        conversationId,
        messageId: null,
      });
      // Quem só lê não marca como lida (#1800).
      if (getters.canOperateConversation(selectedChat)) {
        dispatch('markMessagesRead', { id: conversationId }, { root: true });
      }
    } catch (error) {
      // Handle error
    }
  },

  setConversationLastMessageId: async (
    { commit, state },
    { conversationId }
  ) => {
    const { allConversations } = state;
    const selectedChat = allConversations.find(
      conversation => conversation.id === conversationId
    );
    if (!selectedChat) return;
    const { messages } = selectedChat;
    const lastMessage = messages.last();
    if (!lastMessage) return;
    commit(types.SET_LAST_MESSAGE_ID_IN_SYNC_CONVERSATION, {
      conversationId,
      messageId: lastMessage.id,
    });
  },

  async setActiveChat({ commit, dispatch }, { data, after }) {
    commit(types.SET_CURRENT_CHAT_WINDOW, data);
    if (data.dataFetched === undefined) {
      // Reset only when refetching — a re-activated short conversation has no scroll to earn it back.
      commit(types.CLEAR_ALL_MESSAGES_LOADED, data.id);
      try {
        await dispatch('fetchPreviousMessages', {
          after,
          // A conversation created without an initial message has nothing to anchor on.
          before: data.messages[0]?.id,
          conversationId: data.id,
        });
        commit(types.SET_CHAT_DATA_FETCHED, data.id);
      } catch (error) {
        // Ignore error
      }
    }
  },

  assignAgent: async (
    { dispatch },
    { conversationId, agentId, assigneeType }
  ) => {
    try {
      const response = await ConversationApi.assignAgent({
        conversationId,
        agentId,
        assigneeType,
      });
      dispatch('setCurrentChatAssignee', {
        conversationId,
        assignee: response.data,
        assigneeType,
      });
    } catch (error) {
      // Handle error
    }
  },

  setCurrentChatAssignee(
    { commit },
    { conversationId, assignee, assigneeType }
  ) {
    commit(types.ASSIGN_AGENT, { conversationId, assignee, assigneeType });
  },

  assignTeam: async ({ dispatch }, { conversationId, teamId }) => {
    try {
      const response = await ConversationApi.assignTeam({
        conversationId,
        teamId,
      });
      dispatch('setCurrentChatTeam', { team: response.data, conversationId });
    } catch (error) {
      // Handle error
    }
  },

  setCurrentChatTeam({ commit }, { team, conversationId }) {
    commit(types.ASSIGN_TEAM, { team, conversationId });
  },

  toggleStatus: async (
    { commit },
    { conversationId, status, snoozedUntil = null, customAttributes = null }
  ) => {
    try {
      // Update custom attributes first if provided
      if (customAttributes) {
        await ConversationApi.updateCustomAttributes({
          conversationId,
          customAttributes,
        });
        commit(types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES, {
          conversationId,
          customAttributes,
        });
      }

      const {
        data: {
          payload: {
            current_status: updatedStatus,
            snoozed_until: updatedSnoozedUntil,
          } = {},
        } = {},
      } = await ConversationApi.toggleStatus({
        conversationId,
        status,
        snoozedUntil,
      });
      commit(types.CHANGE_CONVERSATION_STATUS, {
        conversationId,
        status: updatedStatus,
        snoozedUntil: updatedSnoozedUntil,
      });
    } catch (error) {
      // Handle error
    }
  },

  // #2067: devolve a promessa do envio, para a caixa de resposta saber se saiu (e desfazer a
  // escolha de "ficar com a conversa" quando não saiu).
  createPendingMessageAndSend: async ({ dispatch }, data) => {
    const pendingMessage = createPendingMessage(data);
    return dispatch('sendMessageWithData', pendingMessage);
  },

  sendMessageWithData: async ({ commit }, pendingMessage) => {
    const { conversation_id: conversationId, id } = pendingMessage;
    try {
      commit(types.ADD_MESSAGE, {
        ...pendingMessage,
        status: MESSAGE_STATUS.PROGRESS,
      });
      const response = hasMessageFailedWithExternalError(pendingMessage)
        ? await MessageApi.retry(conversationId, id)
        : await MessageApi.create(pendingMessage);
      commit(types.ADD_MESSAGE, {
        ...response.data,
        status: MESSAGE_STATUS.SENT,
      });
      commit(types.ADD_CONVERSATION_ATTACHMENTS, {
        ...response.data,
        status: MESSAGE_STATUS.SENT,
      });
      // #2067: a resposta do envio diz se "ficar com a conversa" não deu.
      return response.data;
    } catch (error) {
      const errorMessage = error.response
        ? error.response.data.error
        : undefined;
      commit(types.ADD_MESSAGE, {
        ...pendingMessage,
        meta: {
          error: errorMessage,
        },
        status: MESSAGE_STATUS.FAILED,
      });
      throw error;
    }
  },

  requestContactInfo: async ({ commit }, conversationId) => {
    const { data } = await ConversationApi.requestContactInfo(conversationId);
    commit(types.ADD_MESSAGE, data);
    return data;
  },

  addMessage({ commit, rootGetters }, message) {
    commit(types.ADD_MESSAGE, message);
    if (message.message_type === MESSAGE_TYPE.INCOMING) {
      commit(types.SET_CONVERSATION_CAN_REPLY, {
        conversationId: message.conversation_id,
        canReply: true,
      });
      commit(types.ADD_CONVERSATION_ATTACHMENTS, message);
    }
    handleVoiceCallCreated(
      message,
      rootGetters?.getCurrentUserID,
      rootGetters?.getCurrentUserAvailability
    );
  },

  updateMessage({ commit, dispatch, rootGetters, state }, message) {
    commit(types.ADD_MESSAGE, message);

    const contactInfoRequest =
      message.content_attributes?.whatsapp_contact_info;
    const isTerminalContactInfoRequest =
      contactInfoRequest?.type === 'request' &&
      (message.status === MESSAGE_STATUS.FAILED ||
        TERMINAL_CONTACT_INFO_REQUEST_STATES.includes(
          contactInfoRequest.state
        ));
    if (isTerminalContactInfoRequest) {
      contactInfoRefreshConversationIds(state, message).forEach(
        conversationId => {
          dispatch('getConversation', conversationId);
        }
      );
    }

    handleVoiceCallUpdated(
      commit,
      message,
      rootGetters?.getCurrentUserID,
      rootGetters?.getCurrentUserAvailability
    );
  },

  deleteMessage: async function deleteLabels(
    { commit },
    { conversationId, messageId }
  ) {
    try {
      const { data } = await MessageApi.delete(conversationId, messageId);
      commit(types.ADD_MESSAGE, data);
      commit(types.DELETE_CONVERSATION_ATTACHMENTS, data);
    } catch (error) {
      throw new Error(error);
    }
  },

  // Acesso por funil (#1148): a pessoa deixou de ver a conversa (o card mudou de funil). Só tira da lista; não apaga.
  removeConversationLocally: ({ commit, dispatch }, conversationId) => {
    commit(types.DELETE_CONVERSATION, conversationId);
    dispatch('conversationStats/get');
  },

  deleteConversation: async ({ commit, dispatch }, conversationId) => {
    try {
      await ConversationApi.delete(conversationId);
      commit(types.DELETE_CONVERSATION, conversationId);
      dispatch('conversationStats/get');
    } catch (error) {
      throw new Error(error);
    }
  },

  addConversation({ commit, state, dispatch, rootState }, conversation) {
    agendarReleituraDoFiltroDoLink({ state, rootState, dispatch });
    const { currentInbox, appliedFilters } = state;
    const {
      inbox_id: inboxId,
      meta: { sender },
    } = conversation;
    const hasAppliedFilters = !!appliedFilters.length;
    const isMatchingInboxFilter =
      !currentInbox || Number(currentInbox) === inboxId;
    if (
      !hasAppliedFilters &&
      !isOnFoldersView(rootState) &&
      !isOnMentionsView(rootState) &&
      !isOnParticipatingView(rootState) &&
      !isOnUnattendedView(rootState) &&
      isMatchingInboxFilter
    ) {
      commit(types.ADD_CONVERSATION, conversation);
      dispatch('contacts/setContact', sender);
      if (isFunnelFilterActive(state)) {
        dispatch('refreshConversationFunnel', conversation.id);
      }
    }
  },

  addMentions({ dispatch, rootState }, conversation) {
    if (isOnMentionsView(rootState)) {
      dispatch('updateConversation', conversation);
    }
  },

  addUnattended({ dispatch, rootState }, conversation) {
    if (isOnUnattendedView(rootState)) {
      dispatch('updateConversation', conversation);
    }
  },

  updateConversation(
    { commit, dispatch, state, rootState, rootGetters },
    conversation
  ) {
    agendarReleituraDoFiltroDoLink({ state, rootState, dispatch });
    const sender = conversation.meta?.sender;
    const needsFunnel = needsCrmFunnel(state, conversation.id);

    commit(types.UPDATE_CONVERSATION, conversation);
    syncConversationCallVisibility(conversation, rootGetters?.getCurrentUserID);
    if (needsFunnel) dispatch('refreshConversationFunnel', conversation.id);

    dispatch('conversationLabels/setConversationLabel', {
      id: conversation.id,
      data: conversation.labels,
    });

    if (sender) dispatch('contacts/setContact', sender);
  },

  updateConversationLastActivity(
    { commit },
    { conversationId, lastActivityAt }
  ) {
    commit(types.UPDATE_CONVERSATION_LAST_ACTIVITY, {
      lastActivityAt,
      conversationId,
    });
  },

  setChatStatusFilter({ commit }, data) {
    commit(types.CHANGE_CHAT_STATUS_FILTER, data);
  },

  setChatSortFilter({ commit }, data) {
    commit(types.CHANGE_CHAT_SORT_FILTER, data);
  },

  updateAssignee({ commit }, data) {
    commit(types.UPDATE_ASSIGNEE, data);
  },

  updateConversationContact({ commit }, data) {
    if (data.id) {
      commit(`contacts/${types.SET_CONTACT_ITEM}`, data);
    }
    commit(types.UPDATE_CONVERSATION_CONTACT, data);
  },

  setActiveInbox({ commit }, inboxId) {
    commit(types.SET_ACTIVE_INBOX, inboxId);
  },

  muteConversation: async ({ commit }, conversationId) => {
    try {
      await ConversationApi.mute(conversationId);
      commit(types.MUTE_CONVERSATION);
    } catch (error) {
      //
    }
  },

  unmuteConversation: async ({ commit }, conversationId) => {
    try {
      await ConversationApi.unmute(conversationId);
      commit(types.UNMUTE_CONVERSATION);
    } catch (error) {
      //
    }
  },

  sendEmailTranscript: async (_, { conversationId, email }) => {
    await ConversationApi.sendEmailTranscript({ conversationId, email });
  },

  updateCustomAttributes: async (
    { commit },
    { conversationId, customAttributes }
  ) => {
    try {
      const response = await ConversationApi.updateCustomAttributes({
        conversationId,
        customAttributes,
      });
      const { custom_attributes } = response.data;
      commit(types.UPDATE_CONVERSATION_CUSTOM_ATTRIBUTES, {
        conversationId,
        customAttributes: custom_attributes,
      });
    } catch (error) {
      throw new Error(error);
    }
  },

  setConversationFilters({ commit }, data) {
    commit(types.SET_CONVERSATION_FILTERS, data);
  },

  // Replaces the list with page 1 of the snake_case filters; sortBy overrides the activity order.
  applyConversationFilters: (
    { commit, dispatch },
    { filters, sortBy = null }
  ) => {
    commit(types.SET_CONVERSATION_FILTERS, filters);
    commit(types.SET_CONVERSATION_FILTERS_SORT, sortBy);
    commit(types.EMPTY_ALL_CONVERSATION);
    dispatch('conversationPage/reset', {}, { root: true });

    return dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(filters),
      page: 1,
    });
  },

  clearConversationFilters({ commit }) {
    commit(types.CLEAR_CONVERSATION_FILTERS);
  },

  setChatListFilters({ commit }, data) {
    commit(types.SET_CHAT_LIST_FILTERS, data);
  },

  updateChatListFilters({ commit }, data) {
    commit(types.UPDATE_CHAT_LIST_FILTERS, data);
  },

  invalidateConversationListRequests({ commit }) {
    novaGeracaoDaLista();
    conversationListRequest.abort();
    commit(types.CLEAR_LIST_LOADING_STATUS);
  },

  assignPriority: async ({ dispatch }, { conversationId, priority }) => {
    try {
      await ConversationApi.togglePriority({
        conversationId,
        priority,
      });

      dispatch('setCurrentChatPriority', {
        priority,
        conversationId,
      });
    } catch (error) {
      // Handle error
    }
  },

  setCurrentChatPriority({ commit }, { priority, conversationId }) {
    commit(types.ASSIGN_PRIORITY, { priority, conversationId });
  },

  setContextMenuChatId({ commit }, chatId) {
    commit(types.SET_CONTEXT_MENU_CHAT_ID, chatId);
  },

  getInboxCaptainAssistantById: async ({ commit }, conversationId) => {
    try {
      const response = await ConversationApi.getInboxAssistant(conversationId);
      commit(types.SET_INBOX_CAPTAIN_ASSISTANT, response.data);
    } catch (error) {
      // Handle error
    }
  },

  ...messageReadActions,
  ...messageTranslateActions,
};

export default actions;
