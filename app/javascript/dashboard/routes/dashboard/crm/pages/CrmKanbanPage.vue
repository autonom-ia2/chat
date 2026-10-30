<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { chaveDoCard, chaveDoErroDeAcesso } from '../helpers/accessErrors';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useNomeDaEtiqueta } from 'dashboard/composables/useNomeDaEtiqueta';
import { defaultFilters } from 'dashboard/store/modules/crmKanban';
import { useCrmPermissions } from '../composables/useCrmPermissions';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';
import {
  canSeeBookingSettings,
  isBookingV2Available,
} from 'dashboard/routes/dashboard/settings/booking/bookingAccess';
import { declararContexto } from 'dashboard/composables/useContextoDaTela';
import crmMeetingsAPI from 'dashboard/api/crmMeetings';
import CtwaCampaignsAPI from 'dashboard/api/ctwaCampaigns';
import {
  CHAVES_DO_LINK,
  CHAVES_DO_MEU_DIA,
  filtroDoMeuDiaPeloLink,
  filtrosDoLink,
  semChaves,
} from '../helpers/filtrosDoLink';
import { useCrmOrigin } from '../composables/useCrmOrigin';
import CompanyAPI from 'dashboard/api/companies';
import { useRelationshipPermissions } from 'dashboard/composables/useRelationshipPermissions';
import MetaConversionsAPI from 'dashboard/api/metaConversions';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import Draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ConfirmModal from 'dashboard/components/widgets/modal/ConfirmationModal.vue';
import CrmKanbanCard from '../components/CrmKanbanCard.vue';
import { nomeDoMes } from '../components/numeros/v2/numerosTextos';
import CrmKanbanZoom from '../components/CrmKanbanZoom.vue';
import { useCrmKanbanZoom } from '../composables/useCrmKanbanZoom';
import { useCrmKanbanAutoScroll } from '../composables/useCrmKanbanAutoScroll';
import { KANBAN_ZOOM_DRAG_CLASSES } from '../helpers/kanbanZoom';
import { diaDoVencimento } from '../helpers/closeDate';
import CrmKanbanFiltersDrawer from '../components/CrmKanbanFiltersDrawer.vue';
import CardGaveta from '../components/card/CardGaveta.vue';
import CrmOpportunityFromContact from '../components/CrmOpportunityFromContact.vue';
import CrmPipelineDrawer from '../components/CrmPipelineDrawer.vue';
import CrmInboxSettingsDrawer from '../components/CrmInboxSettingsDrawer.vue';
import CrmBookingProfilesDrawer from '../components/CrmBookingProfilesDrawer.vue';
import CrmCardsTable from '../components/list/CrmCardsTable.vue';
import CrmListExportButton from '../components/list/CrmListExportButton.vue';
import CrmTableColumnSettings from '../components/list/CrmTableColumnSettings.vue';
import CrmSavedViews from '../components/list/CrmSavedViews.vue';
import CrmResultTabs from '../components/list/CrmResultTabs.vue';
import CrmBulkActionBar from '../components/list/CrmBulkActionBar.vue';
import CrmCalendar from '../components/calendar/CrmCalendar.vue';
import CrmAbaNumeros from '../components/numeros/CrmAbaNumeros.vue';
import ListaAcao from '../components/lista-acao/ListaAcao.vue';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { accountTimeZone } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { useMenuNovo } from 'dashboard/components-next/sidebar/fork/useMenuNovo';
import CalendarioOuro from '../components/calendario/CalendarioOuro.vue';
import CrmCalendarQuickAdd from '../components/calendar/CrmCalendarQuickAdd.vue';
// #1460/#1461/#1462: lembrete pelo calendário na gaveta nova (flag crm_lembretes_v2).
import LembreteGaveta from '../components/lembrete/LembreteGaveta.vue';
import MensagemMarcadaGaveta from '../components/mensagemMarcada/MensagemMarcadaGaveta.vue';
import CrmCalendarMeetingScheduler from '../components/calendar/CrmCalendarMeetingScheduler.vue';
import CrmMeetingDetail from '../components/calendar/CrmMeetingDetail.vue';
// #2095 (flag crm_arquivados): Arquivados, Funis arquivados e as janelas novas de arquivar e restaurar.
import PainelArquivados from '../components/arquivados/PainelArquivados.vue';
import PainelFunisArquivados from '../components/arquivados/PainelFunisArquivados.vue';
import RestaurarConflito from '../components/arquivados/RestaurarConflito.vue';
import ArquivarFunilDialogo from '../components/arquivados/ArquivarFunilDialogo.vue';
import CrmAviso from '../components/arquivados/CrmAviso.vue';
import {
  FUNIS_ARQUIVADOS,
  useArquivadosNaPagina,
} from '../components/arquivados/useArquivadosNaPagina';
import {
  FAILURE_STATUSES,
  SUCCESS_STATUSES,
  countsAsSale,
  outcomeLabels,
  outcomeStatuses,
  avisoDoDesfecho,
} from '../helpers/cardOutcome';
import { ehCobranca } from '../components/funil/funil';
import {
  buildCrmCardColumns,
  DEFAULT_COLUMN_ORDER,
  DEFAULT_COLUMN_VISIBILITY,
  COLUMN_TO_SORT_PARAM,
} from '../components/list/cardColumns.js';

const store = useStore();
const { t, locale } = useI18n();
const { zoom, zoomClass, setZoom, persistenceFailed } = useCrmKanbanZoom();
const kanbanBoard = ref(null);
const isRTL = useMapGetter('accounts/isRTL');
let suppressClickAfterDrag = false;
const resetKanbanClick = () => {
  suppressClickAfterDrag = false;
};
const ignoreDragClick = event => {
  // Sortable can clear its own click guard when crossing sibling cards.
  // Block only the pointer-generated trailing click, not keyboard activation.
  if (!suppressClickAfterDrag || event.detail === 0) return;
  suppressClickAfterDrag = false;
  event.preventDefault();
  event.stopPropagation();
};
const { start: startAutoScroll, stop: stopAutoScroll } = useCrmKanbanAutoScroll(
  kanbanBoard,
  zoom
);

const pipelines = useMapGetter('crmKanban/getPipelines');
const stages = useMapGetter('crmKanban/getStages');
const cardsList = useMapGetter('crmKanban/getCardsList');
const cardsListMeta = useMapGetter('crmKanban/getCardsListMeta');
const followUps = useMapGetter('crmKanban/getFollowUps');
const calendarEvents = useMapGetter('crmKanban/getCalendarEvents');
const lembreteGaveta = ref({
  show: false,
  modo: 'novo',
  dia: new Date(),
  serieId: null,
  followUpId: null,
});
// #1590: a Mensagem marcada nova (flag crm_mensagem_marcada), pelo "+ Novo" do
// calendário; o card abre a mesma gaveta por conta própria.
const mensagemMarcada = ref({ show: false, dia: '' });
const uiFlags = useMapGetter('crmKanban/getUIFlags');
const storedFilters = useMapGetter('crmKanban/getFilters');
const listPrefs = useMapGetter('crmKanban/getListPrefs');
const listSort = useMapGetter('crmKanban/getListSort');
const listGroupBy = useMapGetter('crmKanban/getListGroupBy');
const listSelection = useMapGetter('crmKanban/getListSelection');
const savedViews = useMapGetter('crmKanban/getSavedViews');
const currentUser = useMapGetter('getCurrentUser');
const currentAccountId = useMapGetter('getCurrentAccountId');
const currentRole = useMapGetter('getCurrentRole');
const getAccount = useMapGetter('accounts/getAccount');
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const teams = useMapGetter('teams/getTeams');
const accountLabels = useMapGetter('labels/getLabels');
const { nomeDe: nomeDaEtiqueta } = useNomeDaEtiqueta();
const {
  canManageCards,
  canViewCrm,
  canMoveCards,
  canDeleteCards,
  canManagePipelines,
  canManageAi,
  canExportCrm,
  canAdminCrm,
  canSeeSalesValues,
} = useCrmPermissions();

// #2075 — sem a chave de valores o servidor ignora filtro e ordem por valor; a tela também larga os dois.
const temFiltroDeValor = f =>
  Boolean(f) && (`${f.valueMin ?? ''}` !== '' || `${f.valueMax ?? ''}` !== '');
const semFiltroDeValor = f =>
  canSeeSalesValues.value ? f : { ...f, valueMin: '', valueMax: '' };
const ordemPermitida = sort =>
  !canSeeSalesValues.value && sort?.id === 'value' ? null : sort;

// Ação em massa (#1874): cada botão só para quem pode a ação; sem nenhuma, a lista não tem seleção.
const bulkPermissions = computed(() => ({
  move: canMoveCards.value,
  assign: canManageCards.value,
  status: canManageCards.value,
  archive: canDeleteCards.value,
}));
const canBulkAct = computed(() =>
  Object.values(bulkPermissions.value).some(Boolean)
);

const CRM_CALENDAR_MEETINGS_FEATURE = 'CRM_CALENDAR_MEETINGS_ENABLED';
const isCrmAiEnabled = computed(
  () =>
    store.getters['globalConfig/get']?.crmAiEnabled === true ||
    window.globalConfig?.CRM_AI_ENABLED === 'true'
);

const route = useRoute();
const router = useRouter();
// Calendar-only sub-page (route meta.calendarOnly): opens straight on the calendar
// with the kanban/list/calendar switch and "New pipeline" button hidden.
const isCalendarOnly = computed(() => route.meta?.calendarOnly === true);
// Calendário "Meu dia" (#1568): com a flag da conta, a página do calendário
// abre a tela nova; desligada, a de sempre, sem mudança nenhuma.
const meuDiaLigado = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_CALENDARIO_OURO
    ] === true
);
const calendarioOuro = computed(
  () => isCalendarOnly.value && meuDiaLigado.value
);
// No "Meu dia", o funil é opcional: vazio = todos os funis (decisão 2 do #1568).
// #1883: o link do Números pode abrir o Meu dia já filtrado (quem, tipos e funil).
const filtroDoMeuDia = filtroDoMeuDiaPeloLink(route.query);
const funilDoCalendario = ref(filtroDoMeuDia?.funil ?? null);

const currentPipelineId = ref('');
// Menu novo (#1617): `?view=list|calendar` abre já na vista (a página Números volta por aqui) e a troca de
// vista fica no endereço, para o recarregar abrir a mesma. Com a flag desligada, como sempre foi.
const { ligado: menuNovo } = useMenuNovo();
const VISTAS_PELO_ENDERECO = ['list', 'calendar'];
const vistaDoEndereco = () =>
  menuNovo.value
    ? VISTAS_PELO_ENDERECO.find(vista => vista === route.query.view)
    : undefined;
const viewMode = ref(
  isCalendarOnly.value ? 'calendar' : vistaDoEndereco() || 'kanban'
);
// #1883: ao recarregar ou abrir o link numa aba nova, a flag da conta chega depois da tela.
watch(menuNovo, ligado => {
  const vista = vistaDoEndereco();
  if (ligado && vista && viewMode.value === 'kanban' && !isCalendarOnly.value)
    viewMode.value = vista;
});
// The two CRM routes share this component, so the instance is reused on navigation:
// keep viewMode in sync with the route (force calendar on the calendar-only page).
watch(isCalendarOnly, only => {
  viewMode.value = only ? 'calendar' : 'kanban';
});
// #1894: com o Meu dia ligado, o calendário mora no endereço dele (crm_calendar_index), não numa vista do quadro;
// a aba e o `?view=calendar` levam até lá, e o calendário antigo nunca abre.
const meuDiaNoLugarDoCalendario = mode =>
  mode === 'calendar' && meuDiaLigado.value && !isCalendarOnly.value;
// Leva o resto do endereço (ex.: new_contact_id), menos o `view`. Navegação recusada volta ao quadro, para a área
// não ficar vazia.
const irParaOMeuDia = navegar => {
  const query = Object.fromEntries(
    Object.entries(route.query).filter(([chave]) => chave !== 'view')
  );
  return Promise.resolve(
    navegar({
      name: 'crm_calendar_index',
      params: { accountId: route.params.accountId },
      query,
    })
  ).then(falha => {
    if (falha) viewMode.value = 'kanban';
  });
};
// #1894: `?view=calendar` (ou a flag que chega depois da tela) com o Meu dia ligado troca o endereço pelo do Meu dia.
watch(
  [viewMode, meuDiaLigado],
  ([vista]) => {
    if (meuDiaNoLugarDoCalendario(vista)) irParaOMeuDia(router.replace);
  },
  { immediate: true }
);
const filters = ref(semFiltroDeValor({ ...storedFilters.value }));
const drawerMode = ref('create');
const selectedCard = ref(null);
// Acesso por funil (#1149): o card aberto diz se a pessoa pode mexer nele.
// Card aberto para editar só libera os botões com a resposta do servidor (fecha
// se o detalhe não carregar); card novo não tem essa trava.
const podeMexerNoCard = computed(
  () => drawerMode.value !== 'edit' || selectedCard.value?.can_edit === true
);
// Quem não pode ser dono, por card da lista (#1149).
const donosBarradosPorCard = ref({});
// Mostra a recusa por funil quando é ela; senão, o aviso de sempre.
const avisarErro = (error, chavePadrao) =>
  useAlert(t(chaveDoErroDeAcesso(error) || chavePadrao));
const creationContact = ref(null);
const showDrawer = ref(false);
// Which tab the card drawer lands on when opened ('followups' from the calendar
// quick-add "Continuar"; null → default summary).
const drawerInitialTab = ref(null);
const openedRouteCardId = ref(null);
const pipelineDrawerMode = ref('create');
// #934 — o card aberto (inclusive pelo `card_id` da rota), a seleção da lista e os filtros vão ao Guia.
declararContexto({
  aberto: () =>
    showDrawer.value && selectedCard.value?.id
      ? [{ recurso: 'crm/cards', id: selectedCard.value.id }]
      : [],
  selecionados: () => ({ recurso: 'crm/cards', ids: listSelection.value }),
  filtros: () => ({ pipeline_id: currentPipelineId.value, ...filters.value }),
});
const showPipelineDrawer = ref(false);
const pipelineInboxes = ref([]);
// Authoritative, unfiltered stage list (with real total_cards_count) for the funnel-edit
// drawer and the delete-stage target picker. Deliberately NOT the board's `stages` getter:
// that one is scoped to whatever stage filter/pagination the Kanban view currently has
// active, and its cards_count/total_cards_count are only populated when the board fetch
// that produced it happened to pass include_counts (e.g. right after creating a card it
// doesn't), which let a stale/absent count silently bypass the "has cards" picker.
const pipelineDrawerStages = ref([]);
const cardDrawerStages = ref([]);
const showInboxSettingsDrawer = ref(false);
const showBookingProfilesDrawer = ref(false);
const inboxSettings = ref([]);
// Resultado do último salvamento de caixa, para a janela saber qual caixa salvou.
const inboxSaveResult = ref(null);
const inboxSettingStagesByPipeline = ref({});
const dragSnapshot = ref(null);
const loadError = ref('');
const confirmModal = ref(null);
const confirmConfig = ref({
  title: '',
  description: '',
  confirmLabel: '',
});
// Set only while the delete-stage confirm is open, so the shared confirm modal knows to
// render the target-stage picker (other askConfirmation callers leave this null).
const stageToDelete = ref(null);
const deleteStageTargetId = ref('');

const isLoading = computed(
  () => uiFlags.value.isFetchingPipelines || uiFlags.value.isFetchingBoard
);
const hasPipelines = computed(() => pipelines.value.length > 0);
const hasBoardContent = computed(() => stages.value.length > 0);
const selectedPipeline = computed(() =>
  pipelines.value.find(
    pipeline => pipeline.id === Number(currentPipelineId.value)
  )
);
// #1498 — funil de Atender: "Novo atendimento" e cartão sem valor (a
// Cobrança mostra o valor a receber).
const funilDeVenda = computed(() => countsAsSale(selectedPipeline.value));
const quadroComValor = computed(
  () => funilDeVenda.value || ehCobranca(selectedPipeline.value)
);

