import { flushPromises, mount } from '@vue/test-utils';
import BookingPagesAPI from 'dashboard/api/crmBookingPages';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { canManage } from 'dashboard/composables/useCanManage';
import BookingSettingsPage from '../BookingSettingsPage.vue';

// A tela inteira por perfil (#1187, J8): quem gerencia cria e edita; quem só
// vê abre a página em modo leitura, sem nenhum botão que mude algo.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, values) =>
      values === undefined ? key : `${key} ${JSON.stringify(values)}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
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
    canManage.value = true;
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
    expect(view.find('[data-preview-title]').text()).toBe('Conversa de vendas');
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
});
