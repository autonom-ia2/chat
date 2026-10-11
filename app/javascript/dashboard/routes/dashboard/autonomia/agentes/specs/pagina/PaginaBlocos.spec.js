import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PaginaBlocos from '../../components/pagina/PaginaBlocos.vue';

// #1253 — linha "Marca reuniões" do resumo: frase do estado com a página salva, "Alterar" só para
// quem gerencia, e nada sem a agenda nova na conta, na cotação ou quando a API de páginas falha.
const conta = vi.hoisted(() => ({
  agendaNova: true,
  podeAbrirAgendamento: true,
}));
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
      podeAbrirAgendamento: computed(() => conta.podeAbrirAgendamento),
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
  {
    id: 6,
    title: 'Plantão',
    enabled: true,
    assignment_mode: 'per_agent',
    links: [],
  },
  { id: 8, title: 'Retorno', enabled: true, ai_status: 'sem_responsavel' },
  {
    id: 9,
    title: 'Consulta',
    enabled: true,
    assignment_mode: 'fixed',
    attention: false,
    paused_people: [{ id: 1, name: 'Rita' }],
  },
  { id: 10, title: 'Plantão novo', enabled: true, ai_status: 'agenda_pausada' },
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
    conta.podeAbrirAgendamento = true;
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

  // #1181 (item A) — a linha diz o estado real da página salva.
  const linha = wrapper => wrapper.find('[data-linha="agenda"]');

  it('names the active saved page, read as a number, without an alert', async () => {
    const wrapper = await montar({
      agente: { config: { booking_page_id: '3' } },
    });
    expect(linha(wrapper).text()).toContain(
      'Bia offers times from the page Visita.'
    );
    expect(linha(wrapper).find('.i-lucide-triangle-alert').exists()).toBe(
      false
    );
  });

  it('says a paused page will not offer times, in amber with an icon and the pages link', async () => {
    const wrapper = await montar({
      agente: { config: { booking_page_id: 5 } },
    });
    const estado = linha(wrapper).find('[data-estado-agenda="pausada"]');
    expect(estado.text()).toContain(
      'The page Conversa is paused. Bia will pass the conversation to the team until you turn the page back on.'
    );
    expect(estado.find('p').classes()).toContain('text-n-amber-11');
    expect(estado.find('.i-lucide-triangle-alert').exists()).toBe(true);
    const link = estado.find('[data-abrir-paginas]');
    expect(link.attributes('href')).toBe('/app/settings_booking');
    expect(link.text()).toContain('Open booking pages');
  });

  it('hides the pages link from who cannot open the booking pages', async () => {
    conta.podeAbrirAgendamento = false;
    const wrapper = await montar({
      agente: { config: { booking_page_id: 5 } },
    });
    expect(linha(wrapper).find('[data-estado-agenda="pausada"]').exists()).toBe(
      true
    );
    expect(linha(wrapper).find('[data-abrir-paginas]').exists()).toBe(false);
  });

  it.each([
    ['a per-person page with no active link (list of today)', 6, 'Plantão'],
    ['the server ai_status sem_responsavel', 8, 'Retorno'],
  ])('says nobody takes meetings for %s', async (_caso, id, titulo) => {
    const wrapper = await montar({
      agente: { config: { booking_page_id: id } },
    });
    expect(linha(wrapper).text()).toContain(
      `Nobody takes meetings on the page ${titulo}. Bia will pass the conversation to the team.`
    );
    expect(linha(wrapper).find('[data-abrir-paginas]').exists()).toBe(true);
  });

  it.each([
    ['the single host paused own hours (list of today)', 9, 'Consulta'],
    ['the server ai_status agenda_pausada', 10, 'Plantão novo'],
  ])(
    'says the host calendar is paused for %s, with the pages link',
    async (_caso, id, titulo) => {
      const wrapper = await montar({
        agente: { config: { booking_page_id: id } },
      });
      const estado = linha(wrapper).find(
        '[data-estado-agenda="agenda_pausada"]'
      );
      expect(estado.text()).toContain(
        `The calendar of who takes meetings on the page ${titulo} is paused. Bia will pass the conversation to the team until the hours are resumed.`
      );
      expect(estado.find('p').classes()).toContain('text-n-amber-11');
      expect(estado.find('.i-lucide-triangle-alert').exists()).toBe(true);
      expect(estado.find('[data-abrir-paginas]').exists()).toBe(true);
    }
  );

  it('says a deleted page no longer exists, never "does not book"', async () => {
    const wrapper = await montar({
      agente: { config: { booking_page_id: 99 } },
    });
    const texto = linha(wrapper).text();
    expect(texto).toContain(
      "The chosen page no longer exists. Choose another one or choose Don't book."
    );
    expect(texto).not.toContain("doesn't book");
  });

  // P3 (b) — quem só vê lê o efeito, sem frase de ação.
  it('gives view-only seats the state without "Change" and without action wording', async () => {
    const pausada = await montar({
      podeGerenciar: false,
      agente: { config: { booking_page_id: 5 } },
    });
    expect(linha(pausada).text()).toContain(
      'The page Conversa is paused. Bia will pass the conversation to the team.'
    );
    expect(linha(pausada).text()).not.toContain('turn the page back on');
    expect(pausada.find('[data-alterar="agenda"]').exists()).toBe(false);

    const apagada = await montar({
      podeGerenciar: false,
      agente: { config: { booking_page_id: 99 } },
    });
    expect(linha(apagada).text()).toContain(
      'The chosen page no longer exists. Bia will pass the conversation to the team.'
    );
    expect(linha(apagada).text()).not.toContain('Choose');
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
