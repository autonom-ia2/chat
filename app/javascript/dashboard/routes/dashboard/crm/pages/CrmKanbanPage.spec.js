/* eslint-disable vue/one-component-per-file -- stubs de teste da gaveta, um por cenário */
import { flushPromises, mount } from '@vue/test-utils';
import { h, ref } from 'vue';
import CrmKanbanPage from './CrmKanbanPage.vue';
import { useAlert } from 'dashboard/composables';
import { useEmitter } from 'dashboard/composables/emitter';
import CrmKanbanZoom from '../components/CrmKanbanZoom.vue';
import {
  KANBAN_ZOOM_CLASSES,
  KANBAN_ZOOM_DRAG_CLASSES,
} from '../helpers/kanbanZoom';

// The page is a large orchestrator. These specs pin three review findings:
// the Agenda keeps its admin actions, drag is gated by permission, and the
// stage changes stay available inside the card details.

const route = { meta: {}, query: {}, params: {} };
const permissions = {};
const storeGetters = {};
const dispatch = vi.fn();
const push = vi.fn();
const replace = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: { value: 'en' },
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push, replace }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: (...args) => dispatch(...args),
    getters: { 'globalConfig/get': {} },
  }),
  useMapGetter: key => storeGetters[key] || ref(undefined),
  useStoreGetters: () => ({}),
}));