const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const arquivadosLigado = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_ARQUIVADOS
    ] === true
);
// #2283: Lista nova "o que fazer agora" (flag de conta). Desligada: a Lista de sempre, igual.
const listaAcaoLigada = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_LISTA_ACAO
    ] === true
);
const listaAcao = computed(
  () => listaAcaoLigada.value && viewMode.value === 'list'
);
const listaAcaoRef = ref(null);
// Datas da Lista nova no fuso da conta (o mesmo padrão do servidor), nunca no do navegador.
const fusoDaListaAcao = computed(() => {
  const conta = getAccount.value(currentAccountId.value);
  return fusoDaConta(conta) || accountTimeZone(conta);
});
// No celular, as abas Quadro/Lista/Calendário/Números viram 4 colunas com o ícone em cima.
const ABA_DA_LISTA_ACAO =
  'max-md:min-h-14 max-md:flex-col max-md:justify-center max-md:gap-0.5 max-md:px-1 max-md:text-[13px]';
const arquivados = useArquivadosNaPagina({
  t,
  ligado: arquivadosLigado,
  funilAtual: () => selectedPipeline.value,
});
// O erro de arquivar é daquele card: outro card aberto começa sem ele.
watch(
  () => selectedCard.value?.id,
  () => {
    arquivados.erroArquivarCard.value = '';
  }
);
// Com a flag, "Funis arquivados" fica no fim da escolha de funil (uma opção à parte, que abre o painel). Sem funil
// arquivado, não aparece.
const pipelineGroups = computed(() =>
  arquivadosLigado.value && arquivados.totalDeFunis.value
    ? [
        { label: '', options: pipelineOptions.value },
        arquivados.opcaoDosFunisArquivados.value,
      ]
    : []
);
const escolherFunil = valor => {
  if (valor === FUNIS_ARQUIVADOS) {
    arquivados.abrirFunis();
    return;
  }
  currentPipelineId.value = valor;
};
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);
const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);
const priorityOptions = computed(() => [
  { value: 'low', label: t('CRM_KANBAN.PRIORITY.LOW') },
  { value: 'medium', label: t('CRM_KANBAN.PRIORITY.MEDIUM') },
  { value: 'high', label: t('CRM_KANBAN.PRIORITY.HIGH') },
  { value: 'urgent', label: t('CRM_KANBAN.PRIORITY.URGENT') },
]);
const followUpStatusOptions = computed(() => [
  { value: 'none', label: t('CRM_KANBAN.FOLLOW_UP_FILTER.NONE') },
  { value: 'pending', label: t('CRM_KANBAN.FOLLOW_UP_FILTER.PENDING') },
  { value: 'overdue', label: t('CRM_KANBAN.FOLLOW_UP_FILTER.OVERDUE') },
]);
// List-view-only "Resultado" filter (won/lost/archived). The board stays
// open-only, so this control is rendered only when viewMode === 'list'.
const resultOptions = computed(() => {
  const statuses = outcomeStatuses(selectedPipeline.value);
  const labels = outcomeLabels(t, selectedPipeline.value);
  return [
    { value: 'open', label: t('CRM_KANBAN.RESULT_FILTER.OPEN') },
    { value: statuses.success, label: labels.success },
    { value: statuses.failure, label: labels.failure },
    { value: 'archived', label: t('CRM_KANBAN.RESULT_FILTER.ARCHIVED') },
  ];
});
const teamOptions = computed(() =>
  teams.value.map(team => ({ value: team.id, label: team.name }))
);
const stageOptions = computed(() =>
  stages.value.map(stage => ({ value: stage.id, label: stage.name }))
);
const responsibleOptions = computed(() => [
  { value: 'agent', label: t('CRM_KANBAN.RESPONSIBLE_FILTER.AGENT') },
  { value: 'bot', label: t('CRM_KANBAN.RESPONSIBLE_FILTER.BOT') },
  { value: 'none', label: t('CRM_KANBAN.RESPONSIBLE_FILTER.NONE') },
]);
const staleOptions = computed(() => [
  { value: '3', label: t('CRM_KANBAN.STALE_FILTER.THREE_DAYS') },
  { value: '7', label: t('CRM_KANBAN.STALE_FILTER.SEVEN_DAYS') },
  { value: '14', label: t('CRM_KANBAN.STALE_FILTER.FOURTEEN_DAYS') },
  { value: '30', label: t('CRM_KANBAN.STALE_FILTER.THIRTY_DAYS') },
]);
const linkedOptions = computed(() => [
  { value: 'false', label: t('CRM_KANBAN.LINKED_FILTER.LINKED') },
  { value: 'true', label: t('CRM_KANBAN.LINKED_FILTER.STANDALONE') },
]);
// Filtros com a opção vazia ("Todos"/"Todas") na frente, como no select nativo antigo.
const withEmptyChoice = (label, options) => [{ value: '', label }, ...options];
const inboxChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL_FEMININE'), inboxOptions.value)
);
const ownerChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), agentOptions.value)
);
const priorityChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL_FEMININE'), priorityOptions.value)
);
const followUpStatusChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), followUpStatusOptions.value)
);
const responsibleChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), responsibleOptions.value)
);
const teamChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), teamOptions.value)
);
const staleChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.STALE_PLACEHOLDER'), staleOptions.value)
);
const linkedChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), linkedOptions.value)
);
const resultChoices = computed(() =>
  withEmptyChoice(t('CRM_KANBAN.FILTERS.ALL'), resultOptions.value)
);
const labelOptions = computed(() =>
  accountLabels.value.map(label => ({
    value: label.id,
    label: nomeDaEtiqueta(label.title),
    color: label.color,
  }))
);
// Opções de campanha CTWA (headline + nº de conversas por anúncio), carregadas
// do endpoint único /ctwa_campaigns. `value` fica String — source_id de anúncio
// Meta estoura Number.MAX_SAFE_INTEGER, então nada de coerção numérica.
const campaignOptions = ref([]);
const { campaignOptionLabel } = useCrmOrigin();
const companyOptions = ref([]);
const companySearch = ref('');
const companyLoading = ref(false);
const companyFilterAvailable = ref(true);
// O filtro de empresa busca na base: sem ver contatos, ele não aparece (#1849).
const { canViewRelationshipRecords } = useRelationshipPermissions();
const selectedCompanyOption = ref(null);
let companySearchTimer = null;
let companySearchRequestSeq = 0;
let selectedCompanyRequestSeq = 0;
const campaignFilterOptions = computed(() =>
  campaignOptions.value.map(option => ({
    value: String(option.source_id),
    label: campaignOptionLabel(option),
    count: option.count,
  }))
);
const companyFilterOptions = computed(() => {
  const options = [
    { value: '', label: t('CRM_KANBAN.FILTERS.ALL_COMPANIES') },
    { value: 'none', label: t('CRM_KANBAN.FILTERS.NO_COMPANY') },
    ...companyOptions.value,
  ];
  const selected = selectedCompanyOption.value;
  if (
    selected &&
    !options.some(item => String(item.value) === String(selected.value))
  ) {
    options.push(selected);
  }
  return options;
});

const loadCampaignOptions = async () => {
  try {
    const response = await CtwaCampaignsAPI.get();
    campaignOptions.value = response.data.payload || [];
  } catch {
    // Sem opções o grupo mostra só o placeholder; não bloqueia o board.
    campaignOptions.value = [];
  }
};

const loadCompanyOptions = async query => {
  const term = String(query || '').trim();
  companySearchRequestSeq += 1;
  const requestSeq = companySearchRequestSeq;
  if (!term) {
    companyOptions.value = [];
    companyFilterAvailable.value = true;
    companyLoading.value = false;
    return;
  }

  companyLoading.value = true;
  try {
    const response = await CompanyAPI.search(term, 1, 'name');
    if (requestSeq !== companySearchRequestSeq) return;
    companyOptions.value = (response.data.payload || []).map(company => ({
      value: company.id,
      label: company.name,
    }));
    companyFilterAvailable.value = true;
  } catch (error) {
    if (requestSeq !== companySearchRequestSeq) return;
    // Company search is permission/feature scoped. Keep the filter explicit
    // when the account cannot use it instead of presenting an empty fake list.
    companyOptions.value = [];
    companyFilterAvailable.value = filters.value.companyId
      ? true
      : ![403, 404].includes(error?.response?.status);
  } finally {
    if (requestSeq === companySearchRequestSeq) companyLoading.value = false;
  }
};

const loadSelectedCompanyOption = async companyId => {
  const id = String(companyId || '').trim();
  selectedCompanyRequestSeq += 1;
  const requestSeq = selectedCompanyRequestSeq;
  if (!id || id === 'none') {
    selectedCompanyOption.value = null;
    return;
  }

  const fromSearch = companyOptions.value.find(
    option => String(option.value) === id
  );
  if (fromSearch) {
    selectedCompanyOption.value = fromSearch;
    return;
  }

  try {
    const response = await CompanyAPI.show(id);
    if (requestSeq !== selectedCompanyRequestSeq) return;
    const company = response.data.payload;
    if (company?.id == null || String(company.id) !== id) {
      selectedCompanyOption.value = {
        value: id,
        label: t('CRM_KANBAN.FILTERS.SELECTED_COMPANY_FALLBACK', { id }),
      };
      return;
    }
    selectedCompanyOption.value = {
      value: company.id,
      label:
        company.name ||
        t('CRM_KANBAN.FILTERS.SELECTED_COMPANY_FALLBACK', { id }),
    };
  } catch {
    if (requestSeq !== selectedCompanyRequestSeq) return;
    // Keep the previous canonical option when a refresh fails. The active
    // company filter must never silently fall back to "all companies".
    selectedCompanyOption.value = {
      value: id,
      label: t('CRM_KANBAN.FILTERS.SELECTED_COMPANY_FALLBACK', { id }),
    };
  }
};

const onCompanySearch = query => {
  companySearch.value = query;
  if (companySearchTimer) clearTimeout(companySearchTimer);
  companySearchTimer = setTimeout(() => loadCompanyOptions(query), 250);
};

// Sem ver contatos não há filtro de empresa (#1849): o que veio da URL ou de um filtro salvo sai.
watch(
  () => !canViewRelationshipRecords.value && Boolean(filters.value.companyId),
  semPermissao => {
    if (semPermissao) filters.value = { ...filters.value, companyId: '' };
  },
  { immediate: true }
);

watch(
  () => filters.value.companyId,
  companyId => loadSelectedCompanyOption(companyId),
  { immediate: true }
);

// The Meta conversion column is only relevant for accounts running Click-to-WhatsApp
// ads, so campaignOptions doubles as the gate. Fetch the ledger status for the cards
// currently in the List view and expose it per card for the column badge.
// Paid CTWA only: organic referrals and tracked links (U1/U2) also live in
// campaignOptions now, but the Meta CAPI column/gate is about ad attribution.
// Legacy touches predate the `source` field and were always paid CTWA.
const isMetaSyncActive = computed(() =>
  campaignOptions.value.some(
    option => !option.source || option.source === 'meta_ctwa'
  )
);
const metaByCard = ref({});
// Monotonic request token: a stale (out-of-order) response must never overwrite
// the map built from a fresher card list (load-more / realtime bursts).
let metaRequestSeq = 0;

const loadMetaConversions = async () => {
  if (!isMetaSyncActive.value || !cardsList.value.length) {
    metaByCard.value = {};
    return;
  }
  metaRequestSeq += 1;
  const requestSeq = metaRequestSeq;
  try {
    const response = await MetaConversionsAPI.getForCards(
      cardsList.value.map(card => card.id)
    );
    if (requestSeq !== metaRequestSeq) return;
    metaByCard.value = (response.data.payload || []).reduce((map, row) => {
      map[row.card_id] = row;
      return map;
    }, {});
  } catch {
    if (requestSeq === metaRequestSeq) metaByCard.value = {};
  }
};

const cardsListWithMeta = computed(() =>
  cardsList.value.map(card => ({
    ...card,
    meta_conversion: metaByCard.value[card.id] || null,
  }))
);

// Acesso por funil (#1149): busca, para os cards da lista que ainda não têm,
// quem não pode ser dono. Sem acesso por funil, o servidor responde vazio.
const carregarDonosBarrados = async cards => {
  const faltam = cards.filter(
    card => !(chaveDoCard(card) in donosBarradosPorCard.value)
  );
  if (!faltam.length) return;
  try {
    const { data } = await CrmKanbanAPI.getOwnerOptions({
      cardIds: faltam.map(card => card.id),
    });
    const novos = Object.fromEntries(
      faltam.map(card => [chaveDoCard(card), data.payload.cards[card.id] || []])
    );
    donosBarradosPorCard.value = { ...donosBarradosPorCard.value, ...novos };
  } catch {
    // Sem a lista, o servidor ainda recusa o dono sem o funil e a tela avisa.
  }
};
watch(cardsList, cards => carregarDonosBarrados(cards || []));
const donosBarradosNaSelecao = computed(() => [
  ...new Set(
    (cardsList.value || [])
      .filter(card => listSelection.value.includes(card.id))
      .flatMap(card => donosBarradosPorCard.value[chaveDoCard(card)] || [])
  ),
]);

watch(cardsList, loadMetaConversions);

const showFiltersDrawer = ref(false);
const configurationPopover = ref(null);

const labelForOption = (options, value) =>
  options.value.find(option => String(option.value) === String(value))?.label ||
  String(value);

// Active-filter chips shown in the toolbar. Each chip knows how to clear itself.
const activeFilterChips = computed(() => {
  const chips = [];
  const f = filters.value;
  if (f.search) {
    chips.push({
      key: 'search',
      label: `${t('CRM_KANBAN.FILTERS.SEARCH')}: ${f.search}`,
    });
  }
  if (f.inboxId) {
    chips.push({
      key: 'inboxId',
      label: `${t('CRM_KANBAN.FILTERS.INBOX')}: ${labelForOption(inboxOptions, f.inboxId)}`,
    });
  }
  if (f.ownerId) {
    chips.push({
      key: 'ownerId',
      label: `${t('CRM_KANBAN.FILTERS.OWNER')}: ${labelForOption(agentOptions, f.ownerId)}`,
    });
  }
  if (f.companyId) {
    chips.push({
      key: 'companyId',
      label: `${t('CRM_KANBAN.FILTERS.COMPANY')}: ${labelForOption(companyFilterOptions, f.companyId)}`,
    });
  }
  if (f.priority) {
    chips.push({
      key: 'priority',
      label: `${t('CRM_KANBAN.FILTERS.PRIORITY')}: ${labelForOption(priorityOptions, f.priority)}`,
    });
  }
  if (f.followUpStatus) {
    chips.push({
      key: 'followUpStatus',
      label: `${t('CRM_KANBAN.FILTERS.FOLLOW_UP')}: ${labelForOption(followUpStatusOptions, f.followUpStatus)}`,
    });
  }
  // 'open' is the default result (the "Em andamento" tab), so it is not a real
  // active filter. Any other value — won/lost/archived OR '' ("Todos") — IS a
  // deviation, so it must chip and be clearable; otherwise picking "Todos" in the
  // popover would strand the list in a state the toolbar can't reset.
  if (f.result !== 'open' && viewMode.value === 'list') {
    // '' is the "Todos" (all statuses) option, which isn't in resultOptions.
    const resultLabel =
      f.result === ''
        ? t('CRM_KANBAN.FILTERS.ALL')
        : labelForOption(resultOptions, f.result);
    chips.push({
      key: 'result',
      label: `${t('CRM_KANBAN.FILTERS.RESULT')}: ${resultLabel}`,
    });
  }
  if (f.closedIn && viewMode.value === 'list') {
    chips.push({
      key: 'closedIn',
      label: t('CRM_FILTRO_DO_LINK.FECHADO_NO_MES'),
    });
  }
  // Números › Origens (#2001, F6): os filtros que chegam do "Ver" (só da Lista).
  if (f.origem && viewMode.value === 'list') {
    chips.push({
      key: 'origem',
      label: `${t('CRM_FILTRO_DO_LINK.ORIGEM')}: ${t(`CRM_NUMEROS_ORIGENS.NOMES.${f.origem.toUpperCase()}`)}`,
    });
  }
  if (f.anuncio && viewMode.value === 'list') {
    chips.push({
      key: 'anuncio',
      label: `${t('CRM_FILTRO_DO_LINK.ANUNCIO')}: ${labelForOption(campaignFilterOptions, f.anuncio)}`,
    });
  }
  if (f.entrouEm && viewMode.value === 'list') {
    chips.push({
      key: 'entrouEm',
      label: t('CRM_FILTRO_DO_LINK.ENTROU_EM_MES', {
        mes: nomeDoMes(f.entrouEm, {
          locale: String(locale.value).replace('_', '-'),
        }),
      }),
    });
  }
  if (f.stageIds?.length) {
    const names = f.stageIds
      .map(id => labelForOption(stageOptions, id))
      .join(', ');
    chips.push({
      key: 'stageIds',
      label: `${t('CRM_KANBAN.FILTERS.STAGE')}: ${names}`,
    });
  }
  if (f.labelIds?.length) {
    const names = f.labelIds
      .map(id => labelForOption(labelOptions, id))
      .join(', ');
    chips.push({
      key: 'labelIds',
      label: `${t('CRM_KANBAN.FILTERS.LABELS')}: ${names}`,
    });
  }
  if (f.campaignSourceIds?.length) {
    // labelForOption cai para o próprio source_id quando a option não carrega
    // headline (mesmo fallback do multi-select).
    const names = f.campaignSourceIds
      .map(id => labelForOption(campaignFilterOptions, id))
      .join(', ');
    chips.push({
      key: 'campaignSourceIds',
      label: `${t('CRM_KANBAN.FILTERS.CAMPAIGN')}: ${names}`,
    });
  }
  if (f.teamId) {
    chips.push({
      key: 'teamId',
      label: `${t('CRM_KANBAN.FILTERS.TEAM')}: ${labelForOption(teamOptions, f.teamId)}`,
    });
  }
  if (f.responsibleKind) {
    chips.push({
      key: 'responsibleKind',
      label: `${t('CRM_KANBAN.FILTERS.RESPONSIBLE')}: ${labelForOption(responsibleOptions, f.responsibleKind)}`,
    });
  }
  if (f.valueMin !== '' || f.valueMax !== '') {
    const min = f.valueMin === '' ? '…' : f.valueMin;
    const max = f.valueMax === '' ? '…' : f.valueMax;
    chips.push({
      key: 'value',
      label: `${t('CRM_KANBAN.FILTERS.VALUE_RANGE')}: ${min} – ${max}`,
    });
  }
  if (f.scoreMin !== '' || f.scoreMax !== '') {
    const min = f.scoreMin === '' ? '…' : f.scoreMin;
    const max = f.scoreMax === '' ? '…' : f.scoreMax;
    chips.push({
      key: 'score',
      label: `${t('CRM_KANBAN.FILTERS.SCORE_RANGE')}: ${min} – ${max}`,
    });
  }
  if (f.staleDays) {
    chips.push({
      key: 'staleDays',
      label: `${t('CRM_KANBAN.FILTERS.STALE')}: ${labelForOption(staleOptions, f.staleDays)}`,
    });
  }
  if (f.standalone) {
    chips.push({
      key: 'standalone',
      label: `${t('CRM_KANBAN.FILTERS.LINKED')}: ${labelForOption(linkedOptions, f.standalone)}`,
    });
  }
  // #2150 — sem crm_manage_ai o servidor ignora o filtro: a etiqueta não finge que ele vale.
  if (f.aiPending && canManageAi.value) {
    chips.push({ key: 'aiPending', label: t('CRM_KANBAN.FILTERS.AI_PENDING') });
  }
  return chips;
});

