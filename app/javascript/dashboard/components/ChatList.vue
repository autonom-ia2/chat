<script setup>
import {
  ref,
  unref,
  provide,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';
import { usePastaDoEmail } from 'dashboard/components-next/conversa-canal/email/pastaDoEmail';
import {
  filtroDoLinkDaLista,
  abaDoFiltroDoLink,
  statusDoFiltroDoLink,
  funilDoFiltroDoLink,
  abaDaListaComLink,
  chaveDaPaginaDaLista,
  useFiltrosDoLinkNaCaixa,
  useReleituraPeriodica,
} from 'dashboard/composables/chatlist/useFiltrosDoLinkNaCaixa';
import { cancelarReleituraDoFiltroDoLink } from 'dashboard/store/modules/conversations/actions';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import ChatListHeader from './ChatListHeader.vue';
import ConversationList from './ConversationList.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import FunnelFilter from 'dashboard/components-next/Conversation/FunnelFilter.vue';
import ListaCabecalho from 'dashboard/components-next/Conversation/ListaDeConversas/ListaCabecalho.vue';
import ListaAbas from 'dashboard/components-next/Conversation/ListaDeConversas/ListaAbas.vue';
import ChipDoStatus from 'dashboard/components-next/Conversation/ListaDeConversas/ChipDoStatus.vue';
import CampoDaBusca from 'dashboard/components-next/Conversation/ListaDeConversas/busca/CampoDaBusca.vue';
import ResultadoDaBusca from 'dashboard/components-next/Conversation/ListaDeConversas/busca/ResultadoDaBusca.vue';
import { useBuscaDaLista } from 'dashboard/components-next/Conversation/ListaDeConversas/busca/useBuscaDaLista';
import { useListaNova } from 'dashboard/components-next/Conversation/ListaDeConversas/useListaNova';
import FaixaDoWhatsapp from 'dashboard/components-next/conversa-canal/faixa-whatsapp/FaixaDoWhatsapp.vue';
import {
  FUNNEL_ALL,
  readFunnelChoice,
  writeFunnelChoice,
} from 'dashboard/composables/useFunnelFilterChoice';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { declararContexto } from 'dashboard/composables/useContextoDaTela';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';

import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { useConversationRoutePath } from 'dashboard/composables/useConversationRoutePath';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { isAssignedToUser } from 'dashboard/helper/assigneeHelper';
import {
  sortComparator,
  filterPeloFiltroDoLink,
} from '../store/modules/conversations/helpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';

const props = defineProps({
  conversationInbox: { type: [String, Number], default: 0 },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showConversationList: { default: true, type: Boolean },
  isOnExpandedLayout: { default: false, type: Boolean },
});

const emit = defineEmits(['conversationLoad']);
const { uiSettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const store = useStore();
const { buildConversationListPath } = useConversationRoutePath();

const resolveAttributesModalRef = ref(null);

const activeAssigneeTab = ref(wootConstants.ASSIGNEE_TYPE.ME);
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
// chatsOnView is to store the chats that are currently visible on the screen,
// which mirrors the conversationList.
const chatsOnView = ref([]);
const foldersQuery = useMapGetter('getAppliedConversationFiltersQuery');
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const appliedFilter = ref([]);
const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unAssignedChatsList = useMapGetter('getUnAssignedChats');
const participatingChatsList = useMapGetter('getParticipatingChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const appliedContactFilter = useMapGetter('getAppliedContactFilter');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const { nomeDe: nomeDaEtiqueta } = useNomeDaEtiqueta();
const currentAccountId = useMapGetter('getCurrentAccountId');

// Filtro "Funil" (multifunil #1150): id do funil, "none" (Sem assunto) ou vazio (todos os meus). Lembrado por conta e
// pessoa; vale para todas as listas de conversa.
const isCrmEnabled = window.globalConfig?.CRM_KANBAN_ENABLED === 'true';
const crmPipelineId = ref(
  isCrmEnabled
    ? readFunnelChoice(currentAccountId.value, currentUser.value?.id)
    : FUNNEL_ALL
);
// We can't useFunctionGetter here since it needs to be called on setup?
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
} = useBulkActions();

// #934 — a seleção e os filtros aplicados vão ao Guia. O id da conversa é o número que a tela mostra.
declararContexto({
  selecionados: () => ({
    recurso: 'conversations',
    ids: selectedConversations.value,
  }),
  filtros: () =>
    Object.fromEntries(
      appliedFilters.value.map(({ attributeKey, values }) => [
        attributeKey,
        [values].flat().map(valor => valor?.id ?? valor),
      ])
    ),
});

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

// computed

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const getContact = useMapGetter('contacts/getContact');
const folderContactId = useMapGetter('customViews/getActiveFolderContactId');

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value;
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

const assigneeTabItems = computed(() => {
  return filterItemsByPermission(
    ASSIGNEE_TYPE_TAB_PERMISSIONS,
    userPermissions.value,
    item => item.permissions
  ).map(({ key, count: countKey }) => ({
    key,
    name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
    count: conversationStats.value[countKey] || 0,
  }));
});

// "Em que participo" abre na aba Todos (#1150): a conversa em que a pessoa participa costuma estar com outra pessoa.
// Quem só lê (#1800) não tem "Minhas": abre na primeira aba que tem.
function defaultAssigneeTab() {
  const { PARTICIPATING } = wootConstants.CONVERSATION_TYPE;
  const { ALL, ME } = wootConstants.ASSIGNEE_TYPE;
  const keys = assigneeTabItems.value.map(item => item.key);
  if (!keys.includes(ME)) return keys[0] || ME;
  return props.conversationType === PARTICIPATING && keys.includes(ALL)
    ? ALL
    : ME;
}

// #1809: Spam e Lixeira da caixa de e-mail (a pasta vem do endereço, ?pasta=).
const { pasta: pastaDoEmail, versao: versaoDasPastas } = usePastaDoEmail();

// #1883: filtros pelo link do Números (?da_ia=1, ?esperando_min=30). No Spam e na Lixeira a pasta manda; com filtro
// avançado ou pasta salva, a lista vem de outro pedido e eles não valem.
const {
  daIa: daIaDoLink,
  esperandoMin: esperandoDoLink,
  noFunil: noFunilDoLink,
  assinatura: assinaturaDoLink,
  limparTudo: limparTudoDoLink,
  irParaALista,
} = useFiltrosDoLinkNaCaixa();
const idsDoFiltroDoLink = useMapGetter('getIdsDoFiltroDoLink');
const filtroDoLink = computed(() =>
  filtroDoLinkDaLista({
    daIa: daIaDoLink.value,
    esperandoMin: esperandoDoLink.value,
    noFunil: noFunilDoLink.value,
    pasta: pastaDoEmail.value,
    filtroAvancado: hasAppliedFiltersOrActiveFolders.value,
  })
);
// #1999: sem a aba "Todas", a lista do link junta as abas da pessoa (o servidor corta pelas permissões dela), e as abas
// somem enquanto o link está ligado, porque a lista é a do link.
const abaDaLista = computed(() =>
  abaDaListaComLink(
    filtroDoLink.value,
    assigneeTabItems.value.map(item => item.key),
    activeAssigneeTab.value,
    wootConstants.ASSIGNEE_TYPE.ALL
  )
);
const listaJuntaDoLink = computed(
  () => abaDaLista.value !== activeAssigneeTab.value
);

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    abaDaLista.value === wootConstants.ASSIGNEE_TYPE.ALL
  );
});