vi.mock('../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => permissions,
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({ canViewRelationshipRecords: ref(true) }),
}));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/api/crmMeetings', () => ({ default: {} }));
vi.mock('dashboard/api/ctwaCampaigns', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: [] })) },
}));
vi.mock('dashboard/api/companies', () => ({
  default: {
    search: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
    show: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));
vi.mock('dashboard/api/metaConversions', () => ({
  default: { getForCards: vi.fn(() => Promise.resolve({ data: {} })) },
}));

// Renders every card through the item slot and exposes the disabled flag, so
// the drag permission can be asserted without Sortable in jsdom.
const DraggableStub = {
  name: 'Draggable',
  props: {
    modelValue: { type: Array, default: () => [] },
    disabled: { type: Boolean, default: false },
  },
  template: `
    <div data-test-draggable :data-disabled="String(disabled)">
      <template v-for="element in modelValue" :key="element.id">
        <slot name="item" :element="element" />
      </template>
      <slot name="footer" />
    </div>
  `,
};

const PIPELINE = { id: 1, name: 'Vendas' };
const STAGES = [
  {
    id: 10,
    name: 'Novo',
    color: '#2563eb',
    cards: [{ id: 100, title: 'Acme deal', company: { name: 'Acme' } }],
  },
  {
    id: 11,
    name: 'Proposta',
    color: '#22c55e',
    cards: [{ id: 101, title: 'Beta deal', company: { name: 'Beta' } }],
  },
];

const setPermissions = overrides => {
  Object.assign(permissions, {
    canManageCards: ref(true),
    canViewCrm: ref(true),
    canMoveCards: ref(true),
    canDeleteCards: ref(true),
    canManagePipelines: ref(true),
    canManageAi: ref(true),
    canExportCrm: ref(false),
    canSeeSalesValues: ref(true),
    ...Object.fromEntries(
      Object.entries(overrides).map(([key, value]) => [key, ref(value)])
    ),
  });
};

// `bookingV2` liga a opção da conta `crm_booking_v2` (agendamento novo, #1212).
const setGetters = ({
  bookingV2 = false,
  calendarioOuro = false,
  inboxes = [],
  role = 'administrator',
  keys,
  menuNovo = false,
  agents = [],
  filters = {},
} = {}) => {
  Object.assign(storeGetters, {
    getCurrentRole: ref(role),
    'accounts/getAccount': ref(() => ({
      id: 1,
      features: {
        crm_booking_v2: bookingV2,
        crm_calendario_ouro: calendarioOuro,
      },
    })),
    'crmKanban/getPipelines': ref([PIPELINE]),
    'crmKanban/getStages': ref(
      STAGES.map(s => ({ ...s, cards: [...s.cards] }))
    ),
    'crmKanban/getCardsList': ref([]),
    'crmKanban/getCardsListMeta': ref({}),
    'crmKanban/getFollowUps': ref([]),
    'crmKanban/getCalendarEvents': ref([]),
    'crmKanban/getUIFlags': ref({}),
    'crmKanban/getFilters': ref(filters),
    'crmKanban/getListPrefs': ref({}),
    'crmKanban/getListSort': ref({}),
    'crmKanban/getListGroupBy': ref(''),
    'crmKanban/getListSelection': ref([]),
    'crmKanban/getSavedViews': ref([]),
    getCurrentUser: ref({
      id: 1,
      accounts: [{ id: 1, permissions: keys || [] }],
    }),
    getCurrentAccountId: ref(1),
    'inboxes/getInboxes': ref(inboxes),
    'agents/getAgents': ref(agents),
    'teams/getTeams': ref([]),
    'accounts/isRTL': ref(false),
    'labels/getLabels': ref([]),
    'accounts/isFeatureEnabledonAccount': ref(
      (_id, flag) => menuNovo && flag === 'menu_lateral_novo'
    ),
  });
};

const mountPage = async ({
  calendarOnly = false,
  perms = {},
  stubs = {},
  account = {},
} = {}) => {
  route.meta = calendarOnly ? { calendarOnly: true } : {};
  setPermissions(perms);
  setGetters(account);
  const wrapper = mount(CrmKanbanPage, {
    attachTo: document.body,
    global: {
      stubs: {
        Draggable: DraggableStub,
        Spinner: true,
        ConfirmModal: true,
        CardGaveta: true,
        CrmKanbanFiltersDrawer: true,
        CrmOpportunityFromContact: true,
        CrmPipelineDrawer: true,
        CrmInboxSettingsDrawer: true,
        CrmBookingProfilesDrawer: true,
        CrmCardsTable: true,
        CrmListExportButton: true,
        CrmTableColumnSettings: true,
        CrmSavedViews: true,
        // Aba Números do menu novo (#1617): tem teste próprio (useAbaNumeros.spec.js).
        CrmAbaNumeros: true,
        CrmResultTabs: true,
        CrmBulkActionBar: true,
        CrmCalendar: true,
        CalendarioOuro: true,
        CrmCalendarQuickAdd: true,
        CrmCalendarMeetingScheduler: true,
        CrmMeetingDetail: true,
        ChannelIcon: true,
        CardPriorityIcon: true,
        CardLabels: true,
        SLACardLabel: true,
        CrmCardPill: true,
        ...stubs,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const openConfiguration = async wrapper => {
  const trigger = wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.ACTIONS.CONFIGURE');
  expect(trigger).toBeDefined();
  await trigger.trigger('click');
  await flushPromises();
  return document.body.textContent;
};

describe('CrmKanbanPage', () => {
  let wrapper;

  // #1617 — com o menu novo, a vista fica no endereço (?view=); sem ele, como sempre foi.
  describe('vista no endereço (menu novo)', () => {
    const vistaMarcada = pagina =>
      pagina.find('[role="group"] [aria-pressed="true"]').text();
    const botaoDaVista = (pagina, chave) =>
      pagina
        .findAll('[role="group"] button')
        .find(botao => botao.text() === chave);

    afterEach(() => {
      route.query = {};
      replace.mockClear();
      wrapper?.unmount();
    });

    it('flag desligada: ignora ?view= e não mexe no endereço ao trocar de vista', async () => {
      route.query = { view: 'list' };
      wrapper = await mountPage();
      expect(vistaMarcada(wrapper)).toBe('CRM_KANBAN.VIEWS.KANBAN');
      expect(wrapper.find('[role="group"]').classes()).not.toContain(
        'flex-wrap'
      );
      await botaoDaVista(wrapper, 'CRM_KANBAN.VIEWS.LIST').trigger('click');
      expect(replace).not.toHaveBeenCalled();
    });

    // #1883: ao recarregar (ou abrir o link numa aba nova), a flag da conta chega depois da tela.
    it('flag que chega depois da tela ainda abre na vista do endereço', async () => {
      route.query = { view: 'list' };
      wrapper = await mountPage();
      expect(vistaMarcada(wrapper)).toBe('CRM_KANBAN.VIEWS.KANBAN');

      storeGetters['accounts/isFeatureEnabledonAccount'].value = (_id, flag) =>
        flag === 'menu_lateral_novo';
      await flushPromises();
      expect(vistaMarcada(wrapper)).toBe('CRM_KANBAN.VIEWS.LIST');
    });

    it('flag ligada: abre na vista do endereço e grava a troca com replace', async () => {
      route.query = { view: 'list', pipeline_id: undefined };
      wrapper = await mountPage({ account: { menuNovo: true } });
      expect(vistaMarcada(wrapper)).toBe('CRM_KANBAN.VIEWS.LIST');
      expect(wrapper.find('[role="group"]').classes()).toContain('flex-wrap');
      replace.mockClear();
      route.query = { view: 'list' };
      await botaoDaVista(wrapper, 'CRM_KANBAN.VIEWS.CALENDAR').trigger('click');
      expect(replace).toHaveBeenLastCalledWith({ query: { view: 'calendar' } });
      route.query = { view: 'calendar' };
      await botaoDaVista(wrapper, 'CRM_KANBAN.VIEWS.KANBAN').trigger('click');
      expect(replace).toHaveBeenLastCalledWith({ query: {} });
    });
  });

  // #1894 — com o Meu dia ligado, a aba Calendário leva ao endereço do Meu dia, nunca ao calendário antigo.
  describe('aba Calendário com o Meu dia ligado', () => {
    const botaoCalendario = pagina =>
      pagina
        .findAll('[role="group"] button')
        .find(botao => botao.text() === 'CRM_KANBAN.VIEWS.CALENDAR');

    afterEach(() => {
      route.query = {};
      route.params = {};
      push.mockClear();
      replace.mockClear();
      wrapper?.unmount();
    });

    it('leva ao Meu dia em vez de abrir o calendário antigo', async () => {
      route.params = { accountId: '18' };
      wrapper = await mountPage({ account: { calendarioOuro: true } });
      await botaoCalendario(wrapper).trigger('click');
      expect(push).toHaveBeenCalledWith({
        name: 'crm_calendar_index',
        params: { accountId: '18' },
        query: {},
      });
      expect(wrapper.findComponent({ name: 'CrmCalendar' }).exists()).toBe(
        false
      );
    });

    it('?view=calendar com o menu novo também vai para o Meu dia', async () => {
      route.params = { accountId: '18' };
      route.query = { view: 'calendar' };
      wrapper = await mountPage({
        account: { calendarioOuro: true, menuNovo: true },
      });
      expect(replace).toHaveBeenCalledWith({
        name: 'crm_calendar_index',
        params: { accountId: '18' },
        query: {},
      });
    });

    it('flag do Meu dia que chega depois da tela: vai para o Meu dia sem buscar o calendário antigo', async () => {
      route.params = { accountId: '18' };
      route.query = { view: 'calendar', new_contact_id: '7' };
      wrapper = await mountPage({ account: { menuNovo: true } });
      dispatch.mockClear();
      storeGetters['accounts/getAccount'].value = () => ({
        id: 1,
        features: { crm_calendario_ouro: true },
      });
      await flushPromises();
      expect(replace).toHaveBeenLastCalledWith({
        name: 'crm_calendar_index',
        params: { accountId: '18' },
        query: { new_contact_id: '7' },
      });
      expect(
        dispatch.mock.calls.filter(
          ([tipo]) => tipo === 'crmKanban/fetchCalendarEvents'
        )
      ).toHaveLength(0);
    });

    it('navegação recusada volta ao quadro', async () => {
      route.params = { accountId: '18' };
      push.mockResolvedValueOnce({ type: 4 });
      wrapper = await mountPage({ account: { calendarioOuro: true } });
      await botaoCalendario(wrapper).trigger('click');
      await flushPromises();
      expect(wrapper.find('[role="group"] [aria-pressed="true"]').text()).toBe(
        'CRM_KANBAN.VIEWS.KANBAN'
      );
    });

    it('sem o Meu dia, a aba abre o calendário de sempre', async () => {
      route.params = { accountId: '18' };
      wrapper = await mountPage();
      await botaoCalendario(wrapper).trigger('click');
      expect(push).not.toHaveBeenCalled();
    });
  });

  // #1883 — os "Ver" do Números abrem o Kanban, a Lista e o Meu dia já filtrados, com o filtro à vista.
  describe('filtros que chegam pelo link', () => {
    const filtrosGravados = () =>
      dispatch.mock.calls.filter(([type]) => type === 'crmKanban/setFilters');
    const ultimoFiltro = () => filtrosGravados().at(-1)[1];

    afterEach(() => {
      route.query = {};
      delete route.name;
      replace.mockClear();
      dispatch.mockClear();
      wrapper?.unmount();
    });

    it('Kanban: parado há mais de 7 dias e responsável = eu, com os chips e o endereço limpo', async () => {
      route.name = 'crm_kanban_index';
      route.query = { pipeline_id: '1', stale_days: '7', owner_id: 'me' };
      wrapper = await mountPage();

      expect(ultimoFiltro()).toMatchObject({ staleDays: '7', ownerId: 1 });
      const texto = wrapper.text();
      expect(texto).toContain('CRM_KANBAN.FILTERS.STALE');
      expect(texto).toContain('CRM_KANBAN.FILTERS.OWNER');
      expect(texto).toContain('CRM_KANBAN.ACTIONS.CLEAR_FILTERS');
      expect(replace).toHaveBeenLastCalledWith({ query: {} });
    });

    it('Kanban: pessoa que a tela não conhece não vira filtro', async () => {
      route.name = 'crm_kanban_index';
      route.query = { stale_days: '7', owner_id: '99' };
      wrapper = await mountPage({
        account: {
          agents: [
            { id: 1, name: 'Eu' },
            { id: 2, name: 'Ana' },
          ],
        },
      });

      expect(ultimoFiltro()).toMatchObject({ staleDays: '7', ownerId: '' });
      expect(wrapper.text()).not.toContain('CRM_KANBAN.FILTERS.OWNER');
    });

    it('Kanban: sem a equipe carregada, o dono do link fica', async () => {
      route.name = 'crm_kanban_index';
      route.query = { owner_id: '2' };
      wrapper = await mountPage();

      expect(ultimoFiltro()).toMatchObject({ ownerId: 2 });
    });

    it('Lista: ganhos do mês sem responsável, com o chip do mês', async () => {
      route.name = 'crm_kanban_index';
      route.query = {
        view: 'list',
        result: 'won',
        closed_in: 'this_month',
        responsible_kind: 'none',
      };
      wrapper = await mountPage({ account: { menuNovo: true } });

      expect(ultimoFiltro()).toMatchObject({
        result: 'won',
        closedIn: 'this_month',
        responsibleKind: 'none',
      });
      expect(wrapper.text()).toContain('CRM_FILTRO_DO_LINK.FECHADO_NO_MES');
      expect(replace).toHaveBeenLastCalledWith({ query: { view: 'list' } });
    });

    // #2150 — sem crm_manage_ai o servidor ignora "Pendente de IA": o chip não finge que o filtro vale.
    it('o chip "Pendente de IA" só aparece com crm_manage_ai', async () => {
      route.name = 'crm_kanban_index';
      route.query = { pipeline_id: '1' };
      const account = { filters: { aiPending: true } };
      wrapper = await mountPage({ account });
      expect(wrapper.text()).toContain('CRM_KANBAN.FILTERS.AI_PENDING');
      wrapper.unmount();

      wrapper = await mountPage({ account, perms: { canManageAi: false } });
      expect(wrapper.text()).not.toContain('CRM_KANBAN.FILTERS.AI_PENDING');
    });

    it('sem filtro no link, a sessão segue com o filtro que já tinha', async () => {
      route.name = 'crm_kanban_index';
      route.query = { pipeline_id: '1' };
      wrapper = await mountPage();

      expect(filtrosGravados()).toHaveLength(0);
    });

    it('Meu dia: quem, tipos e funil vão para o calendário; funil fora do acesso não', async () => {
      route.name = 'crm_calendar_index';
      route.query = { quem: 'todos', tipos: 'lembrete', funil: '1' };
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      const calendario = wrapper.findComponent({ name: 'CalendarioOuro' });
      expect(calendario.props('filtroInicial')).toEqual({
        quem: 'todos',
        tipos: ['lembrete'],
        funil: '1',
      });
      expect(calendario.props('funil')).toBe(1);
      expect(replace).toHaveBeenLastCalledWith({ query: {} });
      // O filtro do Kanban (de outra visita) não vira filtro escondido do Meu dia.
      const busca = dispatch.mock.calls.filter(
        ([tipo]) => tipo === 'crmKanban/fetchCalendarEvents'
      );
      expect(busca.at(-1)[1]).toMatchObject({
        pipeline_id: 1,
        semFiltrosDoQuadro: true,
      });
      wrapper.unmount();

      route.query = { funil: '5' };
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      expect(
        wrapper.findComponent({ name: 'CalendarioOuro' }).props('funil')
      ).toBeNull();
    });
  });

  // #1385 — a passagem volta para o Kanban no funil de onde a pessoa saiu.
  describe('passagem para a equipe', () => {
    afterEach(() => {
      route.query = {};
      delete route.name;
      push.mockClear();
      replace.mockClear();
    });

    it('abre a passagem com from=crm e guarda o funil no endereço do quadro', async () => {
      window.globalConfig.CRM_AI_ENABLED = 'true';
      wrapper = await mountPage();
      replace.mockClear();
      await openConfiguration(wrapper);
      Array.from(document.body.querySelectorAll('button'))
        .find(
          b => b.textContent.trim() === 'CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS'
        )
        .click();
      await flushPromises();

      expect(replace).toHaveBeenCalledWith({ query: { pipeline_id: '1' } });
      // O funil fica no endereço do quadro antes de sair (voltar do navegador).
      expect(replace.mock.invocationCallOrder[0]).toBeLessThan(
        push.mock.invocationCallOrder[0]
      );
      expect(push).toHaveBeenCalledWith({
        name: 'crm_handoff_settings_edit',
        params: { pipelineId: 1 },
        query: { from: 'crm' },
      });
    });

    it('com ?pipeline_id= abre nesse funil e tira o parâmetro do endereço', async () => {
      const outro = { id: 2, name: 'Pós-venda' };
      dispatch.mockImplementation(async type =>
        type === 'crmKanban/fetchPipelines' ? [PIPELINE, outro] : []
      );
      route.name = 'crm_kanban_index';
      route.query = { pipeline_id: '2', card_id: '9' };
      wrapper = await mountPage();

      expect(dispatch).toHaveBeenCalledWith('crmKanban/loadListPrefs', 2);
      expect(replace).toHaveBeenCalledWith({ query: { card_id: '9' } });
    });
  });

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    dispatch.mockImplementation(async type =>
      type === 'crmKanban/fetchPipelines' ? [PIPELINE] : []
    );
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    document.body.innerHTML = '';
    delete window.globalConfig;
  });

  // #1568: com a flag, o calendário abre o "Meu dia" sem o topo antigo e
  // busca todos os funis; sem ela, nada muda (os testes acima e abaixo).
  describe('Calendário Meu dia (crm_calendario_ouro)', () => {
    it('com a flag, abre a tela nova sem o topo antigo e sem exigir funil', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });

      expect(wrapper.findComponent({ name: 'CalendarioOuro' }).exists()).toBe(
        true
      );
      expect(wrapper.findComponent({ name: 'CrmCalendar' }).exists()).toBe(
        false
      );
      expect(wrapper.find('header').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('CRM_KANBAN.ACTIONS.CONFIGURE');

      wrapper
        .findComponent({ name: 'CalendarioOuro' })
        .vm.$emit('rangeChange', { from: 'a', to: 'b' });
      await flushPromises();
      const busca = dispatch.mock.calls.filter(
        ([tipo]) => tipo === 'crmKanban/fetchCalendarEvents'
      );
      expect(busca.at(-1)[1].pipeline_id).toBeUndefined();
    });

    const ouro = () => wrapper.findComponent({ name: 'CalendarioOuro' });

    it('Mensagem marcada só com WhatsApp que não pede para reconectar', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: {
          calendarioOuro: true,
          inboxes: [
            {
              channel_type: 'Channel::Whatsapp',
              reauthorization_required: true,
            },
          ],
        },
      });
      expect(ouro().props('temWhatsapp')).toBe(false);
      wrapper.unmount();

      wrapper = await mountPage({
        calendarOnly: true,
        account: {
          calendarioOuro: true,
          inboxes: [
            {
              channel_type: 'Channel::Whatsapp',
              reauthorization_required: false,
            },
          ],
        },
      });
      expect(ouro().props('temWhatsapp')).toBe(true);
    });

    it('concluir que falha devolve a linha e avisa', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      dispatch.mockImplementation(async tipo => {
        if (tipo === 'crmKanban/completeFollowUp') throw new Error('falhou');
        return [];
      });
      const falhou = vi.fn();
      ouro().vm.$emit('concluir', { evento: { id: 'follow_up_5' }, falhou });
      await flushPromises();

      expect(dispatch).toHaveBeenCalledWith('crmKanban/completeFollowUp', '5');
      expect(falhou).toHaveBeenCalled();
      expect(useAlert).toHaveBeenCalledWith(
        'CRM_CALENDARIO.ALERTA.NAO_CONCLUIU'
      );
    });

    it('"Passar os meus" diz quantos passaram quando parte falha', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      dispatch.mockImplementation(async (tipo, carga) => {
        if (tipo === 'crmKanban/rescheduleFollowUp' && carga.id === '2')
          throw new Error('falhou');
        return [];
      });
      ouro().vm.$emit('adiarAtrasados', {
        eventos: [
          { id: 'follow_up_1' },
          { id: 'follow_up_2' },
          { id: 'follow_up_3' },
        ],
        quando: '2026-10-15T12:00:00.000Z',
      });
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        'CRM_CALENDARIO.ALERTA.ADIADOS_PARCIAL:{"ok":2,"total":3}'
      );
    });

    // #1855: o lote pede ao servidor só lembretes; envio ao cliente é recusado.
    it('"Passar os meus" pede o reagendamento só de lembretes', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      dispatch.mockClear();
      ouro().vm.$emit('adiarAtrasados', {
        eventos: [{ id: 'follow_up_1' }],
        quando: '2026-10-15T12:00:00.000Z',
      });
      await flushPromises();

      expect(dispatch).toHaveBeenCalledWith('crmKanban/rescheduleFollowUp', {
        id: '1',
        dueAt: '2026-10-15T12:00:00.000Z',
        remindersOnly: true,
      });
    });

    it('reunião marcada no Meu dia avisa e recarrega o calendário', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      dispatch.mockClear();
      ouro().vm.$emit('reuniaoMarcada', { id: 1 });
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        'CRM_KANBAN.BOOKING_AGENDA.SUCCESS'
      );
      expect(dispatch).toHaveBeenCalledWith(
        'crmKanban/fetchCalendarEvents',
        expect.any(Object)
      );
      expect(
        wrapper
          .findComponent({ name: 'CrmCalendarMeetingScheduler' })
          .props('show')
      ).toBe(false);
    });

    it('as configurações do topo antigo continuam no Mostrar', async () => {
      wrapper = await mountPage({
        calendarOnly: true,
        account: { calendarioOuro: true },
      });
      expect(ouro().props('podeCaixas')).toBe(true);
      expect(ouro().props('podeAgendamento')).toBe(true);

      ouro().vm.$emit('abrirAgendamento');
      await flushPromises();
      expect(
        wrapper
          .findComponent({ name: 'CrmBookingProfilesDrawer' })
          .props('show')
      ).toBe(true);
    });

    it('sem a flag, o calendário continua o de sempre', async () => {
      wrapper = await mountPage({ calendarOnly: true });

      expect(wrapper.findComponent({ name: 'CalendarioOuro' }).exists()).toBe(
        false
      );
      expect(wrapper.findComponent({ name: 'CrmCalendar' }).exists()).toBe(
        true
      );
    });

    it('com a flag, só a página do calendário muda; o Kanban não', async () => {
      wrapper = await mountPage({ account: { calendarioOuro: true } });

      expect(wrapper.findComponent({ name: 'CalendarioOuro' }).exists()).toBe(
        false
      );
      expect(wrapper.text()).toContain('CRM_KANBAN.ACTIONS.CONFIGURE');
    });
  });

  it('keeps inbox settings in the Agenda, without funnel actions', async () => {
    wrapper = await mountPage({ calendarOnly: true });

    const text = await openConfiguration(wrapper);

    expect(text).toContain('CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT');
    expect(text).toContain('CRM_KANBAN.ACTIONS.INBOX_SETTINGS');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.EDIT_PIPELINE');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS');
  });

  it('opens the booking profiles drawer from the Agenda', async () => {
    wrapper = await mountPage({ calendarOnly: true });
    await openConfiguration(wrapper);

    const booking = Array.from(document.body.querySelectorAll('button')).find(
      button =>
        button.textContent.trim() === 'CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT'
    );
    booking.click();
    await flushPromises();

    expect(
      wrapper.findComponent({ name: 'CrmBookingProfilesDrawer' }).props('show')
    ).toBe(true);
  });

  // Botão Agendamento do Calendário (#1212).
  const bookingButton = () =>
    Array.from(document.body.querySelectorAll('button')).find(
      button =>
        button.textContent.trim() === 'CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT'
    );
  const drawerShown = () =>
    wrapper.findComponent({ name: 'CrmBookingProfilesDrawer' }).props('show');

  it('com o agendamento novo ligado, o botão leva à página nova e não abre a gaveta', async () => {
    push.mockClear();
    wrapper = await mountPage({
      calendarOnly: true,
      account: { bookingV2: true },
    });

    bookingButton().click();
    await flushPromises();

    expect(push).toHaveBeenCalledWith({
      name: 'settings_booking',
      params: { accountId: 1 },
    });
    expect(drawerShown()).toBe(false);
  });

  it.each(['agendamento_view', 'agendamento_manage'])(
    'com o agendamento novo, função com %s vê o botão mesmo sem gerenciar funis',
    async key => {
      wrapper = await mountPage({
        calendarOnly: true,
        perms: { canManagePipelines: false },
        account: { bookingV2: true, role: 'agent', keys: [key] },
      });
      expect(bookingButton()).toBeDefined();
    }
  );

  it('com o agendamento novo, quem não pode ver a página não vê o botão', async () => {
    wrapper = await mountPage({
      calendarOnly: true,
      account: { bookingV2: true, role: 'agent', keys: ['crm_view'] },
    });
    expect(bookingButton()).toBeUndefined();
  });

  it('com o agendamento novo desligado, segue a gaveta antiga para quem gerencia funis, e só', async () => {
    push.mockClear();
    wrapper = await mountPage({
      calendarOnly: true,
      account: { role: 'agent', keys: ['agendamento_manage'] },
    });
    bookingButton().click();
    await flushPromises();
    expect(drawerShown()).toBe(true);
    expect(push).not.toHaveBeenCalled();
    wrapper.unmount();

    wrapper = await mountPage({
      calendarOnly: true,
      perms: { canManagePipelines: false },
      account: { role: 'agent', keys: ['agendamento_manage'] },
    });
    expect(bookingButton()).toBeUndefined();
  });

  it('shows funnel actions on the Kanban configuration menu', async () => {
    wrapper = await mountPage();

    const text = await openConfiguration(wrapper);

    expect(text).not.toContain('CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT');
    expect(text).toContain('CRM_KANBAN.ACTIONS.EDIT_PIPELINE');
    expect(text).toContain('CRM_KANBAN.ACTIONS.INBOX_SETTINGS');
  });

  it('disables drag and hides Move without the move permission', async () => {
    wrapper = await mountPage({ perms: { canMoveCards: false } });

    const boards = wrapper.findAll('[data-test-draggable]');
    expect(boards.length).toBe(STAGES.length);
    boards.forEach(board => {
      expect(board.attributes('data-disabled')).toBe('true');
    });
    expect(wrapper.find('[data-crm-card-move]').exists()).toBe(false);
  });

  it('enables drag with the move permission', async () => {
    wrapper = await mountPage();

    wrapper.findAll('[data-test-draggable]').forEach(board => {
      expect(board.attributes('data-disabled')).toBe('false');
    });
  });

  it('confirms the open card drafts before switching to another card', async () => {
    const guardNavigation = vi.fn(action => action());
    dispatch.mockImplementation(async (type, payload) => {
      if (type === 'crmKanban/fetchPipelines') return [PIPELINE];
      if (type === 'crmKanban/fetchCard') return { id: payload };
      return [];
    });
    const DrawerStub = {
      setup(_, { expose }) {
        expose({ guardNavigation });
        return () => h('div');
      },
    };
    wrapper = await mountPage({ stubs: { CardGaveta: DrawerStub } });
    const openButtons = () =>
      wrapper
        .findAll('button')
        .filter(button =>
          (button.attributes('aria-label') || '').startsWith(
            'CRM_KANBAN.CARD.OPEN_DETAILS'
          )
        );
    expect(openButtons()).toHaveLength(2);

    await openButtons()[0].trigger('click');
    await flushPromises();
    await openButtons()[0].trigger('click');
    await flushPromises();
    expect(guardNavigation).not.toHaveBeenCalled();

    await openButtons()[1].trigger('click');
    await flushPromises();
    expect(guardNavigation).toHaveBeenCalledWith(expect.any(Function), {
      leaving: true,
    });
  });
});

