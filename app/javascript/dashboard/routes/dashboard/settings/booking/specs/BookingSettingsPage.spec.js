import { config, flushPromises, mount } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { canManage } from 'dashboard/composables/useCanManage';
import { canViewCrm } from 'dashboard/routes/dashboard/crm/composables/useCrmPermissions';
import BookingSettingsPage from '../BookingSettingsPage.vue';

// A tela inteira por perfil (#1187, J8): quem gerencia cria e edita; quem só
// vê abre a página em modo leitura, sem nenhum botão que mude algo.
// `locale` e `mergeLocaleMessage`: a prévia monta as telas da página pública (#1289).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    locale: { value: 'pt_BR' },
    mergeLocaleMessage: () => {},
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
// `route.query` muda por teste (link direto do #1371); `router` grava a saída.
const { route, router } = vi.hoisted(() => ({
  route: { name: 'settings_booking', params: { accountId: '1' }, query: {} },
  router: { push: vi.fn(), replace: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => router,
}));

// "Voltar para o calendário" (#1212) só aparece para quem abre o Calendário.
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { ref } = await import('vue');
    const flag = ref(true);
    return {
      useCrmPermissions: () => ({ canViewCrm: flag }),
      canViewCrm: flag,
    };
  }
);

// As abas "Páginas" e "Resultados" (#1194) são links do roteador.
config.global.stubs = {
  RouterLink: { props: ['to'], template: '<a :data-to="to.name"><slot /></a>' },
};
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref } = await import('vue');
  const flag = ref(true);
  return {
    useCanManage: key => (key === 'agendamento_manage' ? flag : ref(false)),
    canManage: flag,
  };
});
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { get: vi.fn(), show: vi.fn(), people: vi.fn() },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getPipelines: vi.fn(), getStages: vi.fn() },
}));

const page = {
  id: 5,
  title: 'Conversa de vendas',
  enabled: true,
  public_url: 'https://chat.exemplo.com/book/x',
  duration_minutes: 30,
  slot_durations: [],
  locations: [{ type: 'whatsapp_video' }],
  working_hours: { start_hour: 9, end_hour: 17, weekdays: [1, 2, 3] },
  brand: {},
  people: [{ id: 1, name: 'Maria' }],
  default_pipeline_id: 3,
  default_stage_id: 30,
  calendar_options: [],
};