// A página e o fim da lista seguem a aba que a lista pede (#1999), onde a resposta grava o avanço.
const currentPageFilterKey = computed(() =>
  chaveDaPaginaDaLista(hasAppliedFiltersOrActiveFolders.value, abaDaLista.value)
);

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  abaDaLista
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);

const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

// Antes de montar, a aba ainda é "Minhas", que quem só lê não tem (#1800). Com a lista junta do link (#1999), a aba
// "Todas" que a pessoa não tem: sem contagem, a paginação segue a página gravada.
const activeAssigneeTabCount = computed(
  () =>
    assigneeTabItems.value.find(item => item.key === abaDaLista.value)?.count ||
    0
);

const conversationListPagination = computed(() => {
  const conversationsPerPage = 25;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  return currentPage.value + 1;
});
// #1999: com o filtro do link, o funil da lista vem do link; o escolhido na caixa não é tocado.
const funilDaLista = computed(() =>
  funilDoFiltroDoLink(filtroDoLink.value, crmPipelineId.value, FUNNEL_ALL)
);
// #1999: com o filtro do link, a caixa abre em "Todas" (se a pessoa tem) e em "Abertas", para bater com o número do
// Números.
// #2199: "Ver conversas" da aba Seus posts (Anúncios da Meta) abre a caixa em "Todas" (?aba=todas), se a pessoa tem.
function abaAoAbrir() {
  const abas = assigneeTabItems.value.map(item => item.key);
  const todas = wootConstants.ASSIGNEE_TYPE.ALL;
  const pedeTodas =
    router.currentRoute.value.query.aba === 'todas' && abas.includes(todas);
  return (
    abaDoFiltroDoLink(filtroDoLink.value, abas, todas) ||
    (pedeTodas ? todas : null) ||
    defaultAssigneeTab()
  );
}
// A conversa aberta fica na lista filtrada enquanto estiver aberta.
const conversaAberta = useMapGetter('getSelectedChat');
// Saindo da caixa, nenhuma releitura agendada roda por baixo.
onBeforeUnmount(cancelarReleituraDoFiltroDoLink);
const temFiltroDoLink = computed(() =>
  Boolean(filtroDoLink.value.daIa || filtroDoLink.value.esperandoMin)
);
// #2202: com a chave lista_quem_espera, o topo novo ("Recentes ▾", "Filtrar ▾", abas
// Minhas · Para pegar · Todas). Filtro avançado, pasta salva, escopo de contato, filtro do link e pastas
// do e-mail continuam no topo de sempre, que já mostra e limpa o filtro do jeito dele.
const listaNova = useListaNova();
const cabecalhoNovo = ref(null);
const usaCabecalhoNovo = computed(
  () =>
    listaNova.value &&
    !hasAppliedFiltersOrActiveFolders.value &&
    !appliedContactFilter.value &&
    !temFiltroDoLink.value &&
    !pastaDoEmail.value
);
// Fora das abertas (resolvidas, adiadas, pendentes, todos os status), o chip mostra o status e volta.
const mostraChipDoStatus = computed(
  () =>
    usaCabecalhoNovo.value &&
    activeStatus.value !== wootConstants.STATUS_TYPE.OPEN
);
const voltarParaAbertas = () => cabecalhoNovo.value?.voltarParaAbertas();
// O painel que as abas da lista nova controlam (aria-controls).
const PAINEL_DA_LISTA = 'lista-de-conversas-painel';
// A lista só é o painel das abas quando as abas novas aparecem.
const listaComAbas = computed(
  () =>
    listaNova.value &&
    !hasAppliedFiltersOrActiveFolders.value &&
    !listaJuntaDoLink.value
);
const VAZIA_POR_ABA = { me: 'MINHAS', unassigned: 'PARA_PEGAR', all: 'TODAS' };
// A lista vazia fala do status antes da aba: em "Pendentes", não adianta dizer "nada para pegar".
const VAZIA_POR_STATUS = {
  resolved: 'RESOLVIDAS',
  snoozed: 'ADIADAS',
  pending: 'PENDENTES',
  all: 'TODOS_OS_STATUS',
};
const textoDaListaVazia = computed(() => {
  if (!usaCabecalhoNovo.value) return t('CHAT_LIST.LIST.404');
  const chave =
    VAZIA_POR_STATUS[activeStatus.value] || VAZIA_POR_ABA[abaDaLista.value];
  return chave
    ? t(`LISTA_DE_CONVERSAS.VAZIA.${chave}`)
    : t('CHAT_LIST.LIST.404');
});
const tituloDoFiltroDoLink = computed(() => {
  const { daIa, esperandoMin: n } = filtroDoLink.value;
  if (daIa && n) {
    return t('FORK_CONVERSATION_LIST.FILTRO_DO_LINK.DA_IA_ESPERANDO', { n });
  }
  if (daIa) return t('FORK_CONVERSATION_LIST.FILTRO_DO_LINK.DA_IA');
  return t('FORK_CONVERSATION_LIST.FILTRO_DO_LINK.ESPERANDO', { n });
});