// The drawer uses the existing move endpoint, separate from commercial edits.
it('moves the selected card from details without overwriting its title', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10, title: 'Current title' };
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).toHaveBeenCalledWith('crmKanban/moveCard', {
    cardId: 100,
    stageId: 11,
  });
  expect(wrapper.vm.selectedCard).toMatchObject({
    stage_id: 11,
    title: 'Current title',
  });
  wrapper.unmount();
});

it('does not move from details without movement permission', async () => {
  const wrapper = await mountPage({ perms: { canMoveCards: false } });
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  dispatch.mockClear();
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).not.toHaveBeenCalledWith(
    'crmKanban/moveCard',
    expect.anything()
  );
  wrapper.unmount();
});

it('keeps the current stage when the move request fails', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  dispatch.mockRejectedValueOnce(new Error('Move failed'));
  await wrapper.vm.moveCardFromDetails(11);
  expect(wrapper.vm.selectedCard.stage_id).toBe(10);
  wrapper.unmount();
});

it('loads all authorized stages for card details independently of board filters', async () => {
  const wrapper = await mountPage({ calendarOnly: true });
  dispatch.mockImplementation(async (type, payload) => {
    if (type === 'crmKanban/fetchCard')
      return { id: payload, pipeline_id: 1, stage_id: 10 };
    if (type === 'crmKanban/fetchPipelineStages') return STAGES;
    return [];
  });
  storeGetters['crmKanban/getStages'].value = [];
  await wrapper.vm.openCardDrawer({ id: 100 });
  expect(dispatch).toHaveBeenCalledWith('crmKanban/fetchPipelineStages', 1);
  expect(
    wrapper.findComponent({ name: 'CardGaveta' }).attributes('stages')
  ).toBeTruthy();
  expect(wrapper.vm.cardDrawerStages).toEqual(STAGES);
  wrapper.unmount();
});