describe('BookingSettingsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    route.query = {};
    canManage.value = true;
    canViewCrm.value = true;
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [page] } });
    BookingPagesAPI.show.mockResolvedValue({ data: { payload: page } });
    BookingPagesAPI.people.mockResolvedValue({ data: { payload: [] } });
    CrmKanbanAPI.getPipelines.mockResolvedValue({
      data: { payload: [{ id: 3, name: 'Vendas' }] },
    });
    CrmKanbanAPI.getStages.mockResolvedValue({
      data: { payload: [{ id: 30, name: 'Nova' }] },
    });
  });

  it('mostra as abas Páginas e Resultados na lista e some com elas no assistente', async () => {
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    const tabs = wrapper.findAll('[data-tab]');
    expect(tabs.map(tab => tab.attributes('data-to'))).toEqual([
      'settings_booking',
      'settings_booking_results',
    ]);
    expect(tabs[0].attributes('aria-current')).toBe('page');
    expect(tabs[1].attributes('aria-current')).toBeUndefined();

    await wrapper.find('[data-create]').trigger('click');
    expect(wrapper.find('[data-tab]').exists()).toBe(false);
  });

  it('tem o Voltar para o calendário no topo da lista, e ele some no assistente', async () => {
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    const back = wrapper.find('[data-back-to-calendar]');
    expect(back.attributes('data-to')).toBe('crm_calendar_index');
    expect(back.text()).toBe('BOOKING.PAGE.BACK_TO_CALENDAR');
    expect(back.classes()).toContain('min-h-11');

    await wrapper.find('[data-create]').trigger('click');
    expect(wrapper.find('[data-back-to-calendar]').exists()).toBe(false);
  });

  it('quem não abre o Calendário não vê o Voltar para o calendário', async () => {
    canViewCrm.value = false;
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    expect(wrapper.find('[data-back-to-calendar]').exists()).toBe(false);
  });

  it('quem gerencia cria uma página pelo assistente', async () => {
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    await wrapper.find('[data-create]').trigger('click');
    expect(wrapper.find('[data-wizard]').exists()).toBe(true);
    expect(wrapper.findAll('[data-template]')).toHaveLength(4);
  });

  it('quem gerencia edita: o assistente abre no passo 2 da página', async () => {
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    await wrapper.find('[data-edit]').trigger('click');
    await flushPromises();
    expect(BookingPagesAPI.show).toHaveBeenCalledWith(5);
    expect(wrapper.find('[aria-current="step"]').attributes('data-step')).toBe(
      'CONTE'
    );
  });

  it('quem só vê abre a página em leitura, sem botão de escrita', async () => {
    canManage.value = false;
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    expect(wrapper.find('[data-edit]').exists()).toBe(false);
    await wrapper.find('[data-view]').trigger('click');
    await flushPromises();
    const view = wrapper.find('[data-page-view]');
    expect(view.exists()).toBe(true);
    expect(view.find('[data-preview] [data-brand-header]').text()).toContain(
      'Conversa de vendas'
    );
    expect(view.find('[data-alter]').exists()).toBe(false);
    expect(view.find('[data-primary]').exists()).toBe(false);
    expect(view.find('[data-copy]').exists()).toBe(true);
    await view.find('[data-back]').trigger('click');
    expect(wrapper.find('[data-page]').exists()).toBe(true);
  });

  it('em leitura, página com um link por pessoa mostra o link de cada pessoa', async () => {
    canManage.value = false;
    const perPerson = {
      ...page,
      assignment_mode: 'per_agent',
      public_url: null,
      links: [
        {
          agent_id: 11,
          agent_name: 'Bia',
          url: 'https://chat.exemplo.com/book/bia',
          enabled: true,
        },
      ],
    };
    BookingPagesAPI.get.mockResolvedValue({ data: { payload: [perPerson] } });
    BookingPagesAPI.show.mockResolvedValue({ data: { payload: perPerson } });
    const wrapper = mount(BookingSettingsPage);
    await flushPromises();
    await wrapper.find('[data-view]').trigger('click');
    await flushPromises();
    const view = wrapper.find('[data-page-view]');
    expect(view.text()).not.toContain('/book/x');
    const rows = view.findAll('[data-person-link]');
    expect(rows).toHaveLength(1);
    expect(rows[0].find('[data-link-url]').text()).toBe(
      'https://chat.exemplo.com/book/bia'
    );
  });

  // Link direto para o assistente de página nova (#1371), usado pela gaveta
  // "Marcar reuniões" do agente de IA.
  describe('?nova=1 e ?voltar=', () => {
    const AGENT = '/app/accounts/1/autonomia/agentes/7?gaveta=reunioes';

    it('nova=1 abre o assistente de página nova, sem a lista', async () => {
      route.query = { nova: '1' };
      const wrapper = mount(BookingSettingsPage);
      await flushPromises();
      expect(wrapper.find('[data-wizard]').exists()).toBe(true);
      expect(wrapper.find('[data-template]').exists()).toBe(true);
      expect(wrapper.find('[data-page]').exists()).toBe(false);
    });

    it('sem permissão de gerenciar, nova=1 abre a lista normalmente', async () => {
      canManage.value = false;
      route.query = { nova: '1', voltar: AGENT };
      const wrapper = mount(BookingSettingsPage);
      await flushPromises();
      expect(wrapper.find('[data-wizard]').exists()).toBe(false);
      expect(wrapper.find('[data-page]').exists()).toBe(true);
    });

    it('com voltar válido, sair do assistente diz só Voltar e leva para ele', async () => {
      route.query = { nova: '1', voltar: AGENT };
      const wrapper = mount(BookingSettingsPage);
      await flushPromises();
      const back = wrapper.find('[data-back]');
      expect(back.text()).toBe('BOOKING.WIZARD.BACK');
      await back.trigger('click');
      expect(router.push).toHaveBeenCalledWith(AGENT);
      expect(router.replace).not.toHaveBeenCalled();
    });

    it.each([
      ['endereço externo', 'https://evil.example.com/app/accounts/1/'],
      ['sem esquema, com //', '//evil.example.com/app/accounts/1/'],
      ['outra conta', '/app/accounts/2/crm/booking'],
      ['// no meio', '/app/accounts/1//evil.example.com'],
      ['barra invertida', '/app/accounts/1/\\evil.example.com'],
      ['fora do painel', '/super_admin'],
      ['.. para outra conta', '/app/accounts/1/../2/crm/kanban'],
      ['.. para fora do painel', '/app/accounts/1/../../../super_admin'],
      ['%2e%2e codificado', '/app/accounts/1/%2e%2e/2/crm/kanban'],
      ['tab', '/app/accounts/1/crm/\tkanban'],
      ['quebra de linha', '/app/accounts/1/crm/\nkanban'],
      ['voltar como lista', ['/app/accounts/1/crm/kanban']],
      ['o próprio Agendamento', '/app/accounts/1/crm/booking?nova=1'],
    ])(
      'voltar inválido (%s) é ignorado: volta para a lista e limpa a query',
      async (_case, voltar) => {
        route.query = { nova: '1', voltar, aba: 'x' };
        const wrapper = mount(BookingSettingsPage);
        await flushPromises();
        const back = wrapper.find('[data-back]');
        expect(back.text()).toBe('BOOKING.WIZARD.BACK_TO_LIST');
        await back.trigger('click');
        expect(router.push).not.toHaveBeenCalled();
        expect(router.replace).toHaveBeenCalledWith({ query: { aba: 'x' } });
        expect(wrapper.find('[data-wizard]').exists()).toBe(false);
        expect(wrapper.find('[data-page]').exists()).toBe(true);
      }
    );

    it('nova como lista não abre o assistente', async () => {
      route.query = { nova: ['1'] };
      const wrapper = mount(BookingSettingsPage);
      await flushPromises();
      expect(wrapper.find('[data-wizard]').exists()).toBe(false);
      expect(wrapper.find('[data-page]').exists()).toBe(true);
    });

    it('sem query, sair do assistente não mexe no endereço', async () => {
      const wrapper = mount(BookingSettingsPage);
      await flushPromises();
      await wrapper.find('[data-create]').trigger('click');
      const back = wrapper.find('[data-back]');
      expect(back.text()).toBe('BOOKING.WIZARD.BACK_TO_LIST');
      await back.trigger('click');
      expect(router.replace).not.toHaveBeenCalled();
      expect(router.push).not.toHaveBeenCalled();
      expect(wrapper.find('[data-page]').exists()).toBe(true);
    });
  });
});