const conversationFilters = computed(() => {
  return {
    inboxId: props.conversationInbox ? props.conversationInbox : undefined,
    assigneeType: abaDaLista.value,
    // #1809: Spam e Lixeira resolvem a conversa; dentro da pasta, todos os status.
    status: pastaDoEmail.value ? 'all' : activeStatus.value,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: props.label ? [props.label] : undefined,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
    crmPipelineId: (isCrmEnabled && funilDaLista.value) || undefined,
    pasta: pastaDoEmail.value || undefined,
    ...filtroDoLink.value,
  };
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (pastaDoEmail.value) {
    return t(`CONVERSA_CANAL.EMAIL.PASTA.${pastaDoEmail.value.toUpperCase()}`);
  }
  if (temFiltroDoLink.value) {
    return tituloDoFiltroDoLink.value;
  }
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }
  if (inbox.value.name) {
    return inbox.value.name;
  }
  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }
  if (props.label) {
    return `#${nomeDaEtiqueta(props.label)}`;
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.MENTION) {
    return t('CHAT_LIST.MENTION_HEADING');
  }
  if (
    props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
  ) {
    return t('FORK_CONVERSATION_LIST.PARTICIPATING');
  }
  if (props.conversationType === wootConstants.CONVERSATION_TYPE.UNATTENDED) {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }
  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }
  return t('CHAT_LIST.TAB_HEADING');
});