it('abre o card pedido pelo alerta do agendamento com o quadro já aberto', async () => {
  const wrapper = await mountPage();
  const [, openCard] = useEmitter.mock.calls.findLast(
    ([eventName]) => eventName === 'CRM_OPEN_CARD'
  );
  dispatch.mockImplementation(async (type, payload) =>
    type === 'crmKanban/fetchCard' ? { id: payload, pipeline_id: 1 } : []
  );

  openCard(42);
  await flushPromises();

  expect(dispatch).toHaveBeenCalledWith('crmKanban/fetchCard', 42);
  expect(wrapper.vm.selectedCard).toMatchObject({ id: 42 });
  wrapper.unmount();
});

it('refreshes the messaging window and shows the template alert when creating a follow-up fails that validation', async () => {
  const refreshMessagingWindow = vi.fn();
  const DrawerStub = {
    setup(_, { expose }) {
      expose({ refreshMessagingWindow });
      return () => h('div');
    },
  };
  const wrapper = await mountPage({ stubs: { CardGaveta: DrawerStub } });
  wrapper.vm.selectedCard = { id: 7 };
  dispatch.mockImplementation(async type => {
    if (type === 'crmKanban/createFollowUp') {
      const error = new Error('Validation failed');
      error.response = {
        data: {
          message:
            'Metadata template fallback is required outside the messaging window',
          attributes: ['metadata'],
          code: 'template_fallback_required',
        },
      };
      throw error;
    }
    return [];
  });

  await wrapper.vm.createFollowUp({ card_id: 7, title: 'Retomar' });

  expect(refreshMessagingWindow).toHaveBeenCalledOnce();
  expect(useAlert).toHaveBeenCalledWith(
    'CRM_KANBAN.ALERTS.FOLLOW_UP_TEMPLATE_REQUIRED'
  );
  wrapper.unmount();
});