const activeFilterCount = computed(() => activeFilterChips.value.length);
// #2283: na Lista nova, aba e busca são dela; conta só o que veio da gaveta.
const filtrosDaListaAcao = computed(
  () =>
    activeFilterChips.value.filter(
      chip => !['result', 'search'].includes(chip.key)
    ).length
);

const viewModeOptions = computed(() => [
  {
    id: 'kanban',
    // #2283: com a Lista nova, "Quadro" (a palavra que a pessoa entende).
    label: listaAcaoLigada.value
      ? t('CRM_LISTA_ACAO.VISTAS.QUADRO')
      : t('CRM_KANBAN.VIEWS.KANBAN'),
    icon: 'i-lucide-kanban',
  },
  { id: 'list', label: t('CRM_KANBAN.VIEWS.LIST'), icon: 'i-lucide-list' },
  {
    id: 'calendar',
    label: t('CRM_KANBAN.VIEWS.CALENDAR'),
    icon: 'i-lucide-calendar-days',
  },
]);

const fetchBoard = (includeCounts = false) => {
  if (!currentPipelineId.value) return Promise.resolve();
  return store.dispatch('crmKanban/fetchBoard', {
    pipelineId: currentPipelineId.value,
    includeCounts,
  });
};

const loadCurrentBoard = async (includeCounts = false) => {
  loadError.value = '';
  try {
    await fetchBoard(includeCounts);
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.LOAD');
    useAlert(t('CRM_KANBAN.ERRORS.LOAD'));
  }
};

const calendarRange = () => {
  const now = new Date();
  const from = new Date(now);
  from.setDate(now.getDate() - 30);
  const to = new Date(now);
  to.setDate(now.getDate() + 90);
  return {
    from: from.toISOString(),
    to: to.toISOString(),
  };
};

// List pagination: page 1 replaces the list; "Load more" bumps the page and
// appends. has-more is derived from loaded rows vs the server total count.
const listPage = ref(1);
const listPageSize = 75;
const hasMoreCards = computed(
  () => cardsList.value.length < (cardsListMeta.value?.count || 0)
);

// Map the table's column id (e.g. `value`) to the backend sort param the
// FilterQuery whitelists (e.g. `value_cents`). Empty when no sort is active.
// Shared by the list fetch and the Excel export (#722), so both use the same order.
const listSortParams = computed(() => {
  const activeSort = ordemPermitida(listSort.value);
  const sortParam = activeSort?.id
    ? COLUMN_TO_SORT_PARAM[activeSort.id]
    : undefined;
  if (!sortParam) return {};
  return { sort: sortParam, direction: activeSort.desc ? 'desc' : 'asc' };
});

const loadCurrentList = async ({ append = false } = {}) => {
  if (!currentPipelineId.value) return;
  loadError.value = '';
  if (!append) listPage.value = 1;
  try {
    await store.dispatch('crmKanban/fetchCardsList', {
      pipelineId: currentPipelineId.value,
      page: listPage.value,
      perPage: listPageSize,
      append,
      ...listSortParams.value,
    });
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.LOAD');
    useAlert(t('CRM_KANBAN.ERRORS.LOAD'));
  }
};

// "Load more" in list view: advance the page and append the next slice.
const loadMoreList = async () => {
  if (!hasMoreCards.value || uiFlags.value.isFetchingCardsList) return;
  listPage.value += 1;
  await loadCurrentList({ append: true });
};

const loadCurrentCalendar = async () => {
  // #1894: a caminho do Meu dia, o calendário antigo não busca nada (a resposta dele cairia no Meu dia).
  if (meuDiaNoLugarDoCalendario(viewMode.value)) return;
  if (!calendarioOuro.value && !currentPipelineId.value) return;
  loadError.value = '';
  // The calendar emits range-change with the visible window; use that when
  // present, else the legacy ±30/90d default for the very first fetch.
  const storedRange = store.getters['crmKanban/getCalendarRange'];
  const range =
    storedRange?.from && storedRange?.to
      ? { from: storedRange.from, to: storedRange.to }
      : calendarRange();
  try {
    // Owner scope (mine/all) is applied client-side by the orchestrator via
    // filterByOwner, so the fetch always pulls the full pipeline window.
    // Completed/canceled follow-ups are hidden unless the "Histórico" toggle is on.
    await store.dispatch('crmKanban/fetchCalendarEvents', {
      pipeline_id: calendarioOuro.value
        ? funilDoCalendario.value || undefined
        : currentPipelineId.value,
      include_completed: store.getters['crmKanban/getCalendarIncludeCompleted'],
      semFiltrosDoQuadro: calendarioOuro.value,
      ...range,
    });
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.LOAD');
    useAlert(t('CRM_KANBAN.ERRORS.LOAD'));
  }
};

const loadActiveView = async (includeCounts = false) => {
  // #2283: a Lista nova busca sozinha (funil, filtros, aba) e não pula linha no tempo real.
  if (viewMode.value === 'list')
    return listaAcao.value ? null : loadCurrentList();
  if (viewMode.value === 'calendar') return loadCurrentCalendar();
  return loadCurrentBoard(includeCounts);
};

const moveCardFromDetails = async stageId => {
  if (
    !canMoveCards.value ||
    uiFlags.value.isMovingCard ||
    !selectedCard.value?.id ||
    !stageId
  )
    return;
  const cardId = selectedCard.value.id;
  const accountId = String(route.params.accountId);
  try {
    await store.dispatch('crmKanban/moveCard', { cardId, stageId });
    if (accountId !== String(route.params.accountId)) return;
    if (selectedCard.value?.id === cardId) {
      selectedCard.value = { ...selectedCard.value, stage_id: stageId };
    }
    if (viewMode.value !== 'kanban' || filters.value.stageIds.length) {
      await loadActiveView(true);
    }
    useAlert(t('CRM_KANBAN.ALERTS.CARD_MOVED'));
  } catch (error) {
    if (accountId === String(route.params.accountId))
      avisarErro(error, 'CRM_KANBAN.ALERTS.CARD_MOVE_ERROR');
  }
};

const handleRealtimeConnected = async () => {
  await loadCurrentBoard(true);
};

// Server-only filters (responsible=bot/none, AI-pending) cannot be evaluated from a
// single realtime card payload, so the store asks us to refetch active view instead.
// Debounce so a burst of realtime events triggers a single reload.
let refetchTimer = null;
const handleServerFilterRefetch = () => {
  if (refetchTimer) clearTimeout(refetchTimer);
  refetchTimer = setTimeout(() => loadActiveView(true), 400);
};

// #1883: o responsável que veio pelo link só vale se for alguém da equipe que a pessoa enxerga. Confere assim que
// a equipe carrega, antes da primeira busca, para não ir ao servidor com um dono que vai cair.
const donoDoLinkPorConferir = ref(false);
const conferirDonoDoLink = async () => {
  if (!donoDoLinkPorConferir.value) return;
  donoDoLinkPorConferir.value = false;
  // Sem a equipe carregada não dá para julgar: fica o dono do link (o servidor só devolve o que a pessoa vê).
  if (!agents.value.length) return;
  const { ownerId } = filters.value;
  const conhecido =
    String(ownerId) === String(currentUser.value?.id) ||
    agents.value.some(agent => String(agent.id) === String(ownerId));
  if (conhecido) return;
  filters.value = { ...filters.value, ownerId: '' };
  await store.dispatch('crmKanban/setFilters', filters.value);
};

const refreshData = async () => {
  loadError.value = '';
  try {
    await Promise.allSettled([
      store.dispatch('inboxes/get'),
      store.dispatch('agents/get'),
      store.dispatch('teams/get'),
      // Labels hidratam as opções do filtro de etiquetas e as cores dos cards
      // (deep-link direto no CRM não passa pela sidebar, que normalmente carrega).
      store.dispatch('labels/get'),
      loadCampaignOptions(),
    ]);
    await conferirDonoDoLink();
    const fetchedPipelines = await store.dispatch('crmKanban/fetchPipelines');
    // #1883: o funil do Meu dia que veio pelo link só vale se a pessoa enxerga esse funil.
    const funilVisivel = fetchedPipelines.find(
      pipeline => String(pipeline.id) === String(funilDoCalendario.value)
    );
    funilDoCalendario.value = funilVisivel?.id ?? null;
    if (fetchedPipelines.length > 0) {
      const currentStillExists = fetchedPipelines.some(
        pipeline => String(pipeline.id) === String(currentPipelineId.value)
      );
      // `?pipeline_id=` abre o quadro num funil: a volta da passagem (#1385) cai no funil de onde a pessoa saiu.
      // Passa pelo watch de currentPipelineId, que alinha o filtro de resultado ao funil.
      const requested = fetchedPipelines.find(
        pipeline => String(pipeline.id) === String(route.query.pipeline_id)
      );
      let nextPipelineId = currentStillExists
        ? currentPipelineId.value
        : fetchedPipelines[0].id;
      if (requested) nextPipelineId = requested.id;
      if (String(currentPipelineId.value) === String(nextPipelineId)) {
        await loadActiveView(true);
        return;
      }
      currentPipelineId.value = nextPipelineId;
    }
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.LOAD');
    useAlert(t('CRM_KANBAN.ERRORS.LOAD'));
  }
};

const applyFilters = async () => {
  loadError.value = '';
  try {
    await store.dispatch('crmKanban/setFilters', filters.value);
    await loadActiveView(true);
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.FILTER');
    useAlert(t('CRM_KANBAN.ERRORS.FILTER'));
  }
};

const clearFilters = async () => {
  filters.value = defaultFilters();
  await applyFilters();
};

// List status tabs (open/won/lost). Writes the same `filters.result` the Filtros
// popover uses, so the tabs and the popover stay in sync.
const selectResult = async value => {
  filters.value.result = value;
  await applyFilters();
};

const applyFiltersFromDrawer = async nextFilters => {
  filters.value = nextFilters;
  showFiltersDrawer.value = false;
  await applyFilters();
};

const clearFiltersFromDrawer = async () => {
  showFiltersDrawer.value = false;
  await clearFilters();
};

const closeConfiguration = () => {
  configurationPopover.value?.hide();
};

const runConfigurationAction = action => {
  closeConfiguration();
  action();
};

const removeFilterChip = async key => {
  const defaults = defaultFilters();
  if (key === 'value') {
    filters.value.valueMin = defaults.valueMin;
    filters.value.valueMax = defaults.valueMax;
  } else if (key === 'score') {
    filters.value.scoreMin = defaults.scoreMin;
    filters.value.scoreMax = defaults.scoreMax;
  } else {
    filters.value[key] = defaults[key];
  }
  await applyFilters();
};

const loadPipelineInboxes = async pipelineId => {
  if (!canManagePipelines.value || !pipelineId) {
    pipelineInboxes.value = [];
    return [];
  }

  try {
    const links = await store.dispatch(
      'crmKanban/fetchPipelineInboxes',
      pipelineId
    );
    pipelineInboxes.value = links;
    return links;
  } catch {
    pipelineInboxes.value = [];
    useAlert(t('CRM_KANBAN.ALERTS.PIPELINE_INBOX_LOAD_ERROR'));
    return [];
  }
};

const loadPipelineDrawerStages = async pipelineId => {
  if (!pipelineId) {
    pipelineDrawerStages.value = [];
    return [];
  }

  try {
    const stagesData = await store.dispatch(
      'crmKanban/fetchPipelineStages',
      pipelineId
    );
    pipelineDrawerStages.value = stagesData;
    return stagesData;
  } catch {
    pipelineDrawerStages.value = [];
    return [];
  }
};

const openCreatePipelineDrawer = () => {
  pipelineDrawerMode.value = 'create';
  pipelineInboxes.value = [];
  pipelineDrawerStages.value = [];
  showPipelineDrawer.value = true;
};

const openEditPipelineDrawer = async () => {
  if (!selectedPipeline.value) return;
  pipelineDrawerMode.value = 'edit';
  pipelineInboxes.value = [];
  pipelineDrawerStages.value = [];
  // Stages must resolve BEFORE the drawer opens: CrmPipelineDrawer's form-reset watcher
  // fires immediately on props.show and seeds form.stages from props.stages at that instant
  // — it never backfills stages that arrive later (its ongoing watcher only prunes
  // deletions). Opening the drawer first would initialize the form with an empty stage
  // list. Inboxes aren't read by that same immediate reset, so they can still load after.
  await loadPipelineDrawerStages(selectedPipeline.value.id);
  showPipelineDrawer.value = true;
  loadPipelineInboxes(selectedPipeline.value.id);
};

const closePipelineDrawer = () => {
  showPipelineDrawer.value = false;
};

// A passagem (#1385) volta para cá no mesmo funil: o endereço do quadro guarda o funil antes de sair (vale para o
// voltar do navegador) e `from: 'crm'` diz à passagem que a seta e o X voltam ao Kanban, não à lista de funis.
const openHandoffSettings = async () => {
  if (!selectedPipeline.value) return;
  const pipelineId = selectedPipeline.value.id;
  await router.replace({
    query: { ...route.query, pipeline_id: String(pipelineId) },
  });
  router.push({
    name: 'crm_handoff_settings_edit',
    params: { pipelineId },
    query: { from: 'crm' },
  });
};

