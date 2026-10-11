import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaAgenda from '../../components/pagina/GavetaAgenda.vue';

// #1181 (item A) — a gaveta "Marcar reuniões" diz, com o texto real, o estado da página escolhida,
// quem fica com a reunião e o fuso, só com o que a lista de páginas traz: os campos novos do
// servidor (ai_status e recebe, #1305) quando vêm, e os de hoje quando não vêm. O ChoiceSelect vira
// botões que mudam o v-model (mesmo stub do gavetas.spec.js).
const permissao = vi.hoisted(() => ({ podeAbrirAgendamento: true }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn() }),
    useMapGetter: () => computed(() => false),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeAbrirAgendamento: computed(() => permissao.podeAbrirAgendamento),
    }),
  };
});
const paginasApi = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({ default: paginasApi }));

withFullI18n();

const ChoiceSelect = {
  props: [
    'modelValue',
    'options',
    'ariaLabel',
    'triggerId',
    'disabled',
    'placeholder',
  ],
  emits: ['update:modelValue'],
  template: `<div data-escolha :id="triggerId" :data-placeholder="placeholder">
    <button v-for="opcao in options" :key="String(opcao.value)" type="button"
      :data-valor="String(opcao.value)"
      @click="$emit('update:modelValue', opcao.value)">{{ opcao.label }}</button>
  </div>`,
};

const PAGINAS = [
  // De hoje, responsável único em ordem: a lista não traz o nome.
  {
    id: 3,
    title: 'Visita',
    enabled: true,
    assignment_mode: 'fixed',
    attention: false,
  },
  // De hoje, um link por pessoa: o primeiro link ativo é de quem fica sem atendente.
  {
    id: 4,
    title: 'Demonstração',
    enabled: true,
    assignment_mode: 'per_agent',
    links: [{ agent_name: 'Ana' }, { agent_name: 'Caio' }],
  },
  { id: 5, title: 'Conversa', enabled: false, assignment_mode: 'fixed' },
  {
    id: 6,
    title: 'Plantão',
    enabled: true,
    assignment_mode: 'fixed',
    attention: true,
  },
  // Com os campos novos do servidor.
  {
    id: 7,
    title: 'Avaliação',
    enabled: true,
    ai_status: 'ativa',
    recebe: { modo: 'fixo', nome: 'Rita' },
    timezone: 'America/Sao_Paulo',
  },
  {
    id: 8,
    title: 'Retorno',
    enabled: true,
    ai_status: 'ativa',
    recebe: { modo: 'por_pessoa', nome: '' },
  },
  { id: 9, title: 'Pausa nova', enabled: true, ai_status: 'pausada' },
  // Responsável único com "Meus horários" pausado: de hoje (paused_people) e do servidor.
  {
    id: 10,
    title: 'Consulta',
    enabled: true,
    assignment_mode: 'fixed',
    attention: false,
    paused_people: [{ id: 1, name: 'Rita' }],
  },
  { id: 11, title: 'Plantão novo', enabled: true, ai_status: 'agenda_pausada' },
  { id: 12, title: 'Sem dono', enabled: true, ai_status: 'sem_responsavel' },
];

const no = seletor => document.querySelector(seletor);
const texto = seletor =>
  no(seletor)?.textContent.split(' ').filter(Boolean).join(' ');

const montar = async bookingPageId => {
  const wrapper = mount(GavetaAgenda, {
    attachTo: document.body,
    props: {
      agente: { id: 7, config: { booking_page_id: bookingPageId } },
      nome: 'Bia',
    },
    global: { stubs: { ChoiceSelect } },
  });
  await flushPromises();
  return wrapper;
};