it('explains a past auto-send time without the raw Rails message', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 7 };
  dispatch.mockImplementation(async type => {
    if (type === 'crmKanban/createFollowUp') {
      const error = new Error('Validation failed');
      error.response = {
        data: {
          message: 'Due at must be in the future for auto-send follow-ups',
          attributes: ['due_at'],
          code: 'due_at_in_the_past',
        },
      };
      throw error;
    }
    return [];
  });

  await wrapper.vm.createFollowUp({ card_id: 7, title: 'Retomar' });

  expect(useAlert).toHaveBeenCalledWith(
    'CRM_KANBAN.ALERTS.FOLLOW_UP_DUE_AT_PAST'
  );
  wrapper.unmount();
});

it('shows the raw API message for any other follow-up creation failure', async () => {
  const refreshMessagingWindow = vi.fn();
  const DrawerStub = {
    setup(_, { expose }) {
      expose({ refreshMessagingWindow });
      return () => h('div');
    },
  };
  const wrapper = await mountPage({ stubs: { CardGaveta: DrawerStub } });
  wrapper.vm.selectedCard = { id: 7 };
  dispatch.mockImplementation(async type => {
    if (type === 'crmKanban/createFollowUp') {
      const error = new Error('Validation failed');
      error.response = { data: { message: 'conversation is required' } };
      throw error;
    }
    return [];
  });

  await wrapper.vm.createFollowUp({ card_id: 7, title: 'Retomar' });

  expect(refreshMessagingWindow).not.toHaveBeenCalled();
  expect(useAlert).toHaveBeenCalledWith('conversation is required');
  wrapper.unmount();
});