// Depois de abrir o funil pedido, tira o `pipeline_id` do endereço: trocar de funil no quadro não o atualiza.
// #1883: os filtros do link também saem; dali em diante quem manda é o controle de filtro da tela.
const ROTAS_COM_LINK = {
  crm_kanban_index: ['pipeline_id', ...CHAVES_DO_LINK],
  crm_calendar_index: CHAVES_DO_MEU_DIA,
};
const clearPipelineFromQuery = () => {
  const chaves = ROTAS_COM_LINK[route.name];
  if (!chaves) return;
  const query = semChaves(route.query, chaves);
  if (Object.keys(query).length === Object.keys(route.query).length) return;
  router.replace({ query });
};

const askConfirmation = async config => {
  confirmConfig.value = config;
  return confirmModal.value?.showConfirmation();
};

const savePipeline = async payload => {
  try {
    const pipeline = await store.dispatch(
      'crmKanban/savePipelineWithStages',
      payload
    );
    currentPipelineId.value = pipeline.id;
    closePipelineDrawer();
    useAlert(
      pipelineDrawerMode.value === 'edit'
        ? t('CRM_KANBAN.ALERTS.PIPELINE_UPDATED')
        : t('CRM_KANBAN.ALERTS.PIPELINE_CREATED')
    );
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.PIPELINE_SAVE_ERROR'));
  }
};

const loadPipelineStagesForSettings = async pipelineId => {
  if (!pipelineId || inboxSettingStagesByPipeline.value[String(pipelineId)]) {
    return inboxSettingStagesByPipeline.value[String(pipelineId)] || [];
  }

  const loadedStages = await store.dispatch(
    'crmKanban/fetchPipelineStages',
    pipelineId
  );
  inboxSettingStagesByPipeline.value = {
    ...inboxSettingStagesByPipeline.value,
    [String(pipelineId)]: loadedStages,
  };
  return loadedStages;
};

const loadInboxSettings = async () => {
  try {
    const settings = await store.dispatch('crmKanban/fetchInboxSettings');
    inboxSettings.value = settings;
    await Promise.all(
      settings
        .map(setting => setting.default_pipeline_id)
        .filter(Boolean)
        .map(loadPipelineStagesForSettings)
    );
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.INBOX_SETTINGS_LOAD_ERROR'));
  }
};

// Lembretes novos (#1460/#1461/#1462): com a flag, "Novo lembrete" do
// calendário abre a gaveta nova; sem ela, a janela de sempre.
const mensagemMarcadaNova = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_MENSAGEM_MARCADA
    ] === true
);
const lembretesV2 = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_LEMBRETES_V2
    ] === true
);
// Caixas no CRM (#1149): com a flag da conta, leva à tela nova; sem ela, a
// gaveta antiga, como sempre.
const isCaixasNoCrm = computed(
  () =>
    getAccount.value(currentAccountId.value)?.features?.[
      FEATURE_FLAGS.CRM_CONFIGURAR_CAIXAS
    ] === true
);
// A tela nova decide quem vê o quê: só administrador ou crm_admin (a gaveta
// antiga continua com quem gerencia funis).
const canOpenInboxSettings = computed(() =>
  isCaixasNoCrm.value ? canAdminCrm.value : canManagePipelines.value
);
// Há o que configurar neste funil: o botão do topo e, na Lista nova abaixo de
// 1024 px, o item "Configurar" do "Mais" (#2283).
const podeConfigurar = computed(
  () =>
    canManagePipelines.value ||
    canOpenInboxSettings.value ||
    (!isCalendarOnly.value && canManageAi.value) ||
    (!isCalendarOnly.value && arquivadosLigado.value)
);
// O "Mais" fecha no mesmo clique; o popover abre depois, para o clique não o
// fechar de volta.
const abrirConfiguracao = () =>
  setTimeout(() => configurationPopover.value?.show(), 0);

const openInboxSettingsDrawer = async () => {
  if (isCaixasNoCrm.value) {
    router.push({
      name: 'crm_caixas',
      params: { accountId: currentAccountId.value },
    });
    return;
  }
  showInboxSettingsDrawer.value = true;
  await loadInboxSettings();
};

const closeInboxSettingsDrawer = () => {
  showInboxSettingsDrawer.value = false;
};

// Botão Agendamento do Calendário (#1212): com o agendamento novo ligado na
// conta, leva à página nova (CRM › Agendamento) para quem pode vê-la; desligado,
// abre a gaveta antiga para quem gerencia funis, como sempre.
const isBookingV2 = computed(() =>
  isBookingV2Available(getAccount.value(currentAccountId.value))
);
const canOpenBooking = computed(() => {
  if (!isBookingV2.value) return canManagePipelines.value;
  return canSeeBookingSettings({
    isAdministrator: currentRole.value === 'administrator',
    permissions: getUserPermissions(currentUser.value, currentAccountId.value),
  });
});

const openBooking = () => {
  if (isBookingV2.value) {
    router.push({
      name: 'settings_booking',
      params: { accountId: currentAccountId.value },
    });
    return;
  }
  showBookingProfilesDrawer.value = true;
};

const closeBookingProfilesDrawer = () => {
  showBookingProfilesDrawer.value = false;
};

const saveInboxSetting = async payload => {
  try {
    if (payload.default_pipeline_id) {
      await loadPipelineStagesForSettings(payload.default_pipeline_id);
    }
    const setting = await store.dispatch(
      'crmKanban/updateInboxSetting',
      payload
    );
    const otherSettings = inboxSettings.value.filter(
      item => Number(item.inbox_id) !== Number(setting.inbox_id)
    );
    inboxSettings.value = [...otherSettings, setting];
    inboxSaveResult.value = {
      inboxId: payload.inboxId,
      ok: true,
      at: Date.now(),
    };
    useAlert(t('CRM_KANBAN.ALERTS.INBOX_SETTINGS_SAVED'));
  } catch {
    inboxSaveResult.value = {
      inboxId: payload.inboxId,
      ok: false,
      at: Date.now(),
    };
    useAlert(t('CRM_KANBAN.ALERTS.INBOX_SETTINGS_SAVE_ERROR'));
  }
};

const arquivarFunilDialogo = ref(null);
const archivePipeline = async () => {
  if (!selectedPipeline.value?.id) return;
  if (arquivadosLigado.value) {
    arquivarFunilDialogo.value?.abrir({
      alvo: selectedPipeline.value,
      ativos: pipelines.value,
    });
    return;
  }
  const confirmed = await askConfirmation({
    title: t('CRM_KANBAN.CONFIRM.ARCHIVE_PIPELINE_TITLE'),
    description: t('CRM_KANBAN.CONFIRM.ARCHIVE_PIPELINE_DESCRIPTION'),
    confirmLabel: t('CRM_KANBAN.CONFIRM.ARCHIVE_PIPELINE_CONFIRM'),
  });
  if (!confirmed) return;

  try {
    const nextPipeline = await store.dispatch(
      'crmKanban/archivePipeline',
      selectedPipeline.value.id
    );
    currentPipelineId.value = nextPipeline?.id || '';
    closePipelineDrawer();
    useAlert(t('CRM_KANBAN.ALERTS.PIPELINE_ARCHIVED'));
  } catch (error) {
    // O último funil ativo e o único principal não se arquivam: a API diz por quê, na língua de quem usa.
    useAlert(
      error?.response?.data?.message ||
        t('CRM_KANBAN.ALERTS.PIPELINE_ARCHIVE_ERROR')
    );
  }
};

const deleteStageOptions = computed(() =>
  pipelineDrawerStages.value.filter(
    candidate => Number(candidate.id) !== Number(stageToDelete.value?.id)
  )
);
const deleteStageChoices = computed(() =>
  deleteStageOptions.value.map(option => ({
    value: option.id,
    label: option.name,
  }))
);
const deleteStageHasCards = computed(() =>
  Boolean(stageToDelete.value?.total_cards_count > 0)
);

// Backend error codes from stages_controller#destroy — mapped to a specific message
// instead of one generic toast that used to hide whether it was "has cards" (now paired
// with a target picker so this shouldn't fire from a stale board) or "last stage".
const STAGE_DELETE_ERROR_KEYS = {
  'crm.stage_has_cards': 'CRM_KANBAN.ALERTS.STAGE_DELETE_ERROR_HAS_CARDS',
  'crm.stage_is_last': 'CRM_KANBAN.ALERTS.STAGE_DELETE_ERROR_LAST_STAGE',
  'crm.stage_in_use': 'CRM_KANBAN.ALERTS.STAGE_DELETE_ERROR_IN_USE',
};

const deleteStageErrorMessage = error => {
  const code = error?.response?.data?.error;
  return t(
    STAGE_DELETE_ERROR_KEYS[code] || 'CRM_KANBAN.ALERTS.STAGE_DELETE_ERROR'
  );
};

const deleteStage = async stage => {
  stageToDelete.value = stage;
  deleteStageTargetId.value = '';

  const confirmed = await askConfirmation({
    title: t('CRM_KANBAN.CONFIRM.DELETE_STAGE_TITLE'),
    description: stage.total_cards_count
      ? t('CRM_KANBAN.CONFIRM.DELETE_STAGE_DESCRIPTION_WITH_CARDS', {
          stage: stage.name,
          count: stage.total_cards_count,
        })
      : t('CRM_KANBAN.CONFIRM.DELETE_STAGE_DESCRIPTION', {
          stage: stage.name,
        }),
    confirmLabel: t('CRM_KANBAN.CONFIRM.DELETE_STAGE_CONFIRM'),
  });
  if (!confirmed) {
    stageToDelete.value = null;
    return;
  }

  try {
    await store.dispatch('crmKanban/deleteStage', {
      stageId: stage.id,
      targetStageId: deleteStageTargetId.value || null,
    });
    useAlert(t('CRM_KANBAN.ALERTS.STAGE_DELETED'));
    await Promise.all([
      loadCurrentBoard(true),
      // Re-sync the drawer's own stage list so a second delete in the same drawer
      // session sees accurate total_cards_count (incl. cards just moved here) and
      // no longer offers the just-deleted stage as a target.
      loadPipelineDrawerStages(selectedPipeline.value?.id),
    ]);
  } catch (error) {
    useAlert(deleteStageErrorMessage(error));
  } finally {
    stageToDelete.value = null;
  }
};

const clearContactCreationIntent = () => {
  if (route.query.new_contact_id === undefined) return;
  const { new_contact_id: _intent, ...query } = route.query;
  router.replace({ query });
};
const openCreateDrawer = () => {
  creationContact.value = null;
  clearContactCreationIntent();
  selectedCard.value = null;
  drawerInitialTab.value = null;
  drawerMode.value = 'create';
  showDrawer.value = true;
};

const openCardDrawer = async (card, { initialTab = null } = {}) => {
  cardDrawerStages.value = [];
  drawerInitialTab.value = initialTab;
  selectedCard.value = card;
  drawerMode.value = 'edit';
  showDrawer.value = true;
  try {
    const [detailedCard] = await Promise.all([
      store.dispatch('crmKanban/fetchCard', card.id),
      store.dispatch('crmKanban/fetchFollowUps', { card_id: card.id }),
    ]);
    if (showDrawer.value && selectedCard.value?.id === card.id) {
      selectedCard.value = detailedCard;
      const completeStages = await store.dispatch(
        'crmKanban/fetchPipelineStages',
        detailedCard.pipeline_id
      );
      if (showDrawer.value && selectedCard.value?.id === card.id) {
        cardDrawerStages.value = completeStages;
      }
    }
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.CARD_LOAD_ERROR'));
  }
};

// Bubble shortcut on the board card: jump straight into the linked inbox
// conversation by its per-account display_id (the same route the card drawer's
// "Abrir a conversa" uses). Guarded — the card only emits this when a
// conversation exists, but stay defensive against a stale/empty payload.
const openCardConversation = card => {
  const displayId = card?.conversation?.display_id;
  if (!displayId) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: displayId,
    },
  });
};

const openRouteCardIfNeeded = async () => {
  const cardId = route.query.card_id;
  if (!cardId || openedRouteCardId.value === String(cardId)) return;

  const originAccount = route.params.accountId;
  openedRouteCardId.value = String(cardId);
  await openCardDrawer({ id: Number(cardId) });
  const card = selectedCard.value;
  if (originAccount !== route.params.accountId || card?.id !== Number(cardId))
    return;
  // A profile lists opportunities across funnels. Align the board and its stage
  // options only after the card has been authorized and loaded by the real API.
  // Never inject an unavailable/archived pipeline into the native selector.
  if (pipelines.value.some(pipeline => pipeline.id === card.pipeline_id)) {
    currentPipelineId.value = card.pipeline_id;
  }
};

const closeDrawer = () => {
  showDrawer.value = false;
  selectedCard.value = null;
};

// Re-fetch the open card after a child action mutated it server-side (e.g. the
// AI auto-follow-up RESET re-arms the cadence). Mirrors the closeCardDeal
// refresh pattern, reloads the follow-ups list shown in the drawer, and keeps
// the active board/list/calendar in sync with contact and company edits.
const refreshSelectedCard = async () => {
  const cardId = selectedCard.value?.id;
  if (!cardId) return;
  try {
    const [detailedCard] = await Promise.all([
      store.dispatch('crmKanban/fetchCard', cardId),
      store.dispatch('crmKanban/fetchFollowUps', { card_id: cardId }),
    ]);
    if (detailedCard && selectedCard.value?.id === cardId) {
      selectedCard.value = detailedCard;
      // Contact/company edits can affect every opportunity linked to the same
      // contact and the active company filter. Refresh the current view so the
      // board, list, and calendar do not keep stale identity data.
      await loadActiveView(true);
    }
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.CARD_LOAD_ERROR'));
  }
};

const saveCard = async (payload, failed, saved) => {
  const originAccount = String(route.params.accountId);
  try {
    if (drawerMode.value === 'edit') {
      await store.dispatch('crmKanban/updateCard', {
        id: selectedCard.value.id,
        ...payload,
      });
      useAlert(t('CRM_KANBAN.ALERTS.CARD_UPDATED'));
      // #1423 — o card continua aberto e volta ao resumo atualizado.
      saved?.();
      await refreshSelectedCard();
      return;
    }
    const created = await store.dispatch('crmKanban/createCard', payload);
    if (originAccount !== String(route.params.accountId)) return;
    useAlert(t('CRM_KANBAN.ALERTS.CARD_CREATED'));
    const changedPipeline =
      String(currentPipelineId.value) !== String(created.pipeline_id);
    if (changedPipeline) currentPipelineId.value = created.pipeline_id;
    await openCardDrawer(created, {
      initialTab: created.contact_id ? 'contact' : 'summary',
    });
    if (!changedPipeline) await loadActiveView(true);
  } catch (error) {
    if (originAccount !== String(route.params.accountId)) return;
    failed?.(error);
    avisarErro(error, 'CRM_KANBAN.ALERTS.CARD_SAVE_ERROR');
  }
};

const cardDrawerRef = ref(null);
const openOpportunityForContact = contact => {
  const open = () => {
    openCreateDrawer();
    creationContact.value = contact;
  };
  if (showDrawer.value)
    cardDrawerRef.value?.guardNavigation(open, { leaving: true });
  else open();
};

const openCardFromBoard = card => {
  const sameCard =
    drawerMode.value === 'edit' && selectedCard.value?.id === card?.id;
  if (showDrawer.value && !sameCard) {
    // Switching cards leaves the open one: its unsaved drafts must be confirmed.
    cardDrawerRef.value?.guardNavigation(() => openCardDrawer(card), {
      leaving: true,
    });
    return;
  }
  openCardDrawer(card);
};

// Follow-up CRUD from the card drawer mutates the calendar's data source, so
// keep the calendar in sync when it's the active view (it reads a separate
// calendarEvents array, not the drawer's follow-up list).
const syncCalendarIfActive = async () => {
  if (viewMode.value === 'calendar') await loadCurrentCalendar();
};

// A mensagem crua do Rails (em inglês) nunca deve aparecer; quando o 422 é essa validação
// específica, o card já sabe explicar — e a janela pode ter mudado entre o preenchimento e o
// envio, então o aviso do drawer (verde/vermelho) precisa recarregar antes do operador tentar de novo.
// Código estável (não o texto da mensagem, que é do Rails e pode mudar) — ver follow_ups_controller.rb.
const isTemplateFallbackError = error =>
  error?.response?.data?.code === 'template_fallback_required';