function filterByAssigneeTab(conversations) {
  if (abaDaLista.value === wootConstants.ASSIGNEE_TYPE.ME) {
    return conversations.filter(c =>
      isAssignedToUser(c, currentUser.value?.id)
    );
  }
  if (abaDaLista.value === wootConstants.ASSIGNEE_TYPE.UNASSIGNED) {
    return conversations.filter(c => !c.meta?.assignee);
  }
  return [...conversations];
}

function sortByUnreadStatus(conversations) {
  return [...conversations].sort((a, b) =>
    sortComparator(a, b, wootConstants.SORT_BY_TYPE.UNREAD)
  );
}

const conversationList = computed(() => {
  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;
    if (
      props.conversationType === wootConstants.CONVERSATION_TYPE.PARTICIPATING
    ) {
      localConversationList = filterByAssigneeTab(
        participatingChatsList.value(filters)
      );
    } else if (abaDaLista.value === 'me') {
      localConversationList = [...mineChatsList.value(filters)];
    } else if (abaDaLista.value === 'unassigned') {
      localConversationList = [...unAssignedChatsList.value(filters)];
    } else {
      localConversationList = [...allChatList.value(filters)];
    }
    localConversationList = filterPeloFiltroDoLink(
      localConversationList,
      Boolean(filters.daIa || filters.esperandoMin),
      idsDoFiltroDoLink.value,
      conversaAberta.value?.id
    );
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  if (
    !hasAppliedFiltersOrActiveFolders.value &&
    activeSortBy.value === wootConstants.SORT_BY_TYPE.UNREAD
  ) {
    localConversationList = sortByUnreadStatus(localConversationList);
  }

  return localConversationList;
});