it('does not start another move while a card is moving', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  storeGetters['crmKanban/getUIFlags'].value = { isMovingCard: true };
  dispatch.mockClear();
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).not.toHaveBeenCalledWith(
    'crmKanban/moveCard',
    expect.anything()
  );
  wrapper.unmount();
});

describe('Kanban zoom integration', () => {
  let wrapper;
  beforeEach(() => {
    localStorage.clear();
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    dispatch.mockImplementation(async type =>
      type === 'crmKanban/fetchPipelines' ? [PIPELINE] : []
    );
  });
  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    document.body.innerHTML = '';
    localStorage.clear();
    delete window.globalConfig;
  });

  it.each([70, 80, 87, 90, 100, 110, 117, 120, 130])(
    'scales only the board at %i without rebuilding cards or refetching data',
    async value => {
      wrapper = await mountPage();
      const board = wrapper.get('[data-kanban-board]').element;
      const column = wrapper.get('[data-stage-id="10"]').element;
      const header = wrapper.get('main > header').element;
      dispatch.mockClear();
      wrapper.findComponent(CrmKanbanZoom).vm.$emit('update:modelValue', value);
      await flushPromises();
      expect(wrapper.get('[data-kanban-board]').classes()).toContain(
        KANBAN_ZOOM_CLASSES[value]
      );
      expect(wrapper.get('[data-kanban-board]').element).toBe(board);
      expect(wrapper.get('[data-stage-id="10"]').element).toBe(column);
      expect(wrapper.get('main > header').element).toBe(header);
      expect(header.className).not.toContain('[zoom:');
      expect(wrapper.get('main').classes()).toContain('w-full');
      expect(wrapper.get('[data-card-id]').classes()).toContain(
        KANBAN_ZOOM_DRAG_CLASSES[value]
      );
      expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(
        value
      );
      expect(dispatch).not.toHaveBeenCalled();
      wrapper.findAll('[data-test-draggable]').forEach(list => {
        expect(list.attributes('sort')).toBe('false');
        expect(list.attributes('fallback-on-body')).toBe('true');
        expect(list.attributes('force-fallback')).toBe('true');
        expect(list.attributes('fallback-tolerance')).toBe('4');
        expect(list.attributes('scroll')).toBe('false');
        expect(list.attributes('fallback-class')).toBe(
          'crm-kanban-drag-preview'
        );
      });
      wrapper.vm.onDragStart();
      await wrapper.vm.onDragChange(STAGES[1], {
        added: { element: STAGES[0].cards[0] },
      });
      expect(dispatch).toHaveBeenCalledWith('crmKanban/moveCard', {
        cardId: 100,
        stageId: 11,
      });
    }
  );

  it.each(['list', 'calendar'])(
    'keeps the exact preference through %s without scaling it',
    async mode => {
      wrapper = await mountPage();
      wrapper.vm.setZoom(87);
      wrapper.vm.setViewMode(mode);
      await flushPromises();
      expect(wrapper.findComponent(CrmKanbanZoom).exists()).toBe(false);
      expect(wrapper.find('[data-kanban-board]').exists()).toBe(false);
      expect(
        wrapper
          .findAll('[class]')
          .some(node => node.attributes('class').includes('[zoom:'))
      ).toBe(false);
      wrapper.vm.setViewMode('kanban');
      await flushPromises();
      expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(87);
    }
  );

  // #1874 — ação em massa por permissão: cada botão só para quem pode; sem nenhuma, a lista não tem seleção.
  it('quem só vê o CRM não tem seleção na lista', async () => {
    wrapper = await mountPage({
      perms: {
        canManageCards: false,
        canMoveCards: false,
        canDeleteCards: false,
      },
    });
    wrapper.vm.setViewMode('list');
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'CrmCardsTable' }).props('selectable')
    ).toBe(false);
  });

  it('quem mexe sem arquivar não vê o Arquivar em massa', async () => {
    wrapper = await mountPage({ perms: { canDeleteCards: false } });
    wrapper.vm.setViewMode('list');
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'CrmCardsTable' }).props('selectable')
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'CrmBulkActionBar' }).props('permissions')
    ).toEqual({ move: true, assign: true, status: true, archive: false });
  });

  it('restores the exact percentage after leaving and mounting the CRM again', async () => {
    wrapper = await mountPage();
    wrapper.vm.setZoom(87);
    wrapper.unmount();
    wrapper = await mountPage();
    expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(87);
  });

  it('preserves the account direction on cards cloned outside the app', async () => {
    wrapper = await mountPage();
    expect(wrapper.get('[data-card-id]').attributes('dir')).toBe('ltr');
    storeGetters['accounts/isRTL'].value = true;
    await flushPromises();
    expect(wrapper.get('[data-card-id]').attributes('dir')).toBe('rtl');
  });

  it('suppresses the trailing click after dragging, not a fresh pointer click', async () => {
    wrapper = await mountPage();
    const target = wrapper.get('[data-card-id]').element;
    const clicked = vi.fn();
    target.addEventListener('click', clicked);
    wrapper.vm.onDragStart();
    const trailing = new MouseEvent('click', {
      bubbles: true,
      cancelable: true,
      detail: 1,
    });
    target.dispatchEvent(trailing);
    expect(trailing.defaultPrevented).toBe(true);
    expect(clicked).not.toHaveBeenCalled();
    target.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 1 }));
    expect(clicked).toHaveBeenCalledOnce();
  });

  it('preserves keyboard activation after an abandoned drag', async () => {
    wrapper = await mountPage();
    const target = wrapper.get('[data-card-id]').element;
    const clicked = vi.fn();
    target.addEventListener('click', clicked);
    wrapper.vm.onDragStart();
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 0 }));
    expect(clicked).toHaveBeenCalledOnce();
  });

  it('keeps zoom across funnels and never exposes the control on the Agenda-only route', async () => {
    wrapper = await mountPage();
    wrapper.vm.setZoom(83);
    storeGetters['crmKanban/getPipelines'].value = [
      PIPELINE,
      { id: 2, name: 'Outro funil' },
    ];
    wrapper.vm.currentPipelineId = 2;
    await flushPromises();
    expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(83);
    wrapper.unmount();
    wrapper = await mountPage({ calendarOnly: true });
    expect(wrapper.findComponent(CrmKanbanZoom).exists()).toBe(false);
  });
});