const createFollowUp = async payload => {
  try {
    await store.dispatch('crmKanban/createFollowUp', payload);
    await store.dispatch('crmKanban/fetchFollowUps', {
      card_id: selectedCard.value.id,
    });
    cardDrawerRef.value?.resetFollowUpForm?.();
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_CREATED'));
    await syncCalendarIfActive();
  } catch (error) {
    if (isTemplateFallbackError(error)) {
      await cardDrawerRef.value?.refreshMessagingWindow?.();
      useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_TEMPLATE_REQUIRED'));
      return;
    }
    // #1590: com a flag crm_mensagem_marcada, mensagem automática com horário que já
    // passou é recusada na criação; o retorno de sempre (Twilio, caixa API) ainda passa aqui.
    if (error?.response?.data?.code === 'due_at_in_the_past') {
      useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_DUE_AT_PAST'));
      return;
    }
    const apiMessage = error?.response?.data?.message;
    useAlert(apiMessage || t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'));
  }
};

const completeFollowUp = async followUp => {
  try {
    await store.dispatch('crmKanban/completeFollowUp', followUp.id);
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_COMPLETED'));
    await syncCalendarIfActive();
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'));
  }
};

const cancelFollowUp = async followUp => {
  try {
    await store.dispatch('crmKanban/cancelFollowUp', followUp.id);
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_CANCELED'));
    await syncCalendarIfActive();
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'));
  }
};

// `detalhes.retornos` (janela nova, #2095): quantos retornos o arquivar para, para o Desfazer avisar.
const archiveCard = async (detalhes = {}) => {
  if (!selectedCard.value?.id) return;
  const card = selectedCard.value;
  arquivados.erroArquivarCard.value = '';
  try {
    await store.dispatch('crmKanban/archiveCard', card.id);
    if (arquivadosLigado.value)
      arquivados.avisarArquivado(card, detalhes?.retornos || 0);
    else useAlert(t('CRM_KANBAN.ALERTS.CARD_ARCHIVED'));
    closeDrawer();
    if (arquivadosLigado.value) arquivados.contar();
  } catch (error) {
    // #2095: com a flag, o erro fica na janela de arquivar, com o motivo; nada mudou.
    if (arquivadosLigado.value) arquivados.erroAoArquivar(error);
    else avisarErro(error, 'CRM_KANBAN.ALERTS.CARD_ARCHIVE_ERROR');
  }
};

const closeCardDeal = async payload => {
  const cardId = selectedCard.value?.id;
  if (!cardId) return;
  try {
    await store.dispatch('crmKanban/closeCard', { id: cardId, ...payload });
    // Refresh drawer detail so the timeline shows the won/lost/reopen activity.
    const detailedCard = await store.dispatch('crmKanban/fetchCard', cardId);
    if (selectedCard.value?.id === cardId) {
      selectedCard.value = detailedCard;
    }
    useAlert(avisoDoDesfecho(t, detailedCard?.status, selectedPipeline.value));
  } catch (error) {
    avisarErro(
      error,
      funilDeVenda.value
        ? 'CRM_KANBAN.ALERTS.CARD_CLOSE_ERROR'
        : 'CRM_KANBAN.ALERTS.CARD_CLOSE_ERROR_ATENDER'
    );
  }
};

const onDragStart = event => {
  suppressClickAfterDrag = true;
  dragSnapshot.value = JSON.parse(JSON.stringify(stages.value));
  startAutoScroll(event);
};

const onDragChange = async (stage, event) => {
  if (!event.added) return;
  const movedCard = event.added.element;
  try {
    await store.dispatch('crmKanban/moveCard', {
      cardId: movedCard.id,
      stageId: stage.id,
    });
    useAlert(t('CRM_KANBAN.ALERTS.CARD_MOVED'));
  } catch (error) {
    store.commit('crmKanban/RESTORE_CRM_KANBAN_STAGES', dragSnapshot.value);
    avisarErro(error, 'CRM_KANBAN.ALERTS.CARD_MOVE_ERROR');
  } finally {
    dragSnapshot.value = null;
  }
};

const loadMore = async stage => {
  if (!stage.has_more || !stage.next_cursor) return;
  loadError.value = '';
  try {
    await store.dispatch('crmKanban/fetchBoard', {
      pipelineId: currentPipelineId.value,
      cursorByStage: { [stage.id]: stage.next_cursor },
      stageIds: [stage.id],
      append: true,
    });
  } catch {
    loadError.value = t('CRM_KANBAN.ERRORS.PAGINATION', {
      stage: stage.name,
    });
    useAlert(loadError.value);
  }
};

/* -------------------------------------------------------------------------- */
/* List (v2) — TanStack table wiring                                          */
/* -------------------------------------------------------------------------- */
const collapsedGroups = ref([]);

// TanStack column defs, rebuilt when stages/agents change so editors get fresh
// option lists. Labels resolve through CRM_KANBAN.LIST.COLUMNS.* i18n.
const cardColumnDefs = computed(() =>
  buildCrmCardColumns({
    t,
    stages: stages.value,
    agents: agents.value,
    // Keep the settings menu in sync with the table: the Meta column must be
    // hideable/reorderable whenever it is rendered.
    includeMeta: isMetaSyncActive.value,
    includeValue: quadroComValor.value,
  })
);

// Merge persisted listPrefs with the column defaults so the table always has a
// complete state object (visibility/order/sizing/density).
const listColumnState = computed(() => {
  const prefs = listPrefs.value || {};
  return {
    columnVisibility: {
      ...DEFAULT_COLUMN_VISIBILITY,
      ...(prefs.columnVisibility || {}),
    },
    columnOrder:
      prefs.columnOrder && prefs.columnOrder.length
        ? prefs.columnOrder
        : DEFAULT_COLUMN_ORDER,
    columnSizing: prefs.columnSizing || {},
    density: prefs.density || 'comfortable',
  };
});

// Column descriptors for the settings menu: { id, label, visible, hideable }.
const columnSettingsItems = computed(() => {
  const state = listColumnState.value;
  const byId = new Map(cardColumnDefs.value.map(col => [col.id, col]));
  return state.columnOrder
    .filter(id => id !== 'select' && byId.has(id))
    .map(id => {
      const col = byId.get(id);
      return {
        id,
        label: col.header || id,
        visible: state.columnVisibility[id] !== false,
        hideable: col.enableHiding !== false,
      };
    });
});

const hasActiveFilters = computed(() => activeFilterCount.value > 0);

const persistListPrefs = patch => {
  store.dispatch('crmKanban/setListPrefs', {
    pipelineId: currentPipelineId.value,
    ...listColumnState.value,
    ...patch,
  });
};

const onListSortChange = async payload => {
  store.dispatch('crmKanban/setListSort', payload || null);
  await loadCurrentList();
};

const onListGroupChange = ({ groupBy, collapsed }) => {
  if (groupBy !== undefined)
    store.dispatch('crmKanban/setListGroupBy', groupBy);
  if (collapsed !== undefined) collapsedGroups.value = collapsed;
};

const onListColumnChange = ({ columnSizing }) => {
  if (columnSizing) persistListPrefs({ columnSizing });
};

const onListSelectChange = ids => {
  store.dispatch('crmKanban/setListSelection', ids);
};

// CrmTableCellEditable reports intent {cardId|field, value}; route through the
// store wrapper which handles stage→move, won/lost→close, value-source lock.
const onListEditSave = async ({ cardId, field, value }) => {
  try {
    if (field === 'next_follow_up_at') {
      await store.dispatch('crmKanban/updateCardFields', {
        id: cardId,
        expected_close_at: undefined,
        next_follow_up_at: value,
      });
    } else {
      await store.dispatch('crmKanban/updateCardFields', {
        id: cardId,
        [field === 'value' ? 'value_cents' : field]: value,
      });
    }
    useAlert(t('CRM_KANBAN.EDIT.SAVED'));
  } catch (error) {
    avisarErro(error, 'CRM_KANBAN.EDIT.ERROR');
  }
};

// Column-settings menu emits the full next state, or { reset: true }.
const onColumnSettingsUpdate = update => {
  if (update.reset) {
    persistListPrefs({
      columnVisibility: { ...DEFAULT_COLUMN_VISIBILITY },
      columnOrder: [...DEFAULT_COLUMN_ORDER],
      density: 'comfortable',
    });
    return;
  }
  const patch = {};
  if (update.columns) {
    patch.columnOrder = ['select', ...update.columns.map(c => c.id)];
    patch.columnVisibility = update.columns.reduce(
      (acc, c) => ({ ...acc, [c.id]: c.visible }),
      { select: true }
    );
  }
  if (update.density) patch.density = update.density;
  persistListPrefs(patch);
};

/* -------------------------------------------------------------------------- */
/* Saved views (v2) — list-view-only                                          */
/* -------------------------------------------------------------------------- */
// Current list state serialized as a saved-view config. Shape matches the
// jsonb contract: { columns, filters, sort, group_by, density }.
const currentSavedViewConfig = computed(() => ({
  columns: {
    columnVisibility: listColumnState.value.columnVisibility,
    columnOrder: listColumnState.value.columnOrder,
    columnSizing: listColumnState.value.columnSizing,
  },
  filters: { ...filters.value },
  sort: listSort.value || null,
  group_by: listGroupBy.value || 'none',
  density: listColumnState.value.density,
}));

const fetchSavedViews = () => {
  if (!currentPipelineId.value) return;
  store.dispatch('crmKanban/fetchSavedViews', currentPipelineId.value);
};

// Apply a chosen view: restore the page's column/filter/sort/group state from
// its config, then reload the list with the new state.
const onSavedViewApply = async ({ view }) => {
  const config = view?.config || {};
  if (config.columns) {
    persistListPrefs({
      columnVisibility:
        config.columns.columnVisibility || DEFAULT_COLUMN_VISIBILITY,
      columnOrder: config.columns.columnOrder || DEFAULT_COLUMN_ORDER,
      columnSizing: config.columns.columnSizing || {},
      ...(config.density ? { density: config.density } : {}),
    });
  }
  const valorIgnorado =
    !canSeeSalesValues.value &&
    (temFiltroDeValor(config.filters) || config.sort?.id === 'value');
  store.dispatch('crmKanban/setListSort', ordemPermitida(config.sort || null));
  store.dispatch('crmKanban/setListGroupBy', config.group_by || 'none');
  if (config.filters) {
    filters.value = semFiltroDeValor({
      ...defaultFilters(),
      ...config.filters,
    });
    await store.dispatch('crmKanban/setFilters', filters.value);
  }
  // Lista nova (#2379): ela recarrega sozinha com os filtros novos; a ordem e
  // o que aparece ela mesma aplica.
  if (!listaAcao.value) await loadCurrentList();
  if (valorIgnorado) useAlert(t('CRM_KANBAN.LIST.SAVED_VIEWS.VALUE_IGNORED'));
};

// Lista nova (#2379): "Lista antiga: só os mais quentes" → "Mostrar todos" tira
// a nota da IA da lista guardada (o filtro saiu da gaveta).
const tirarNotaDaListaAcao = async () => {
  filters.value = { ...filters.value, scoreMin: '', scoreMax: '' };
  await store.dispatch('crmKanban/setFilters', filters.value);
};

const onSavedViewCreate = async payload => {
  try {
    await store.dispatch('crmKanban/saveSavedView', payload);
    useAlert(t('CRM_KANBAN.EDIT.SAVED'));
  } catch {
    useAlert(t('CRM_KANBAN.EDIT.ERROR'));
  }
};

const onSavedViewUpdate = async payload => {
  try {
    await store.dispatch('crmKanban/saveSavedView', payload);
    useAlert(t('CRM_KANBAN.EDIT.SAVED'));
  } catch {
    useAlert(t('CRM_KANBAN.EDIT.ERROR'));
  }
};

const onSavedViewDelete = async ({ id }) => {
  try {
    await store.dispatch('crmKanban/deleteSavedView', id);
    useAlert(t('CRM_KANBAN.EDIT.SAVED'));
  } catch {
    useAlert(t('CRM_KANBAN.EDIT.ERROR'));
  }
};

const runBulkAction = async (action, payload = {}) => {
  try {
    await store.dispatch('crmKanban/bulkAction', {
      ids: listSelection.value,
      action,
      payload,
    });
    useAlert(t('CRM_KANBAN.BULK.DONE', { count: listSelection.value.length }));
    if (listaAcao.value) {
      store.dispatch('crmKanban/setListSelection', []);
      listaAcaoRef.value?.recarregar();
    }
  } catch {
    useAlert(t('CRM_KANBAN.EDIT.ERROR'));
  }
};

const onBulkMove = ({ stageId }) =>
  runBulkAction('move', { stage_id: stageId });
const onBulkAssign = ({ ownerId }) =>
  runBulkAction('assign', { owner_id: ownerId });
const onBulkStatus = ({ value }) => runBulkAction('status', { result: value });
const onBulkArchive = () => runBulkAction('delete');
const onBulkClear = () => store.dispatch('crmKanban/setListSelection', []);

/* -------------------------------------------------------------------------- */
/* Calendar (v2) wiring                                                       */
/* -------------------------------------------------------------------------- */
// The calendar emits the visible window; persist it then refetch that range.
const onCalendarRangeChange = async ({ from, to, includeCompleted }) => {
  store.dispatch('crmKanban/setCalendarRange', { from, to });
  if (includeCompleted !== undefined) {
    store.dispatch('crmKanban/setCalendarIncludeCompleted', includeCompleted);
  }
  await loadCurrentCalendar();
};

const onCalendarViewChange = view => {
  store.dispatch('crmKanban/setCalendarView', view);
};

const showMeetingDetail = ref(false);
const selectedMeetingEvent = ref(null);
const isMeetingEvent = event => event?.event_type === 'meeting';

// Open the existing card drawer from a calendar event (reuses openCardDrawer).
// Land on the tab that matches the event: follow-up/reminder events open on the
// Follow-ups tab; expected-close (Previsão) events on Resumo, where that field lives.
const onCalendarOpenEvent = event => {
  // #1460/#1461: lembrete que repete abre a repetição; o sem card, a gaveta.
  if (
    lembretesV2.value &&
    (event?.series_id ||
      (!event?.card_id && event?.id?.startsWith?.('follow_up_')))
  ) {
    lembreteGaveta.value = {
      show: true,
      modo: event.series_id ? 'serie' : 'unico',
      dia: new Date(event.starts_at),
      serieId: event.series_id || null,
      followUpId: event.series_id ? null : event.id.replace('follow_up_', ''),
    };
    return;
  }
  if (isMeetingEvent(event)) {
    selectedMeetingEvent.value = event;
    showMeetingDetail.value = true;
    return;
  }

  if (!event?.card_id) return;
  const initialTab = String(event.event_type || '').startsWith('follow_up')
    ? 'followups'
    : 'summary';
  openCardDrawer({ id: event.card_id }, { initialTab });
};

// Quick-add: clicking a day (or "+ Novo") opens the lightweight reminder popover,
// pre-filled with that date. Creating a deal still lives in the full drawer
// ("Mais opções" / the Kanban "+ Novo card").
const showQuickAdd = ref(false);
const quickAddDate = ref(new Date());
const quickAddType = ref('reminder');
const showMeetingScheduler = ref(false);
const meetingSchedulerCard = ref(null);
const meetingSchedulerDate = ref(new Date());
// When set, the scheduler mounts in reschedule mode prefilled from this meeting.
const meetingSchedulerMeeting = ref(null);

// Install-level flag (exposed in window.globalConfig, like CRM_KANBAN_ENABLED).
// Meetings are available to every account when this flag is on; each account
// schedules through its own connected Google/Microsoft calendar mailbox
// (Crm::Config.calendar_meetings_enabled? is ENV-only).
const isMeetingFeatureEnabled = computed(
  () => window.globalConfig?.[CRM_CALENDAR_MEETINGS_FEATURE] === 'true'
);
const userTimezone = computed(
  () => Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC'
);

const openMeetingScheduler = async ({ card, cardId, date } = {}) => {
  if (!isMeetingFeatureEnabled.value) return;

  showQuickAdd.value = false;
  const id = card?.id || cardId || selectedCard.value?.id;
  if (!id) {
    openCreateDrawer();
    return;
  }

  meetingSchedulerCard.value = card || { id };
  meetingSchedulerDate.value = date || new Date();

  try {
    const detailedCard =
      card?.title && card?.contact
        ? card
        : await store.dispatch('crmKanban/fetchCard', id);
    if (
      detailedCard?.id === Number(id) ||
      String(detailedCard?.id) === String(id)
    ) {
      meetingSchedulerCard.value = detailedCard;
    }
  } catch {
    useAlert(t('CRM_KANBAN.ALERTS.CARD_LOAD_ERROR'));
  }

  showMeetingScheduler.value = true;
};

const closeMeetingScheduler = () => {
  showMeetingScheduler.value = false;
  meetingSchedulerMeeting.value = null;
};

const closeMeetingDetail = () => {
  showMeetingDetail.value = false;
  selectedMeetingEvent.value = null;
};

// Pela agenda (#1265, `source: 'panel'`) não há convite por e-mail: outro aviso.
const scheduleMeeting = async meeting => {
  closeMeetingScheduler();
  useAlert(
    meeting?.source === 'panel'
      ? t('CRM_KANBAN.BOOKING_AGENDA.SUCCESS')
      : t('CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SUCCESS')
  );
  await refreshSelectedCard();
  await syncCalendarIfActive();
};

// Reschedule success (scheduler @updated): refresh the card + calendar in
// realtime (like cal12) and close any open meeting detail drawer.
const onMeetingRescheduled = async () => {
  closeMeetingScheduler();
  closeMeetingDetail();
  useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.RESCHEDULED_TOAST'));
  await refreshSelectedCard();
  await syncCalendarIfActive();
};

// Opens the scheduler in reschedule mode for a meeting. Fetches the full meeting
// (guests/inbox/times) when we only have the lightweight calendar event. An
// optional date prefills a new day/time from a calendar drag (always confirmed).
const openMeetingReschedule = async (meetingLike, date) => {
  if (!isMeetingFeatureEnabled.value) return;

  const rawId = String(
    meetingLike?.meeting_id || meetingLike?.id || ''
  ).replace(/^meeting_/, '');
  if (!rawId) return;

  let meeting = meetingLike;
  try {
    const { data } = await crmMeetingsAPI.show(currentAccountId.value, rawId);
    meeting = data?.payload || meetingLike;
  } catch {
    useAlert(t('CRM_KANBAN.CALENDAR.MEETING_DETAIL.ERRORS.LOAD_FAILED'));
    return;
  }

  if (date) {
    const next = date instanceof Date ? date : new Date(date);
    if (!Number.isNaN(next.getTime())) {
      const start = new Date(meeting.starts_at || next);
      const end = new Date(meeting.ends_at || next);
      const durationMs = end > start ? end - start : 30 * 60 * 1000;
      meeting = {
        ...meeting,
        starts_at: next.toISOString(),
        ends_at: new Date(next.getTime() + durationMs).toISOString(),
      };
    }
  }

  meetingSchedulerMeeting.value = meeting;
  meetingSchedulerCard.value = { id: meeting.card_id };
  meetingSchedulerDate.value = meeting.starts_at
    ? new Date(meeting.starts_at)
    : new Date();
  showMeetingScheduler.value = true;
};

const onCalendarQuickAdd = (payload = {}) => {
  if (mensagemMarcadaNova.value && payload.type === 'whatsapp') {
    // Só o Calendário novo pede "mensagem" (o antigo manda sempre 'reminder'), e
    // ele manda o dia como chave no fuso da conta. Sem dia, a gaveta começa sem
    // dia escolhido e conta o "hoje" no fuso da conta — nunca no do navegador.
    mensagemMarcada.value = { show: true, dia: payload.dia || '' };
    return;
  }
  if (lembretesV2.value && (!payload.type || payload.type === 'reminder')) {
    lembreteGaveta.value = {
      show: true,
      modo: 'novo',
      dia: payload.date ? new Date(payload.date) : new Date(),
      serieId: null,
      followUpId: null,
    };
    return;
  }
  quickAddDate.value = payload.date ? new Date(payload.date) : new Date();
  quickAddType.value = payload.type || 'reminder';
  showQuickAdd.value = true;
};

const onQuickAddCreate = async ({ cardId, title, dueAt }) => {
  try {
    await store.dispatch('crmKanban/createFollowUp', {
      card_id: cardId,
      title,
      follow_up_type: 'task',
      automation_mode: 'reminder_only',
      due_at: dueAt,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    });
    showQuickAdd.value = false;
    useAlert(t('CRM_KANBAN.ALERTS.FOLLOW_UP_CREATED'));
    await loadCurrentCalendar();
  } catch (error) {
    const apiMessage = error?.response?.data?.message;
    useAlert(apiMessage || t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'));
  }
};

const onQuickAddScheduleMeeting = ({ cardId, date } = {}) => {
  showQuickAdd.value = false;
  openMeetingScheduler({ cardId, date: date || quickAddDate.value });
};

// "Continuar" (WhatsApp/Previsão) and "Mais opções": when a deal is already
// picked, open THAT card's drawer on the relevant tab (WhatsApp → Follow-ups;
// Previsão → Resumo, where the expected-close field lives). Reunião opens the
// standalone scheduler. With no deal chosen, fall back to a fresh card.
const onQuickAddMoreOptions = ({ cardId, type } = {}) => {
  showQuickAdd.value = false;
  if (type === 'meeting') {
    onQuickAddScheduleMeeting({ cardId, date: quickAddDate.value });
    return;
  }

  if (cardId) {
    const initialTab = type === 'closeDate' ? 'summary' : 'followups';
    openCardDrawer({ id: cardId }, { initialTab });
  } else {
    openCreateDrawer();
  }
};

const SNOOZE_PRESET_MS = {
  '1h': 60 * 60 * 1000,
  tomorrow: 24 * 60 * 60 * 1000,
  next_week: 7 * 24 * 60 * 60 * 1000,
};

// Reschedule from a calendar drag/snooze. expected_close mutates the deal date
// (PATCH card); follow-up events go through the reschedule action (WhatsApp
// past-guard server-side). `date` may be a Date, ISO string, or snooze preset.
const onCalendarReschedule = async ({ event, date }) => {
  if (isMeetingEvent(event)) {
    // Never silently PATCH a meeting on drag — open the scheduler in reschedule
    // mode with the dragged-to date/time prefilled so the user confirms.
    let nextDate;
    if (date instanceof Date) {
      nextDate = date;
    } else if (SNOOZE_PRESET_MS[date]) {
      nextDate = new Date(Date.now() + SNOOZE_PRESET_MS[date]);
    } else if (date) {
      nextDate = new Date(date);
    }
    await openMeetingReschedule(event, nextDate);
    return;
  }

  try {
    const isCloseDate = event.event_type === 'expected_close';
    let nextDate;
    if (date instanceof Date) {
      nextDate = date;
    } else if (SNOOZE_PRESET_MS[date]) {
      nextDate = new Date(Date.now() + SNOOZE_PRESET_MS[date]);
    } else {
      nextDate = new Date(date);
    }
    const nextIso = nextDate.toISOString();

    if (isCloseDate) {
      await store.dispatch('crmKanban/updateCardFields', {
        id: event.card_id,
        expected_close_at: diaDoVencimento(nextDate),
      });
    } else {
      const followUpId = String(event.id).replace(/^follow_up_/, '');
      await store.dispatch('crmKanban/rescheduleFollowUp', {
        id: followUpId,
        dueAt: nextIso,
      });
    }
    await loadCurrentCalendar();
  } catch {
    useAlert(t('CRM_KANBAN.CALENDAR.RESCHEDULE_ERROR'));
  }
};

/* Calendário Ouro: concluir, próximo passo, adiar e abrir a conversa. */
// Só os canais conectados: "Mensagem marcada" exige uma caixa de WhatsApp
// que não esteja pedindo para reconectar (reauthorization_required). É o canal
// oficial que envia a mensagem marcada; o WhatsApp API (Híbrido) é auxiliar e
// não muda isso.
const ehWhatsappConectado = inbox =>
  (inbox.channel_type === 'Channel::Whatsapp' ||
    (inbox.channel_type === 'Channel::TwilioSms' &&
      inbox.medium === 'whatsapp')) &&
  inbox.reauthorization_required !== true;
const temWhatsappConectado = computed(() =>
  (inboxes.value || []).some(ehWhatsappConectado)
);
const idDoLembrete = evento => String(evento.id).replace('follow_up_', '');

// A tela já marcou como feito; se o servidor recusar, ela volta como estava.
const ouroConcluir = async ({ evento, falhou }) => {
  try {
    await store.dispatch('crmKanban/completeFollowUp', idDoLembrete(evento));
  } catch {
    falhou();
    useAlert(t('CRM_CALENDARIO.ALERTA.NAO_CONCLUIU'));
  }
  await loadCurrentCalendar();
};

const ouroProximoPasso = async ({ evento, titulo, quando, fuso }) => {
  try {
    await store.dispatch('crmKanban/createFollowUp', {
      card_id: evento.card_id || undefined,
      contact_id: evento.card_id ? undefined : evento.contact_id,
      title: titulo,
      follow_up_type: 'task',
      automation_mode: 'reminder_only',
      due_at: quando,
      timezone: fuso,
    });
    useAlert(t('CRM_CALENDARIO.ALERTA.PROXIMO_MARCADO'));
    await loadCurrentCalendar();
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR')
    );
  }
};

// Só aquela vez de cada lembrete (o reschedule mexe na linha, nunca na
// repetição). Se parte falhar, diz quantos passaram. Só lembretes (#1855): o
// servidor recusa envio ao cliente, para o lote nunca mandar mensagem.
const ouroAdiarAtrasados = async ({ eventos, quando }) => {
  const resultados = await Promise.allSettled(
    eventos.map(evento =>
      store.dispatch('crmKanban/rescheduleFollowUp', {
        id: idDoLembrete(evento),
        dueAt: quando,
        remindersOnly: true,
      })
    )
  );
  const total = eventos.length;
  const ok = resultados.filter(r => r.status === 'fulfilled').length;
  if (ok === total) {
    useAlert(t('CRM_CALENDARIO.ALERTA.ADIADOS', { n: total }, total));
  } else if (ok > 0) {
    useAlert(t('CRM_CALENDARIO.ALERTA.ADIADOS_PARCIAL', { ok, total }));
  } else {
    useAlert(t('CRM_KANBAN.CALENDAR.RESCHEDULE_ERROR'));
  }
  await loadCurrentCalendar();
};

// O evento já traz o número da conversa (display_id), o mesmo da rota (#1568).
const ouroAbrirConversa = displayId =>
  openCardConversation({ conversation: { display_id: displayId } });

// Reunião marcada pelo agendamento novo, direto do Meu dia (#1568).
const ouroReuniaoMarcada = async () => {
  useAlert(t('CRM_KANBAN.BOOKING_AGENDA.SUCCESS'));
  await loadCurrentCalendar();
};

const ouroMudarFunil = funil => {
  funilDoCalendario.value = funil;
  loadCurrentCalendar();
};

const onMeetingOpenCard = meeting => {
  closeMeetingDetail();
  if (meeting?.card_id) openCardDrawer({ id: meeting.card_id });
};

const onMeetingReschedule = async meeting => {
  const target = meeting || selectedMeetingEvent.value;
  closeMeetingDetail();
  await openMeetingReschedule(target);
};

const onMeetingCanceled = async () => {
  closeMeetingDetail();
  await refreshSelectedCard();
  await syncCalendarIfActive();
};

// After an outcome (held/no-show) is recorded, keep the detail open but refresh
// the card + calendar so the change is reflected without an F5 (cal12 pattern).
const onMeetingUpdated = async () => {
  await refreshSelectedCard();
  await syncCalendarIfActive();
};

// A aba de resultado segue o tipo do funil: "Ganho" vira "Resolvido" num funil que não é de venda (#1144).
const alignResultFilter = async () => {
  const { result } = filters.value;
  const statuses = outcomeStatuses(selectedPipeline.value);
  let aligned = result;
  if (SUCCESS_STATUSES.includes(result)) aligned = statuses.success;
  if (FAILURE_STATUSES.includes(result)) aligned = statuses.failure;
  if (aligned === result) return;
  filters.value = { ...filters.value, result: aligned };
  await store.dispatch('crmKanban/setFilters', filters.value);
};

watch(currentPipelineId, async (newPipelineId, oldPipelineId) => {
  if (newPipelineId && newPipelineId !== oldPipelineId) {
    // Rehydrate per-pipeline column layout from localStorage and clear stale
    // list selection before loading the new pipeline's active view.
    store.dispatch('crmKanban/loadListPrefs', newPipelineId);
    store.dispatch('crmKanban/setListSelection', []);
    fetchSavedViews();
    await alignResultFilter();
    await loadActiveView(true);
  }
});

watch(viewMode, async () => {
  await loadActiveView(true);
});

watch(
  () => route.query.card_id,
  () => {
    openRouteCardIfNeeded();
  }
);

const setViewMode = mode => {
  if (meuDiaNoLugarDoCalendario(mode)) {
    irParaOMeuDia(router.push);
    return;
  }
  viewMode.value = mode;
  if (!menuNovo.value || isCalendarOnly.value) return;
  const resto = Object.fromEntries(
    Object.entries(route.query).filter(([chave]) => chave !== 'view')
  );
  router.replace({
    query: mode === 'kanban' ? resto : { ...resto, view: mode },
  });
};

// #2095: as ações da página que Arquivados usa (declaradas acima deste ponto).
arquivados.ligar({
  recarregarVista: () => loadActiveView(true),
  fecharCard: closeDrawer,
  abrirCard: (card, aba = null) =>
    openCardDrawer({ id: card.id }, { initialTab: aba }),
  atualizarCardAberto: async id => {
    if (showDrawer.value && selectedCard.value?.id === id)
      await refreshSelectedCard();
  },
  funilPorId: id => pipelines.value.find(item => item.id === Number(id)),
  irParaALista: async (pipelineId, status) => {
    if (pipelineId && pipelines.value.some(p => p.id === Number(pipelineId)))
      currentPipelineId.value = Number(pipelineId);
    setViewMode('list');
    await selectResult(status);
  },
  recarregarFunis: async preferido => {
    const lista = await store.dispatch('crmKanban/fetchPipelines');
    const proximo =
      lista.find(item => item.id === Number(preferido)) ||
      lista.find(item => item.is_default) ||
      lista[0];
    currentPipelineId.value = proximo?.id || '';
    closePipelineDrawer();
  },
  juntar: nomes =>
    new Intl.ListFormat(String(locale.value).replace('_', '-'), {
      style: 'long',
      type: 'conjunction',
    }).format(nomes),
});
const abrirArquivadosDosFiltros = () => {
  showFiltersDrawer.value = false;
  arquivados.abrirPainel();
};
const abrirCardArquivado = linha => {
  arquivados.painelAberto.value = false;
  openCardFromBoard({ id: linha.id });
};
const carregarEtapasDoFunil = id =>
  store.dispatch('crmKanban/fetchPipelineStages', id);

useEmitter(BUS_EVENTS.WEBSOCKET_RECONNECT_COMPLETED, handleRealtimeConnected);
useEmitter(BUS_EVENTS.CRM_BOARD_REFETCH, handleServerFilterRefetch);
// Com o quadro já aberto, a URL com `card_id` não reabre um card que já passou
// por ela; o alerta do agendamento pede a abertura por aqui (#1291).
useEmitter(BUS_EVENTS.CRM_OPEN_CARD, cardId =>
  openCardFromBoard({ id: Number(cardId) })
);

onMounted(async () => {
  // Filtros do link: "Ver no CRM" do resultado da campanha (#1007) e os "Ver" do Números (#1883).
  // Partem do zero, para nenhum filtro antigo da sessão somar ao do link.
  const doLink = isCalendarOnly.value
    ? null
    : filtrosDoLink(route.query, { currentUserId: currentUser.value?.id });
  if (doLink) {
    filters.value = { ...defaultFilters(), ...doLink };
    donoDoLinkPorConferir.value = Boolean(doLink.ownerId);
    await store.dispatch('crmKanban/setFilters', filters.value);
  }
  await refreshData();
  // A aba de resultado segue o tipo do funil ("ganhos" num funil de Atender vira "resolvidos").
  if (doLink) await alignResultFilter();
  clearPipelineFromQuery();
  // Seed the per-pipeline column layout for the resolved initial pipeline.
  if (currentPipelineId.value) {
    store.dispatch('crmKanban/loadListPrefs', currentPipelineId.value);
    fetchSavedViews();
  }
  await openRouteCardIfNeeded();
});

onUnmounted(() => {
  if (companySearchTimer) clearTimeout(companySearchTimer);
});
</script>

<template>
  <main
    class="flex h-full w-full min-w-0 flex-col overflow-hidden bg-n-background"
  >
    <CrmOpportunityFromContact
      v-if="route.query.new_contact_id !== undefined"
      :ready="Boolean(currentPipelineId && stages.length && !isLoading)"
      :can-manage="canManageCards && canViewCrm"
      @open="openOpportunityForContact"
      @cancel="clearContactCreationIntent"
    />
    <header
      v-if="!calendarioOuro"
      class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-b border-n-weak px-6 py-3 sm:px-8"
    >
      <div
        class="flex min-w-0 flex-wrap items-center gap-4"
        :class="{ 'max-md:contents': listaAcao }"
      >
        <h1 v-if="listaAcao" class="mb-0 max-md:order-1">
          <ChoiceSelect
            :model-value="currentPipelineId"
            :options="pipelineGroups.length ? [] : pipelineOptions"
            :groups="pipelineGroups"
            :aria-label="t('CRM_LISTA_ACAO.FUNIL')"
            :disabled="!hasPipelines"
            fit-selected
            data-lista-acao-funil
            class="[&>button]:!h-11 [&>button]:!rounded-xl [&>button]:!bg-transparent [&>button]:!text-2xl [&>button]:!font-semibold [&>button]:!outline-0 hover:[&>button]:!bg-n-alpha-2"
            @update:model-value="escolherFunil"
          />
        </h1>
        <h1 v-else class="mb-0 text-2xl font-semibold text-n-slate-12">
          {{
            isCalendarOnly ? t('SIDEBAR.CRM_CALENDAR') : t('CRM_KANBAN.TITLE')
          }}
        </h1>
        <div
          v-if="!isCalendarOnly"
          class="flex items-center rounded-xl bg-n-alpha-2 p-1"
          :class="
            listaAcao
              ? 'max-md:order-3 max-md:grid max-md:w-full max-md:grid-cols-4'
              : { 'flex-wrap': menuNovo }
          "
          role="group"
          :aria-label="t('CRM_KANBAN.VIEWS.LABEL')"
        >
          <button
            v-for="mode in viewModeOptions"
            :key="mode.id"
            type="button"
            class="inline-flex min-h-11 items-center gap-1.5 rounded-lg px-3 text-sm font-medium text-n-slate-11 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="[
              viewMode === mode.id
                ? '!font-bold bg-n-surface-2 text-n-slate-12 shadow-sm'
                : '',
              listaAcao ? ABA_DA_LISTA_ACAO : '',
            ]"
            :aria-pressed="viewMode === mode.id"
            @click="setViewMode(mode.id)"
          >
            <span :class="mode.icon" class="size-3.5" aria-hidden="true" />
            {{ mode.label }}
          </button>
          <CrmAbaNumeros :class="listaAcao ? ABA_DA_LISTA_ACAO : ''" />
        </div>
      </div>

      <div
        class="flex min-w-0 flex-wrap items-center gap-2 sm:w-auto"
        :class="listaAcao ? 'ms-auto max-md:order-2' : 'w-full'"
      >
        <Button
          v-if="!listaAcao"
          icon="i-lucide-refresh-cw"
          slate
          outline
          class="!rounded-lg min-h-11 min-w-11 !outline-n-weak bg-n-surface-1"
          :title="t('CRM_KANBAN.ACTIONS.REFRESH')"
          :aria-label="t('CRM_KANBAN.ACTIONS.REFRESH')"
          :disabled="isLoading"
          @click="refreshData"
        />
        <Button
          v-if="canManageCards && viewMode !== 'calendar'"
          :label="
            t(
              listaAcao && funilDeVenda
                ? 'CRM_LISTA_ACAO.NOVO_CLIENTE'
                : funilDeVenda
                  ? 'CRM_KANBAN.ACTIONS.NEW_CARD'
                  : 'CRM_KANBAN.ACTIONS.NEW_CARD_ATENDER'
            )
          "
          icon="i-lucide-plus"
          data-crm-new-card
          :disabled="!hasPipelines || isLoading"
          class="order-2 !rounded-lg min-h-11 !font-bold"
          :class="
            listaAcao
              ? '!rounded-xl !bg-n-solid-1 !text-n-slate-12 !outline-n-weak hover:enabled:!bg-n-alpha-2'
              : ''
          "
          @click="openCreateDrawer"
        />
        <Button
          v-if="
            canOpenBooking && isMeetingFeatureEnabled && viewMode === 'calendar'
          "
          :label="t('CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT')"
          icon="i-lucide-calendar-clock"
          slate
          outline
          class="!rounded-lg min-h-11 !outline-n-weak bg-n-surface-1"
          @click="openBooking"
        />
        <Popover
          v-if="podeConfigurar"
          ref="configurationPopover"
          align="end"
          class="order-1"
        >
          <template #default>
            <Button
              :label="t('CRM_KANBAN.ACTIONS.CONFIGURE')"
              icon="i-lucide-settings-2"
              slate
              outline
              data-crm-configurar
              class="!rounded-lg min-h-11 !font-bold !outline-n-weak bg-n-surface-1"
              :class="
                listaAcao
                  ? 'max-lg:invisible max-lg:!w-0 max-lg:!min-w-0 max-lg:!p-0 max-lg:!outline-0 max-lg:overflow-hidden'
                  : ''
              "
              :aria-label="t('CRM_KANBAN.ACTIONS.CONFIGURE')"
            />
          </template>
          <template #content>
            <div class="grid w-72 gap-1 p-2">
              <p
                class="mb-1 px-2 py-1 text-xs font-medium text-n-slate-10"
                :class="listaAcao ? 'text-sm' : 'uppercase tracking-wide'"
              >
                {{ t('CRM_KANBAN.ACTIONS.CONFIGURE') }}
              </p>
              <Button
                v-if="
                  !isCalendarOnly &&
                  selectedPipeline &&
                  (canManagePipelines || canManageAi)
                "
                :label="t('CRM_KANBAN.ACTIONS.EDIT_PIPELINE')"
                icon="i-lucide-pencil"
                slate
                ghost
                start
                class="w-full"
                @click="runConfigurationAction(openEditPipelineDrawer)"
              />
              <Button
                v-if="
                  !isCalendarOnly &&
                  selectedPipeline &&
                  canManageAi &&
                  isCrmAiEnabled
                "
                :label="t('CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS')"
                icon="i-lucide-arrow-right-left"
                slate
                ghost
                start
                class="w-full"
                @click="runConfigurationAction(openHandoffSettings)"
              />
              <Button
                v-if="canOpenInboxSettings"
                :label="t('CRM_KANBAN.ACTIONS.INBOX_SETTINGS')"
                icon="i-lucide-inbox"
                slate
                ghost
                start
                class="w-full"
                @click="runConfigurationAction(openInboxSettingsDrawer)"
              />
              <template v-if="!isCalendarOnly && arquivadosLigado">
                <hr class="my-1 border-n-weak" />
                <Button
                  data-config-funis-arquivados
                  :label="
                    t('CRM_ARQUIVADOS.FUNIS.TITULO_N', {
                      count: arquivados.totalDeFunis.value,
                    })
                  "
                  icon="i-lucide-archive"
                  slate
                  ghost
                  start
                  class="w-full"
                  @click="runConfigurationAction(arquivados.abrirFunis)"
                />
              </template>
            </div>
          </template>
        </Popover>
      </div>
    </header>

    <section
      v-if="viewMode !== 'calendar' && !listaAcao"
      class="flex shrink-0 flex-col gap-3 border-b border-n-weak bg-n-surface-1 px-6 py-3 sm:px-8"
    >
      <div class="flex flex-wrap items-end gap-3">
        <div class="flex items-center gap-2">
          <ChoiceSelect
            :model-value="currentPipelineId"
            :options="pipelineGroups.length ? [] : pipelineOptions"
            :groups="pipelineGroups"
            :aria-label="t('CRM_KANBAN.FILTERS.PIPELINE')"
            :disabled="!hasPipelines"
            class="w-44 sm:w-52 [&>button]:!min-h-11 [&>button]:!rounded-lg [&>button]:!bg-n-surface-1 [&>button]:!font-bold"
            @update:model-value="escolherFunil"
          />
          <Button
            v-if="canManagePipelines"
            :label="t('CRM_KANBAN.ACTIONS.CREATE_PIPELINE')"
            icon="i-lucide-plus"
            blue
            outline
            class="!rounded-lg min-h-11 !border-0 !px-[1.0625rem] !font-bold !outline-none !bg-transparent focus-visible:ring-2 focus-visible:ring-n-brand"
            :disabled="isLoading"
            @click="openCreatePipelineDrawer"
          />
        </div>

        <div
          class="min-w-0 basis-full sm:min-w-[12rem] sm:flex-1 sm:basis-auto"
        >
          <Input
            id="crm-kanban-search"
            v-model="filters.search"
            custom-input-class="!min-h-11 !rounded-lg !bg-n-surface-1"
            :placeholder="t('CRM_KANBAN.FILTERS.SEARCH_PLACEHOLDER')"
            :aria-label="t('CRM_KANBAN.FILTERS.SEARCH')"
            @enter="applyFilters"
          />
        </div>

        <Button
          :label="t('CRM_KANBAN.ACTIONS.MORE_FILTERS')"
          icon="i-lucide-list-filter"
          slate
          outline
          class="!rounded-lg min-h-11 !font-bold !outline-n-weak bg-n-surface-1"
          :aria-expanded="showFiltersDrawer"
          @click="showFiltersDrawer = true"
        />
        <CrmKanbanZoom
          v-if="viewMode === 'kanban'"
          :model-value="zoom"
          :persistence-failed="persistenceFailed"
          class="ms-auto"
          @update:model-value="setZoom"
        />
        <CrmListExportButton
          v-if="canExportCrm && viewMode === 'list'"
          :pipeline-id="currentPipelineId"
          :sort-params="listSortParams"
          :disabled="!hasPipelines || isLoading"
        />
      </div>

      <!-- Applied filters stay visible so every selection can be understood and removed. -->
      <div
        v-if="activeFilterChips.length"
        class="flex flex-wrap items-center gap-2"
      >
        <button
          v-for="chip in activeFilterChips"
          :key="chip.key"
          type="button"
          class="inline-flex min-h-11 items-center gap-1.5 rounded-full bg-n-alpha-2 px-3 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="
            t('CRM_KANBAN.ACTIONS.REMOVE_FILTER', { filter: chip.label })
          "
          @click="removeFilterChip(chip.key)"
        >
          {{ chip.label }}
          <span class="i-lucide-x size-3 text-n-slate-10" aria-hidden="true" />
        </button>
        <Button
          :label="t('CRM_KANBAN.ACTIONS.CLEAR_FILTERS')"
          slate
          ghost
          sm
          @click="clearFilters"
        />
      </div>
    </section>

    <CrmKanbanFiltersDrawer
      :show="showFiltersDrawer"
      :venda="funilDeVenda"
      :pipeline-name="selectedPipeline?.name"
      :current-user-id="currentUser?.id"
      :filters="filters"
      :view-mode="viewMode"
      :inbox-choices="inboxChoices"
      :owner-choices="ownerChoices"
      :priority-choices="priorityChoices"
      :follow-up-status-choices="followUpStatusChoices"
      :company-choices="companyFilterOptions"
      :company-search="companySearch"
      :company-loading="companyLoading"
      :company-filter-available="
        companyFilterAvailable && canViewRelationshipRecords
      "
      :responsible-choices="responsibleChoices"
      :team-choices="teamChoices"
      :stage-options="stageOptions"
      :label-options="labelOptions"
      :campaign-filter-options="campaignFilterOptions"
      :stale-choices="staleChoices"
      :linked-choices="linkedChoices"
      :result-choices="resultChoices"
      :arquivados="
        arquivadosLigado && viewMode !== 'calendar'
          ? (arquivados.totalDoFunil.value ?? 0)
          : null
      "
      @abrir-arquivados="abrirArquivadosDosFiltros"
      @close="showFiltersDrawer = false"
      @apply="applyFiltersFromDrawer"
      @clear="clearFiltersFromDrawer"
      @search-company="onCompanySearch"
    />

    <section
      v-if="loadError && hasBoardContent"
      class="flex items-center justify-between gap-3 border-b border-n-weak bg-n-ruby-2 px-8 py-3 text-sm"
    >
      <div class="min-w-0">
        <p class="mb-0 font-medium text-n-ruby-11">
          {{ t('CRM_KANBAN.ERRORS.TITLE') }}
        </p>
        <p class="mb-0 truncate text-xs text-n-ruby-10">
          {{ loadError }}
        </p>
      </div>
      <Button
        :label="t('CRM_KANBAN.ERRORS.RETRY')"
        icon="i-lucide-refresh-cw"
        ruby
        faded
        sm
        @click="refreshData"
      />
    </section>

    <div v-if="isLoading" class="flex flex-1 items-center justify-center">
      <Spinner />
    </div>

    <section
      v-else-if="loadError && !hasBoardContent"
      class="flex flex-1 items-center justify-center px-8"
    >
      <div class="max-w-xl text-center">
        <p class="mb-2 text-lg font-medium text-n-ruby-11">
          {{ t('CRM_KANBAN.ERRORS.TITLE') }}
        </p>
        <p class="mb-5 text-sm leading-6 text-n-slate-11">
          {{ loadError }}
        </p>
        <Button
          :label="t('CRM_KANBAN.ERRORS.RETRY')"
          icon="i-lucide-refresh-cw"
          @click="refreshData"
        />
      </div>
    </section>

    <section
      v-else-if="!hasPipelines"
      class="flex flex-1 items-center justify-center px-8"
    >
      <div class="max-w-xl text-center">
        <p class="mb-2 text-lg font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.EMPTY.TITLE') }}
        </p>
        <p class="mb-5 text-sm leading-6 text-n-slate-11">
          {{ t('CRM_KANBAN.EMPTY.DESCRIPTION') }}
        </p>
        <Button
          v-if="canManagePipelines"
          :label="t('CRM_KANBAN.ACTIONS.CREATE_INITIAL_PIPELINE')"
          icon="i-lucide-kanban"
          @click="openCreatePipelineDrawer"
        />
      </div>
    </section>

    <section
      v-else-if="viewMode === 'kanban'"
      ref="kanbanBoard"
      data-kanban-board
      :class="zoomClass"
      class="flex min-h-0 min-w-0 flex-1 gap-4 overflow-x-auto overflow-y-hidden bg-n-slate-3 px-8 py-5"
      @pointerdown.capture="resetKanbanClick"
      @click.capture="ignoreDragClick"
    >
      <article
        v-for="stage in stages"
        :key="stage.id"
        :data-stage-id="stage.id"
        class="flex h-full w-[19rem] shrink-0 flex-col overflow-hidden rounded-xl bg-n-alpha-1"
      >
        <header
          class="flex min-h-14 items-center justify-between gap-3 px-4 py-3"
        >
          <div class="flex min-w-0 items-center gap-2">
            <span
              class="size-2.5 shrink-0 rounded-sm"
              :style="{ backgroundColor: stage.color || '#64748b' }"
            />
            <h2
              class="mb-0 truncate text-base font-semibold text-n-slate-12"
              :title="stage.name"
            >
              {{ stage.name }}
            </h2>
          </div>
          <span
            class="shrink-0 rounded-lg bg-n-surface-1 px-2 py-1 text-xs font-medium tabular-nums text-n-slate-11"
            :aria-label="
              t('CRM_KANBAN.STATUS.STAGE_CARDS', {
                count: stage.cards_count ?? stage.cards.length,
              })
            "
          >
            {{ stage.cards_count ?? stage.cards.length }}
          </span>
        </header>

        <!-- :sort=false — a ordem da coluna é sempre por conversa mais recente
             (getter); reordenar manualmente dentro da coluna seria revertido no
             próximo tick, então fica desabilitado. Drag entre etapas segue. -->
        <Draggable
          v-model="stage.cards"
          item-key="id"
          group="crm-kanban-cards"
          ghost-class="opacity-40"
          drag-class="cursor-grabbing"
          fallback-class="crm-kanban-drag-preview"
          v-bind="{
            'fallback-on-body': true,
            'force-fallback': true,
            'fallback-tolerance': 4,
            scroll: false,
          }"
          data-kanban-list
          class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-2 pb-3 pt-2"
          :animation="150"
          :disabled="!canMoveCards || uiFlags.isMovingCard"
          :sort="false"
          filter=".crm-card-open-conversation"
          :prevent-on-filter="false"
          @start="onDragStart"
          @end="stopAutoScroll"
          @change="event => onDragChange(stage, event)"
        >
          <template #item="{ element }">
            <div
              :data-card-id="element.id"
              :dir="isRTL ? 'rtl' : 'ltr'"
              class="w-full shrink-0 [&.crm-kanban-drag-preview>*]:w-auto"
              :class="KANBAN_ZOOM_DRAG_CLASSES[zoom]"
            >
              <!-- Body-mounted preview: scale the child, not pointer coordinates. -->
              <CrmKanbanCard
                :card="element"
                :stage-color="stage.color"
                :com-valor="quadroComValor"
                @open="openCardFromBoard"
                @open-conversation="openCardConversation"
              />
            </div>
          </template>

          <template #footer>
            <div
              v-if="stage.cards.length === 0"
              class="flex min-h-24 items-center justify-center rounded-lg border border-dashed border-n-weak px-4 py-6 text-center text-xs leading-5 text-n-slate-10"
            >
              {{ t('CRM_KANBAN.EMPTY.DROP_HINT') }}
            </div>
            <Button
              v-if="stage.has_more"
              :label="t('CRM_KANBAN.ACTIONS.LOAD_MORE')"
              icon="i-lucide-chevron-down"
              slate
              faded
              sm
              @click="loadMore(stage)"
            />
          </template>
        </Draggable>
      </article>
    </section>

    <section
      v-else-if="listaAcao"
      class="flex min-h-0 flex-1 flex-col overflow-y-auto"
    >
      <ListaAcao
        ref="listaAcaoRef"
        :pipeline-id="currentPipelineId"
        :pipeline="selectedPipeline"
        :filtros="storedFilters"
        :filtros-ativos="filtrosDaListaAcao"
        :meu-id="currentUser?.id"
        :meu-nome="currentUser?.name || ''"
        :pessoas="agents"
        :fuso="fusoDaListaAcao"
        :pode-passar="canManageCards"
        :pode-mexer="canManageCards"
        :pode-baixar="canExportCrm"
        :pode-marcar="canBulkAct"
        :pode-configurar="podeConfigurar"
        :selecionados="listSelection"
        :pode-ver-valor="canSeeSalesValues"
        :listas="savedViews"
        :config-atual="currentSavedViewConfig"
        :eh-admin="currentRole === 'administrator'"
        @filtros="showFiltersDrawer = true"
        @configurar="abrirConfiguracao"
        @abrir="openCardFromBoard"
        @conversa="openCardConversation"
        @selecionar="ids => store.dispatch('crmKanban/setListSelection', ids)"
        @limpar-filtros="clearFilters"
        @abrir-lista="view => onSavedViewApply({ view })"
        @guardar-lista="onSavedViewCreate"
        @mudar-lista="onSavedViewUpdate"
        @apagar-lista="onSavedViewDelete"
        @tirar-nota="tirarNotaDaListaAcao"
      />
      <CrmBulkActionBar
        :count="listSelection.length"
        :ids="listSelection"
        :permissions="bulkPermissions"
        :stages="stages"
        :owners="agents"
        :blocked-owner-ids="[]"
        :pipeline="selectedPipeline"
        :is-busy="uiFlags.isBulkActing"
        @move="onBulkMove"
        @assign="onBulkAssign"
        @status="onBulkStatus"
        @archive="onBulkArchive"
        @clear="onBulkClear"
      />
    </section>

    <section
      v-else-if="viewMode === 'list'"
      class="flex min-h-0 flex-1 flex-col px-8 py-5"
    >
      <div class="mb-3 flex items-center justify-between gap-2">
        <div class="flex items-center gap-3">
          <CrmResultTabs
            :model-value="filters.result"
            :pipeline="selectedPipeline"
            @update:model-value="selectResult"
          />
          <p class="mb-0 text-xs text-n-slate-10">
            {{ t('CRM_KANBAN.LIST.META', { count: cardsListMeta.count || 0 }) }}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <CrmSavedViews
            :views="savedViews"
            :current-config="currentSavedViewConfig"
            :pipeline-id="currentPipelineId"
            @apply="onSavedViewApply"
            @create="onSavedViewCreate"
            @update="onSavedViewUpdate"
            @delete="onSavedViewDelete"
          />
          <CrmTableColumnSettings
            :columns="columnSettingsItems"
            :density="listColumnState.density"
            @update="onColumnSettingsUpdate"
          />
        </div>
      </div>
      <CrmCardsTable
        :cards="cardsListWithMeta"
        :stages="stages"
        :owners="agents"
        :owner-blocked="donosBarradosPorCard"
        :pipeline="selectedPipeline"
        :show-meta-column="isMetaSyncActive"
        :loading="uiFlags.isFetchingCardsList"
        :error="!!loadError"
        :sort="ordemPermitida(listSort)"
        :group-by="listGroupBy"
        :column-state="listColumnState"
        :selected-ids="listSelection"
        :selectable="canBulkAct"
        :collapsed-groups="collapsedGroups"
        :total-count="cardsListMeta.count || 0"
        :has-more="hasMoreCards"
        :has-active-filters="hasActiveFilters"
        @sort-change="onListSortChange"
        @page-change="loadMoreList"
        @group-change="onListGroupChange"
        @column-change="onListColumnChange"
        @select-change="onListSelectChange"
        @open-card="openCardFromBoard"
        @edit-save="onListEditSave"
        @retry="loadCurrentList"
        @clear-filters="clearFilters"
      />
      <CrmBulkActionBar
        :count="listSelection.length"
        :ids="listSelection"
        :permissions="bulkPermissions"
        :stages="stages"
        :owners="agents"
        :blocked-owner-ids="donosBarradosNaSelecao"
        :pipeline="selectedPipeline"
        :is-busy="uiFlags.isBulkActing"
        @move="onBulkMove"
        @assign="onBulkAssign"
        @status="onBulkStatus"
        @archive="onBulkArchive"
        @clear="onBulkClear"
      />
    </section>

    <CalendarioOuro
      v-else-if="viewMode === 'calendar' && calendarioOuro"
      :events="calendarEvents"
      :loading="uiFlags.isFetchingCalendar"
      :error="!!loadError"
      :owners="agents"
      :current-user-id="currentUser?.id"
      :funil="funilDoCalendario"
      :funis="pipelineOptions"
      :filtro-inicial="filtroDoMeuDia"
      :eh-admin="currentRole === 'administrator'"
      :tem-whatsapp="temWhatsappConectado"
      :reunioes-ligadas="isMeetingFeatureEnabled"
      :pode-agendamento="canOpenBooking && isMeetingFeatureEnabled"
      :pode-caixas="canOpenInboxSettings"
      :caixas="inboxes"
      @update:funil="ouroMudarFunil"
      @abrir-agendamento="openBooking"
      @abrir-caixas="openInboxSettingsDrawer"
      @reuniao-marcada="ouroReuniaoMarcada"
      @range-change="onCalendarRangeChange"
      @abrir="onCalendarOpenEvent"
      @abrir-conversa="ouroAbrirConversa"
      @novo="onCalendarQuickAdd"
      @concluir="ouroConcluir"
      @proximo-passo="ouroProximoPasso"
      @adiar-atrasados="ouroAdiarAtrasados"
      @retry="loadCurrentCalendar"
    />
    <section
      v-else-if="viewMode === 'calendar' && !meuDiaLigado"
      class="flex min-h-0 flex-1 flex-col px-8 pb-4 pt-1"
    >
      <CrmCalendar
        :events="calendarEvents"
        :loading="uiFlags.isFetchingCalendar"
        :error="!!loadError"
        :owners="agents"
        :current-user-id="currentUser?.id"
        :pipeline-id="currentPipelineId"
        :pipelines="pipelineOptions"
        :paused="
          showDrawer ||
          showPipelineDrawer ||
          showInboxSettingsDrawer ||
          showBookingProfilesDrawer
        "
        @update:pipeline-id="currentPipelineId = $event"
        @range-change="onCalendarRangeChange"
        @view-change="onCalendarViewChange"
        @open-event="onCalendarOpenEvent"
        @quick-add="onCalendarQuickAdd"
        @reschedule="onCalendarReschedule"
        @retry="loadCurrentCalendar"
      />
    </section>

    <LembreteGaveta
      v-if="lembretesV2"
      :show="lembreteGaveta.show"
      :modo="lembreteGaveta.modo"
      :dia="lembreteGaveta.dia"
      :serie-id="lembreteGaveta.serieId"
      :follow-up-id="lembreteGaveta.followUpId"
      @salvou="loadCurrentCalendar"
      @close="lembreteGaveta = { ...lembreteGaveta, show: false }"
    />
    <MensagemMarcadaGaveta
      v-if="mensagemMarcadaNova"
      :show="mensagemMarcada.show"
      :dia="mensagemMarcada.dia"
      :caixas="inboxes"
      @salvou="loadCurrentCalendar"
      @abrir-negocio="
        id => {
          mensagemMarcada = { ...mensagemMarcada, show: false };
          openCardDrawer({ id }, { initialTab: 'followups' });
        }
      "
      @close="mensagemMarcada = { ...mensagemMarcada, show: false }"
    />
    <CrmCalendarQuickAdd
      :show="showQuickAdd"
      :date="quickAddDate"
      :pipeline-id="currentPipelineId"
      :default-type="quickAddType"
      :meetings-enabled="isMeetingFeatureEnabled"
      :booking-v2="isBookingV2"
      @create="onQuickAddCreate"
      @more-options="onQuickAddMoreOptions"
      @schedule-meeting="onQuickAddScheduleMeeting"
      @close="showQuickAdd = false"
    />

    <CrmCalendarMeetingScheduler
      v-if="isMeetingFeatureEnabled"
      v-model:show="showMeetingScheduler"
      :account-id="currentAccountId"
      :card-id="meetingSchedulerCard?.id"
      :deal-title="meetingSchedulerCard?.title"
      :date="meetingSchedulerDate"
      :available-inboxes="inboxes"
      :card-contact-email="meetingSchedulerCard?.contact?.email"
      :card-contact-name="meetingSchedulerCard?.contact?.name"
      :meeting="meetingSchedulerMeeting"
      :card="meetingSchedulerCard"
      @create="scheduleMeeting"
      @updated="onMeetingRescheduled"
      @close="closeMeetingScheduler"
    />

    <CrmMeetingDetail
      :show="showMeetingDetail"
      :event="selectedMeetingEvent"
      :account-id="currentAccountId"
      :timezone="userTimezone"
      @close="closeMeetingDetail"
      @open-card="onMeetingOpenCard"
      @reschedule="onMeetingReschedule"
      @canceled="onMeetingCanceled"
      @updated="onMeetingUpdated"
    />

    <CardGaveta
      ref="cardDrawerRef"
      :show="showDrawer"
      :mode="drawerMode"
      :card="selectedCard"
      :initial-tab="drawerInitialTab"
      :initial-contact="creationContact"
      :stages="drawerMode === 'edit' ? cardDrawerStages : stages"
      :pipelines="pipelines"
      :pipeline-id="currentPipelineId"
      :agents="agents"
      :inboxes="inboxes"
      :follow-ups="followUps"
      :can-manage-cards="canManageCards && podeMexerNoCard"
      :can-move-cards="canMoveCards && podeMexerNoCard"
      :can-delete-cards="canDeleteCards && podeMexerNoCard"
      :is-moving-card="uiFlags.isMovingCard"
      :can-manage-ai="canManageAi"
      :is-saving="uiFlags.isCreatingCard || uiFlags.isUpdatingCard"
      :is-loading-details="uiFlags.isFetchingCard"
      :is-archiving="uiFlags.isArchivingCard"
      :is-fetching-follow-ups="uiFlags.isFetchingFollowUps"
      :is-saving-follow-up="uiFlags.isSavingFollowUp"
      :meetings-enabled="isMeetingFeatureEnabled"
      :arquivados-ligado="arquivadosLigado"
      :erro-arquivar="arquivados.erroArquivarCard.value"
      :restaurando="arquivados.restaurandoCard.value"
      :erro-restaurar="arquivados.erroRestaurarCard.value"
      @restaurar="arquivados.restaurarCardAberto(selectedCard)"
      @save="saveCard"
      @move="moveCardFromDetails"
      @archive="archiveCard"
      @close-deal="closeCardDeal"
      @create-follow-up="createFollowUp"
      @complete-follow-up="completeFollowUp"
      @cancel-follow-up="cancelFollowUp"
      @refresh-card="refreshSelectedCard"
      @close="closeDrawer"
    />

    <CrmPipelineDrawer
      :show="showPipelineDrawer"
      :mode="pipelineDrawerMode"
      :pipeline="pipelineDrawerMode === 'edit' ? selectedPipeline : null"
      :stages="pipelineDrawerMode === 'edit' ? pipelineDrawerStages : []"
      :inboxes="inboxes"
      :pipeline-inboxes="pipelineInboxes"
      :is-saving="uiFlags.isSavingPipeline"
      :is-archiving="uiFlags.isArchivingPipeline"
      :is-deleting-stage="uiFlags.isDeletingStage"
      :is-loading-pipeline-inboxes="uiFlags.isFetchingPipelineInboxes"
      :agents="agents"
      @save="savePipeline"
      @archive="archivePipeline"
      @delete-stage="deleteStage"
      @close="closePipelineDrawer"
    />

    <CrmInboxSettingsDrawer
      :show="showInboxSettingsDrawer"
      :inboxes="inboxes"
      :settings="inboxSettings"
      :pipelines="pipelines"
      :stages-by-pipeline="inboxSettingStagesByPipeline"
      :is-loading="uiFlags.isFetchingInboxSettings"
      :is-loading-stages="uiFlags.isFetchingPipelineStages"
      :save-result="inboxSaveResult"
      @save="saveInboxSetting"
      @load-pipeline-stages="loadPipelineStagesForSettings"
      @close="closeInboxSettingsDrawer"
    />

    <CrmBookingProfilesDrawer
      :show="showBookingProfilesDrawer"
      :inboxes="inboxes"
      :pipelines="pipelines"
      :agents="agents"
      @close="closeBookingProfilesDrawer"
    />

    <template v-if="arquivadosLigado">
      <PainelArquivados
        :ref="el => (arquivados.painel.value = el)"
        :show="arquivados.painelAberto.value"
        :funil="selectedPipeline"
        :funis="pipelines"
        :pode-arquivar="canDeleteCards"
        :restaurar="arquivados.restaurar"
        @close="arquivados.painelAberto.value = false"
        @abrir-card="abrirCardArquivado"
        @ver-funis-arquivados="arquivados.abrirFunis"
        @mudou="arquivados.depoisDeMudar"
      />
      <PainelFunisArquivados
        :show="arquivados.funisAbertos.value"
        :pode-gerenciar="canManagePipelines"
        @close="arquivados.funisAbertos.value = false"
        @restaurado="arquivados.funilRestaurado"
      />
      <RestaurarConflito
        :ref="el => (arquivados.dialogoConflito.value = el)"
        :conflito="arquivados.conflito.value"
        :ocupado="arquivados.conflitoOcupado.value"
        :erro="arquivados.conflitoErro.value"
        @abrir-aberto="arquivados.abrirOAberto"
        @restaurar-mesmo-assim="arquivados.restaurarMesmoAssim"
        @close="arquivados.aoFecharConflito"
      />
      <ArquivarFunilDialogo
        ref="arquivarFunilDialogo"
        :carregar-etapas="carregarEtapasDoFunil"
        @arquivado="arquivados.funilArquivado"
        @criar-funil="openCreatePipelineDrawer"
      />
      <CrmAviso />
    </template>

    <ConfirmModal
      ref="confirmModal"
      :title="confirmConfig.title"
      :description="confirmConfig.description"
      :confirm-label="confirmConfig.confirmLabel"
      :cancel-label="t('CRM_KANBAN.CONFIRM.CANCEL')"
      :confirm-disabled="deleteStageHasCards && !deleteStageTargetId"
    >
      <div v-if="stageToDelete && deleteStageHasCards" class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('CRM_KANBAN.CONFIRM.DELETE_STAGE_TARGET_LABEL') }}
        </span>
        <ChoiceSelect
          v-model="deleteStageTargetId"
          :options="deleteStageChoices"
          :placeholder="t('CRM_KANBAN.CONFIRM.DELETE_STAGE_TARGET_PLACEHOLDER')"
          :aria-label="t('CRM_KANBAN.CONFIRM.DELETE_STAGE_TARGET_LABEL')"
          class="w-full"
        />
      </div>
    </ConfirmModal>
  </main>
</template>
