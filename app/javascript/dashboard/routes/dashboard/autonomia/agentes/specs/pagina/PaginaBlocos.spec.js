import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PaginaBlocos from '../../components/pagina/PaginaBlocos.vue';

// #1253 — linha "Marca reuniões" do resumo: frase do estado com a página salva, "Alterar" só para
// quem gerencia, e nada sem a agenda nova na conta, na cotação ou quando a API de páginas falha.
const conta = vi.hoisted(() => ({ agendaNova: true }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentAccountId: 1,
    'accounts/getAccount': () => ({
      features: { crm_booking_v2: conta.agendaNova },
    }),
  };
  return { useMapGetter: nome => computed(() => getters[nome]) };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeEscolherQuemRecebe: computed(() => false),
      crmLigado: computed(() => false),
    }),
  };
});
const paginasApi = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({ default: paginasApi }));

withFullI18n();

const PAGINAS = [
  { id: 3, title: 'Visita', enabled: true },
  { id: 5, title: 'Conversa', enabled: false },
];

const montar = async ({ agente = {}, ...props } = {}) => {
  const wrapper = mount(PaginaBlocos, {
    props: {
      agente: { id: 7, name: 'Bia', config: {}, ...agente },
      nome: 'Bia',
      podeGerenciar: true,
      ...props,
    },
  });
  await flushPromises();
  return wrapper;
};

describe('PaginaBlocos · Marca reuniões', () => {
  beforeEach(() => {
    conta.agendaNova = true;
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: PAGINAS } });
  });
  afterEach(() => {
    delete window.globalConfig;
  });

  it('says the agent does not book, and opens the drawer from "Change"', async () => {
    const wrapper = await montar();
    const linha = wrapper.find('[data-linha="agenda"]');
    expect(linha.find('h3').text()).toBe('Books meetings');
    expect(linha.text()).toContain("Bia doesn't book meetings.");
    expect(linha.find('.i-lucide-calendar-check').exists()).toBe(true);
    const alterar = wrapper.find('[data-alterar="agenda"]');
    expect(alterar.attributes('aria-label')).toBe(
      'Change how meetings are booked'
    );
    await alterar.trigger('click');
    expect(wrapper.emitted('abrir')).toEqual([['agenda']]);
  });

  it('names the saved page, read as a number, and marks a paused one', async () => {
    const wrapper = await montar({
      agente: { config: { booking_page_id: '5' } },
    });
    expect(wrapper.find('[data-linha="agenda"]').text()).toContain(
      'Bia offers times from your booking page Conversa (paused).'
    );
  });

  it('shows the line without "Change" to view-only seats', async () => {
    const wrapper = await montar({ podeGerenciar: false });
    expect(wrapper.find('[data-linha="agenda"]').exists()).toBe(true);
    expect(wrapper.find('[data-alterar="agenda"]').exists()).toBe(false);
  });

  it('has no line, and reads no pages, for the quoting agent', async () => {
    const wrapper = await montar({ cotacao: true });
    expect(wrapper.find('[data-linha="agenda"]').exists()).toBe(false);
    expect(paginasApi.get).not.toHaveBeenCalled();
  });

  it('has no line for an agent that does not take the calendar', async () => {
    const wrapper = await montar({ agente: { booking_available: false } });
    expect(wrapper.find('[data-linha="agenda"]').exists()).toBe(false);
    expect(paginasApi.get).not.toHaveBeenCalled();
  });

  it('shows nothing new with the account flag off', async () => {
    conta.agendaNova = false;
    const wrapper = await montar();
    expect(wrapper.find('[data-linha="agenda"]').exists()).toBe(false);
    expect(paginasApi.get).not.toHaveBeenCalled();
  });

  it('hides the line when the pages API answers an error', async () => {
    paginasApi.get.mockRejectedValue(new Error('403'));
    const wrapper = await montar();
    expect(wrapper.find('[data-linha="agenda"]').exists()).toBe(false);
  });
});