const showEndOfListMessage = computed(() => {
  return !!(
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

// ---------------------- Methods -----------------------
function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;
  activeStatus.value = status || wootConstants.STATUS_TYPE.OPEN;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(
    orderBy
  )
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
      sortBy: activeSortBy.value,
    })
    .catch(() => useAlert(t('CHAT_LIST.FETCH_ERROR')))
    // emit even on failure so a deep-linked conversation still loads via
    // fetchConversationIfUnavailable
    .finally(emitConversationLoaded);

  showAdvancedFilters.value = false;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  let page = currentFiltersPage.value + 1;
  store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
      sortBy: activeSortBy.value,
    })
    .catch(() => useAlert(t('CHAT_LIST.FETCH_ERROR')))
    .finally(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  showAdvancedFilters.value = false;
  store
    .dispatch('applyConversationFilters', { filters: payload })
    .catch(() => useAlert(t('CHAT_LIST.FETCH_ERROR')))
    .finally(emitConversationLoaded);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);
  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };
  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  // Here we are setting the params for edit folder modal to show the existing values.

  // For agent, team, inboxes,and campaigns we get only the id's from the query.
  // So we are mapping the id's to the actual values.

  // For labels we get the name of the label from the query.
  // If we delete the label from the label list then we will not be able to show the label name.

  // For custom attributes we get only attribute key.
  // So we are mapping it to find the input type of the attribute to show in the edit folder modal.
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    contacts: [getContact.value(folderContactId.value)],
    languages: languages,
    countries: countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    abaDaLista.value
  );
  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  // Here we are setting the params for edit folder modal.
  //  To show the existing values. when we click on edit folder button.

  // Here we get the query from the active folder.
  // And we are mapping the query to the actual values.
  // To show in the edit folder modal by the help of generateValuesForEditCustomViews helper.
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }
  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }
  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations() {
  store.dispatch('updateChatListFilters', conversationFilters.value);
  store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

function resetAndFetchData() {
  appliedFilter.value = [];
  resetBulkActions();
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');
  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  }
  if (props.foldersId) {
    return;
  }
  fetchConversations();
}

function loadMoreConversations() {
  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value !== selectedTab) {
    resetBulkActions();
    emitter.emit('clearSearchInput');
    activeAssigneeTab.value = selectedTab;
    if (!currentPage.value) {
      fetchConversations();
    } else {
      store.dispatch('invalidateConversationListRequests');
      store.dispatch('updateChatListFilters', conversationFilters.value);
    }
  }
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    activeStatus.value = value;
  } else {
    activeSortBy.value = value;
  }

  if (type === 'sort' && hasAppliedFiltersOrActiveFolders.value) {
    resetBulkActions();
    store.dispatch('conversationPage/reset');
    store.dispatch('emptyAllConversations');

    if (hasActiveFolders.value) {
      fetchSavedFilteredConversations(activeFolder.value.query);
    } else {
      fetchFilteredConversations(appliedFilters.value);
    }
    return;
  }

  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;
  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  // #1883: com o filtro do link ligado, a lista volta filtrada.
  irParaALista(buildConversationListPath(), temFiltroDoLink.value);
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });
  store.dispatch('assignPriority', { conversationId, priority }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });
    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch (error) {
    // Ignore error
  }
}
async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch (error) {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });
    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch (error) {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  // Check for required attributes before resolving
  const conversation = getConversationById.value(conversationId);
  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(
    currentCustomAttributes
  );

  if (hasMissing) {
    // Pass conversation context through the modal's API
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };
    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes =
      existingConversation?.custom_attributes || {};
    const mergedAttributes = { ...currentCustomAttributes, ...attributes };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;
  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

// #1801: a tela inicial pede uma aba. Aba que a pessoa não tem é ignorada; com filtro avançado
// aplicado, o filtro sai junto (senão a lista seguiria filtrada e o clique pareceria não fazer nada).
function abrirAbaDaTelaInicial(aba) {
  if (!assigneeTabItems.value.some(item => item.key === aba)) return;
  if (!hasAppliedFilters.value) {
    updateAssigneeTab(aba);
    return;
  }
  activeAssigneeTab.value = aba;
  resetAndFetchData();
}
useEmitter(BUS_EVENTS.TELA_INICIAL_ABA, abrirAbaDaTelaInicial);
// #1883: a releitura voltou a lista longa (mais de 5 páginas) para a primeira página.
const conversationListComponentRef = ref(null);
// #2211: a busca no topo da lista. Enquanto busca, a lista some (sem desmontar) e o resultado aparece no
// lugar; o ✕ volta a lista como estava: aba, filtro e a posição da rolagem.
const busca = useBuscaDaLista();
const buscaAtiva = computed(() => usaCabecalhoNovo.value && busca.ativa.value);
let rolagemAntesDaBusca = 0;
watch(buscaAtiva, async (ativa, antes) => {
  const lista = conversationListComponentRef.value?.conversationListRef;
  if (ativa && !antes) {
    rolagemAntesDaBusca = lista?.scrollTop || 0;
    return;
  }
  if (!ativa && antes) {
    await nextTick();
    if (lista) lista.scrollTop = rolagemAntesDaBusca;
  }
});
useEmitter(BUS_EVENTS.LISTA_DO_FILTRO_DO_LINK_NO_TOPO, () => {
  const lista = conversationListComponentRef.value?.conversationListRef;
  if (lista) lista.scrollTop = 0;
});
useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  store.dispatch('conversationStats/get', conversationFilters.value);
});