describe('GavetaAgenda · estado real da página (#1181 item A)', () => {
  let wrapper;
  beforeEach(() => {
    permissao.podeAbrirAgendamento = true;
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: PAGINAS } });
  });
  afterEach(() => wrapper?.unmount());

  it('active, single host of today: names the page and the generic host, no zone', async () => {
    wrapper = await montar(3);
    expect(texto('[data-estado-agenda="ativa"]')).toBe(
      'Bia offers times from the page Visita.'
    );
    expect(texto('[data-recebe]')).toBe(
      'The meeting goes to the person in charge of the page.'
    );
    expect(no('[data-fuso]')).toBeNull();
    expect(no('.i-lucide-triangle-alert')).toBeNull();
  });

  it('active, per person of today: the first active link when nobody handles the chat', async () => {
    wrapper = await montar(4);
    expect(texto('[data-recebe]')).toBe(
      'The meeting goes to whoever is handling the conversation, if that person takes meetings on the page. If not, it goes to Ana.'
    );
  });

  it('active with the server recebe fixo: names the host and the business zone', async () => {
    wrapper = await montar(7);
    expect(texto('[data-recebe]')).toBe('The meeting goes to Rita.');
    // O nome do fuso vem do Intl do navegador ("Brasilia Standard Time" no ICU do Node 24).
    const fuso = texto('[data-fuso]');
    expect(fuso.startsWith('Times in the business time zone (Brasilia')).toBe(
      true
    );
    expect(fuso.endsWith('Time).')).toBe(true);
  });

  it('active with the server recebe por_pessoa without a name: the generic first person', async () => {
    wrapper = await montar(8);
    expect(texto('[data-recebe]')).toBe(
      "The meeting goes to whoever is handling the conversation, if that person takes meetings on the page. If not, it goes to the first person on the page's list."
    );
  });

  it.each([
    ['enabled false (today)', 5, 'Conversa'],
    ['ai_status pausada (server)', 9, 'Pausa nova'],
  ])(
    'paused by %s: amber text with icon, pages link, no host line',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      const estado = no('[data-estado-agenda="pausada"]');
      expect(texto('[data-estado-agenda="pausada"] p')).toBe(
        `The page ${titulo} is paused. Bia will pass the conversation to the team until you turn the page back on.`
      );
      expect(estado.querySelector('p').className).toContain('text-n-amber-11');
      expect(estado.querySelector('.i-lucide-triangle-alert')).not.toBeNull();
      const link = no('[data-abrir-paginas]');
      expect(link.getAttribute('href')).toBe('/app/settings_booking');
      expect(link.getAttribute('target')).toBe('_blank');
      expect(no('[data-recebe]')).toBeNull();
    }
  );

  it('paused without access to the booking pages: no link', async () => {
    permissao.podeAbrirAgendamento = false;
    wrapper = await montar(5);
    expect(no('[data-estado-agenda="pausada"]')).not.toBeNull();
    expect(no('[data-abrir-paginas]')).toBeNull();
  });

  it.each([
    ['single host flagged (today)', 6, 'Plantão'],
    ['ai_status sem_responsavel (server)', 12, 'Sem dono'],
  ])(
    'nobody to take meetings by %s: passes to the team, pages link, no host line',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      const estado = no('[data-estado-agenda="sem_ninguem"]');
      expect(texto('[data-estado-agenda="sem_ninguem"] p')).toBe(
        `Nobody takes meetings on the page ${titulo}. Bia will pass the conversation to the team.`
      );
      expect(estado.querySelector('p').className).toContain('text-n-amber-11');
      expect(estado.querySelector('.i-lucide-triangle-alert')).not.toBeNull();
      expect(no('[data-abrir-paginas]')).not.toBeNull();
      expect(no('[data-recebe]')).toBeNull();
    }
  );

  // P2-2 — a IA não acha horário de quem pausou "Meus horários" (Slots#host_paused?).
  it.each([
    ['paused_people of the single host (today)', 10, 'Consulta'],
    ['ai_status agenda_pausada (server)', 11, 'Plantão novo'],
  ])(
    'host calendar paused by %s: amber with icon, pages link, no host line',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      const estado = no('[data-estado-agenda="agenda_pausada"]');
      expect(texto('[data-estado-agenda="agenda_pausada"] p')).toBe(
        `The calendar of who takes meetings on the page ${titulo} is paused. Bia will pass the conversation to the team until the hours are resumed.`
      );
      expect(estado.querySelector('p').className).toContain('text-n-amber-11');
      expect(estado.querySelector('.i-lucide-triangle-alert')).not.toBeNull();
      expect(no('[data-abrir-paginas]')).not.toBeNull();
      expect(no('[data-recebe]')).toBeNull();
    }
  );

  it('a deleted page: says it no longer exists and asks to choose another or "Don\'t book"', async () => {
    wrapper = await montar(42);
    expect(texto('[data-estado-agenda="nao_existe"]')).toBe(
      "The chosen page no longer exists. Choose another one or choose Don't book."
    );
    expect(no('[data-escolha]').dataset.placeholder).toBe('Choose a page');
    expect(no('[data-recebe]')).toBeNull();
    expect(no('[data-abrir-paginas]')).toBeNull();
  });

  // P3 (a) — lista vazia, mas o agente ainda aponta para uma página apagada.
  it('a deleted page with an empty list: "no longer exists" and "Don\'t book", not "create a page"', async () => {
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
    wrapper = await montar(42);
    expect(no('[data-sem-paginas]')).toBeNull();
    expect(no('[data-estado-agenda="nao_existe"]')).not.toBeNull();
    expect(
      [...document.querySelectorAll('[data-escolha] button')].map(
        b => b.dataset.valor
      )
    ).toEqual(['']);
    expect(no('[data-salvar]')).not.toBeNull();
  });

  it('an empty list and no saved page: teaches how to create a page', async () => {
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
    wrapper = await montar(null);
    expect(no('[data-sem-paginas]')).not.toBeNull();
    expect(no('[data-escolha]')).toBeNull();
  });

  it('none: the agent does not book', async () => {
    wrapper = await montar(null);
    expect(texto('[data-estado-agenda="nenhuma"]')).toBe(
      "Bia doesn't book meetings."
    );
    expect(no('[data-recebe]')).toBeNull();
  });

  it('follows the choice on screen before saving', async () => {
    wrapper = await montar(3);
    no('[data-valor="5"]').click();
    await flushPromises();
    expect(no('[data-estado-agenda="pausada"]')).not.toBeNull();
    no('[data-valor=""]').click();
    await flushPromises();
    expect(no('[data-estado-agenda="nenhuma"]')).not.toBeNull();
  });
});