onMounted(() => {
  activeAssigneeTab.value = abaAoAbrir();
  store.dispatch('setChatListFilters', conversationFilters.value);
  setFiltersFromUISettings();
  activeStatus.value = statusDoFiltroDoLink(
    filtroDoLink.value,
    activeStatus.value,
    wootConstants.STATUS_TYPE.OPEN
  );
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);
  resetAndFetchData();
  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch (error) {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

watch(activeTeam, () => resetAndFetchData());
watch(crmPipelineId, value => {
  writeFunnelChoice(currentAccountId.value, currentUser.value?.id, value);
  resetAndFetchData();
});

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);
watch(
  computed(() => props.label),
  () => resetAndFetchData()
);
watch([pastaDoEmail, versaoDasPastas], () => resetAndFetchData());
// Os valores do link, não o filtro já combinado: aplicar um filtro avançado não pode disparar uma releitura que o apaga.
watch(assinaturaDoLink, () => resetAndFetchData());

// A seta "Limpar filtros" do topo: um clique limpa tudo. Com o link no endereço (mesmo com o filtro avançado por cima),
// tira o link e o watch acima relê a lista, o que também tira o avançado.
function onResetFilters() {
  limparTudoDoLink(resetAndFetchData);
}

// "Esperando há mais de N min": a conversa que cruza o limite entra numa releitura por minuto.
useReleituraPeriodica(
  computed(() => Boolean(filtroDoLink.value.esperandoMin)),
  () => store.dispatch('releerFiltroDoLink')
);
watch(
  computed(() => props.conversationType),
  (type, previousType) => {
    // Só entrar ou sair de "Em que participo" troca a aba; nas outras listas a escolha da pessoa fica.
    const { PARTICIPATING } = wootConstants.CONVERSATION_TYPE;
    if ([type, previousType].includes(PARTICIPATING)) {
      activeAssigneeTab.value = defaultAssigneeTab();
    }
    resetAndFetchData();
  }
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(chatLists, () => {
  chatsOnView.value = conversationList.value;
});

// Filters can be applied from outside the list, so clear the selection here.
watch(appliedFilters, () => resetBulkActions());
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1 relative"
    :class="[
      { hidden: !showConversationList, 'min-w-0': usaCabecalhoNovo },
      isOnExpandedLayout ? 'basis-full' : 'w-[340px] 2xl:w-[412px]',
    ]"
  >
    <slot />
    <ListaCabecalho
      v-if="usaCabecalhoNovo"
      ref="cabecalhoNovo"
      :page-title="pageTitle"
      :active-status="activeStatus"
      :active-sort-by="activeSortBy"
      :is-on-expanded-layout="isOnExpandedLayout"
      @basic-filter-change="onBasicFilterChange"
      @filters-modal="onToggleAdvanceFiltersModal"
    />
    <ChatListHeader
      v-else
      :page-title="pageTitle"
      :contact-filter="appliedContactFilter"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :has-link-filter="temFiltroDoLink"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="chatListLoading && !conversationList.length"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="onResetFilters"
      @basic-filter-change="onBasicFilterChange"
    />
    <CampoDaBusca v-if="usaCabecalhoNovo" v-model="busca.texto.value" />

    <!-- #1941: lista de uma caixa WAHA comum cujo WhatsApp parou. -->
    <FaixaDoWhatsapp :caixa="inbox" />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <FunnelFilter
      v-if="
        isCrmEnabled && !hasAppliedFiltersOrActiveFolders && !temFiltroDoLink
      "
      v-show="!buscaAtiva"
      v-model="crmPipelineId"
      :lista-nova="listaNova"
    >
      <template v-if="mostraChipDoStatus" #antes>
        <ChipDoStatus :status="activeStatus" @limpar="voltarParaAbertas" />
      </template>
    </FunnelFilter>
    <div
      v-else-if="mostraChipDoStatus"
      v-show="!buscaAtiva"
      class="flex px-4 pb-2"
    >
      <ChipDoStatus :status="activeStatus" @limpar="voltarParaAbertas" />
    </div>

    <template v-if="!hasAppliedFiltersOrActiveFolders && !listaJuntaDoLink">
      <ListaAbas
        v-if="listaNova"
        v-show="!buscaAtiva"
        :painel-id="PAINEL_DA_LISTA"
        :items="assigneeTabItems"
        :active-tab="activeAssigneeTab"
        @chat-tab-change="updateAssigneeTab"
      />
      <ChatTypeTabs
        v-else
        :items="assigneeTabItems"
        :active-tab="activeAssigneeTab"
        is-compact
        @chat-tab-change="updateAssigneeTab"
      />
    </template>

    <ResultadoDaBusca
      v-if="buscaAtiva"
      :resultado="busca.resultado.value"
      :buscado="busca.buscado.value"
      :texto="busca.texto.value"
      :carregando="busca.carregando.value"
      :erro="busca.erro.value"
      @tentar="busca.buscar"
    />
    <p
      v-if="!buscaAtiva && !chatListLoading && !conversationList.length"
      class="flex overflow-auto justify-center items-center p-4"
      :class="usaCabecalhoNovo && 'text-center text-sm text-n-slate-11'"
      :data-lista-vazia="usaCabecalhoNovo || undefined"
    >
      {{ textoDaListaVazia }}
    </p>
    <ConversationBulkActions
      v-show="!buscaAtiva"
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      :class="isOnExpandedLayout && 'sm:!w-[24rem] !w-full'"
      @select-all-conversations="toggleSelectAll"
    />
    <ConversationList
      v-show="!buscaAtiva"
      :id="listaNova ? PAINEL_DA_LISTA : undefined"
      ref="conversationListComponentRef"
      :role="listaComAbas ? 'tabpanel' : undefined"
      :aria-labelledby="listaComAbas ? `lista-aba-${abaDaLista}` : undefined"
      :conversation-list="conversationList"
      :is-loading="chatListLoading"
      :show-end-of-list-message="showEndOfListMessage"
      :label="label"
      :team-id="teamId"
      :folders-id="foldersId"
      :conversation-type="conversationType"
      :show-assignee="showAssigneeInConversationCard"
      :is-on-expanded-layout="isOnExpandedLayout"
      @load-more="loadMoreConversations"
    />
    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />
    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>
    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>
