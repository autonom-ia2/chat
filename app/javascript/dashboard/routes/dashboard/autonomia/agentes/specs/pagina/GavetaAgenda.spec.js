import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaAgenda from '../../components/pagina/GavetaAgenda.vue';

// #1181 (item A) / #1370 — a gaveta "Marcar reuniões" mostra um cartão por página (como em CRM ›
// Agendamento › Páginas e links), avisa quando a página escolhida pede atenção, mostra quem fica
// com a reunião e um exemplo de como o cliente vê. Usa os campos novos do servidor (ai_status e
// recebe, #1305) quando vêm, e os de hoje quando não vêm. Os cartões são rádios de verdade
// (BookingChoiceCards): o teste marca o rádio do cartão.
const permissao = vi.hoisted(() => ({ podeAbrirAgendamento: true }));
const loja = vi.hoisted(() => ({ dispatch: vi.fn() }));
const roteador = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => loja,
    useMapGetter: () => computed(() => false),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-router', () => ({
  useRouter: () => ({
    resolve: rota => ({ href: `/app/${rota.name}` }),
    push: roteador.push,
  }),
  useRoute: () => ({
    path: '/app/accounts/1/agents/7',
    params: { accountId: '1' },
  }),
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
const escolher = async valor => {
  no(`[data-choice="${valor}"] input`).click();
  await flushPromises();
};
const escolhida = () =>
  [...document.querySelectorAll('[data-choice]')].find(
    cartao => cartao.querySelector('input').checked
  )?.dataset.choice;

const montar = async (bookingPageId, extra = {}, props = {}) => {
  const wrapper = mount(GavetaAgenda, {
    attachTo: document.body,
    props: {
      agente: { id: 7, config: { booking_page_id: bookingPageId, ...extra } },
      nome: 'Bia',
      ...props,
    },
  });
  await flushPromises();
  return wrapper;
};

describe('GavetaAgenda · cartões e estado real da página (#1181 item A, #1370)', () => {
  let wrapper;
  beforeEach(() => {
    permissao.podeAbrirAgendamento = true;
    roteador.push.mockReset();
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: PAGINAS } });
  });
  afterEach(() => wrapper?.unmount());

  it('one card per page, "Don\'t book meetings" first, with the Páginas e links status badge', async () => {
    paginasApi.get.mockResolvedValue({
      data: {
        payload: [
          {
            id: 3,
            title: 'Visita',
            enabled: true,
            ai_status: 'ativa',
            upcoming_meetings_count: 2,
            duration_minutes: 45,
            locations: [{ type: 'in_person' }, { type: 'whatsapp_video' }],
          },
          { id: 5, title: 'Conversa', enabled: false, missing: [] },
          { id: 6, title: '', enabled: false, missing: ['location'] },
        ],
      },
    });
    wrapper = await montar(3);
    expect(
      [...document.querySelectorAll('[data-choice]')].map(c => c.dataset.choice)
    ).toEqual(['', '3', '5']);
    expect(texto('[data-choice=""]')).toContain("Don't book meetings");
    const visita = texto('[data-choice="3"]');
    expect(visita).toContain('Visita');
    expect(visita).toContain('Live');
    expect(visita).toContain('In person, WhatsApp video');
    expect(visita).toContain('45 min');
    expect(visita).toContain('2 meetings booked');
    expect(no('[data-choice="5"] [data-status]').dataset.statusKey).toBe(
      'PAUSED'
    );
    expect(escolhida()).toBe('3');
    expect(no('select')).toBeNull();
  });

  // Decisão do Rodrigo (#1370): rascunho não é escolha. A pausada continua (o dono pode retomar).
  it('a draft page is a disabled card outside the choice, with what is missing and the pages link', async () => {
    paginasApi.get.mockResolvedValue({
      data: {
        payload: [
          { id: 3, title: 'Visita', enabled: true, ai_status: 'ativa' },
          {
            id: 6,
            title: 'Plantão',
            enabled: false,
            missing: ['location', 'pipeline', 'outra'],
          },
        ],
      },
    });
    wrapper = await montar(3);
    const rascunho = no('[data-rascunho="6"]');
    expect(rascunho.getAttribute('aria-disabled')).toBe('true');
    expect(rascunho.querySelector('input')).toBeNull();
    expect(no('[data-choice="6"]')).toBeNull();
    expect(rascunho.querySelector('[data-status]').dataset.statusKey).toBe(
      'DRAFT'
    );
    const textoRascunho = texto('[data-rascunho="6"]');
    expect(textoRascunho).toContain('Publish the page so Bia can use it.');
    expect(texto('[data-rascunho="6"] [data-faltas]')).toBe(
      'Almost ready to publish: Choose where the appointment happens Choose which pipeline new bookings go to'
    );
    const link = rascunho.querySelector('[data-abrir-rascunho]');
    expect(link.getAttribute('href')).toBe('/app/settings_booking');
    expect(link.getAttribute('target')).toBe('_blank');
  });

  it('a draft without access to Agendamento: no link', async () => {
    permissao.podeAbrirAgendamento = false;
    paginasApi.get.mockResolvedValue({
      data: {
        payload: [{ id: 6, title: 'P', enabled: false, missing: ['host'] }],
      },
    });
    wrapper = await montar(null);
    expect(no('[data-rascunho="6"]')).not.toBeNull();
    expect(no('[data-abrir-rascunho]')).toBeNull();
  });

  it('no duration on the card when the list does not bring it', async () => {
    wrapper = await montar(3);
    expect(texto('[data-choice="3"]')).not.toContain('min');
  });

  it('active, single host of today: no warning, the generic host and the example', async () => {
    wrapper = await montar(3);
    expect(no('[data-estado-agenda]')).toBeNull();
    expect(texto('[data-recebe]')).toBe(
      'The meeting goes to the person in charge of the page.'
    );
    expect(texto('[data-exemplo]')).toContain('Example');
    expect(texto('[data-exemplo]')).toContain('For Visita,');
    expect(no('[data-fuso]')).toBeNull();
  });

  it('active, per person of today: the first active link when nobody handles the chat', async () => {
    wrapper = await montar(4);
    expect(texto('[data-recebe]')).toBe(
      'The meeting goes to whoever is handling the conversation, if that person takes meetings on the page. If not, it goes to Ana.'
    );
  });

  it('active with the server recebe fixo: names the host, never the time zone', async () => {
    wrapper = await montar(7);
    expect(texto('[data-recebe]')).toBe('The meeting goes to Rita.');
    expect(document.body.textContent).not.toContain('Brasilia');
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
    'paused by %s: amber warning with icon, pages link, no host line nor example',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      const estado = no('[data-estado-agenda="pausada"]');
      expect(texto('[data-estado-agenda="pausada"] p')).toBe(
        `The page ${titulo} is paused. Bia will pass the conversation to the team until you turn the page back on.`
      );
      expect(estado.className).toContain('bg-n-amber-2');
      expect(estado.querySelector('.i-lucide-triangle-alert')).not.toBeNull();
      const link = no('[data-abrir-paginas]');
      expect(link.getAttribute('href')).toBe('/app/settings_booking');
      expect(link.getAttribute('target')).toBe('_blank');
      expect(no('[data-recebe]')).toBeNull();
      expect(no('[data-exemplo]')).toBeNull();
    }
  );

  it('paused without access to the booking pages: no link and no "create a page"', async () => {
    permissao.podeAbrirAgendamento = false;
    wrapper = await montar(5);
    expect(no('[data-estado-agenda="pausada"]')).not.toBeNull();
    expect(no('[data-abrir-paginas]')).toBeNull();
    expect(no('[data-criar-pagina]')).toBeNull();
  });

  it.each([
    ['single host flagged (today)', 6, 'Plantão'],
    ['ai_status sem_responsavel (server)', 12, 'Sem dono'],
  ])(
    'nobody to take meetings by %s: passes to the team, pages link, no host line',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      expect(texto('[data-estado-agenda="sem_ninguem"] p')).toBe(
        `Nobody takes meetings on the page ${titulo}. Bia will pass the conversation to the team.`
      );
      expect(no('[data-abrir-paginas]')).not.toBeNull();
      expect(no('[data-recebe]')).toBeNull();
    }
  );

  // P2-2 — a IA não acha horário de quem pausou "Meus horários" (Slots#host_paused?).
  it.each([
    ['paused_people of the single host (today)', 10, 'Consulta'],
    ['ai_status agenda_pausada (server)', 11, 'Plantão novo'],
  ])(
    'host calendar paused by %s: warning, pages link, no host line',
    async (_c, id, titulo) => {
      wrapper = await montar(id);
      expect(texto('[data-estado-agenda="agenda_pausada"] p')).toBe(
        `The calendar of who takes meetings on the page ${titulo} is paused. Bia will pass the conversation to the team until the hours are resumed.`
      );
      expect(no('[data-abrir-paginas]')).not.toBeNull();
      expect(no('[data-recebe]')).toBeNull();
    }
  );

  it('a deleted page: says it no longer exists, no card checked', async () => {
    wrapper = await montar(42);
    expect(texto('[data-estado-agenda="nao_existe"]')).toBe(
      "The chosen page no longer exists. Choose another one or choose Don't book."
    );
    expect(escolhida()).toBeUndefined();
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
      [...document.querySelectorAll('[data-choice]')].map(c => c.dataset.choice)
    ).toEqual(['']);
    expect(no('[data-salvar]')).not.toBeNull();
  });

  it('an empty list and no saved page: one action, the page assistant of Agendamento (#1371)', async () => {
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
    wrapper = await montar(null);
    expect(no('[data-sem-paginas]')).not.toBeNull();
    expect(no('[data-choice]')).toBeNull();
    expect(no('[data-salvar]')).toBeNull();
    no('[data-criar-pagina]').click();
    expect(roteador.push).toHaveBeenCalledWith({
      name: 'settings_booking',
      params: { accountId: '1' },
      query: { nova: 1, voltar: '/app/accounts/1/agents/7?gaveta=agenda' },
    });
  });

  it('an empty list without access to Agendamento: asks who manages the account', async () => {
    permissao.podeAbrirAgendamento = false;
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
    wrapper = await montar(null);
    expect(no('[data-criar-pagina]')).toBeNull();
    expect(no('[data-peca-pagina]')).not.toBeNull();
  });

  it('none: the "Don\'t book meetings" card is checked, no warning nor example', async () => {
    wrapper = await montar(null);
    expect(escolhida()).toBe('');
    expect(texto('[data-choice=""]')).toContain("Bia doesn't book meetings.");
    expect(no('[data-estado-agenda]')).toBeNull();
    expect(no('[data-exemplo]')).toBeNull();
  });

  it('follows the choice on screen before saving', async () => {
    wrapper = await montar(3);
    await escolher(5);
    expect(no('[data-estado-agenda="pausada"]')).not.toBeNull();
    await escolher('');
    expect(no('[data-estado-agenda]')).toBeNull();
    expect(no('[data-exemplo]')).toBeNull();
  });
});

// #1307 / #1370 — as pessoas da página que a IA pode usar (`booking_agent_ids`; vazio = todas), com
// "Todas as pessoas" primeiro. A preferência por uma delas vai em Mudar conversando.
describe('GavetaAgenda · pessoas que a IA pode usar (#1307)', () => {
  let wrapper;
  const PESSOAS = [
    { id: 21, nome: 'Rodrigo', ai_status: 'ativa' },
    { id: 22, nome: 'Roberto', ai_status: 'ativa' },
    { id: 23, nome: 'Rita', ai_status: 'agenda_pausada' },
  ];
  const COM_PESSOAS = [
    {
      id: 30,
      title: 'Reunião',
      enabled: true,
      ai_status: 'ativa',
      recebe: { modo: 'por_pessoa', nome: 'Rodrigo' },
      pessoas: PESSOAS,
    },
    {
      id: 31,
      title: 'Outra',
      enabled: true,
      ai_status: 'ativa',
      recebe: { modo: 'por_pessoa', nome: 'Caio' },
      pessoas: [
        { id: 40, nome: 'Caio', ai_status: 'ativa' },
        { id: 41, nome: 'Lia', ai_status: 'ativa' },
      ],
    },
    {
      id: 32,
      title: 'Solo',
      enabled: true,
      ai_status: 'ativa',
      recebe: { modo: 'fixo', nome: 'Rita' },
      pessoas: [{ id: 23, nome: 'Rita', ai_status: 'ativa' }],
    },
  ];
  const marcadas = () =>
    [...document.querySelectorAll('[data-pessoa]')]
      .filter(rotulo => rotulo.querySelector('input').checked)
      .map(rotulo => Number(rotulo.dataset.pessoa));
  const alternar = async id => {
    no(`[data-pessoa="${id}"] input`).click();
    await flushPromises();
  };
  const alternarTodas = async () => {
    no('[data-todas] input').click();
    await flushPromises();
  };
  const salvar = async () => {
    no('[data-salvar]').click();
    await flushPromises();
  };

  beforeEach(() => {
    permissao.podeAbrirAgendamento = true;
    loja.dispatch.mockReset();
    loja.dispatch.mockResolvedValue({});
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: COM_PESSOAS } });
  });
  afterEach(() => wrapper?.unmount());

  it('"All people" first, then every person checked with photo, in the page order, without the host line', async () => {
    wrapper = await montar(30);
    expect(texto('[data-pessoas] legend')).toBe('Who Bia can book with');
    expect(no('[data-todas] input').checked).toBe(true);
    expect(texto('[data-todas]')).toContain('All people');
    expect(marcadas()).toEqual([21, 22, 23]);
    expect(texto('[data-pessoa="23"] [data-pessoa-pausada]')).toBe(
      'calendar paused'
    );
    expect(no('[data-pessoa="21"] [data-pessoa-pausada]')).toBeNull();
    expect(texto('[data-pessoas-dica]')).toBe(
      'Want Bia to prefer one person? Say it in Change by chatting.'
    );
    expect(no('[data-recebe]')).toBeNull();
    // O cartão inteiro é o alvo de toque (44 px), com a caixa dentro do rótulo.
    expect(no('[data-pessoa="21"]').className).toContain('min-h-11');
    expect(no('[data-todas]').className).toContain('min-h-11');
  });

  it('"All people" is half checked when only some are, and checks everyone again', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    const todas = no('[data-todas] input');
    expect(todas.checked).toBe(false);
    expect(todas.indeterminate).toBe(true);
    await alternarTodas();
    expect(marcadas()).toEqual([21, 22, 23]);
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_agent_ids: [] },
    });
  });

  it('unchecking "All people" leaves nobody and blocks saving', async () => {
    wrapper = await montar(30);
    await alternarTodas();
    expect(marcadas()).toEqual([]);
    expect(texto('[data-pessoas-erro]')).toBe('Check at least one person.');
    expect(no('[data-salvar]').disabled).toBe(true);
  });

  it('checks only the saved people that are still on the page', async () => {
    wrapper = await montar(30, { booking_agent_ids: [22, 99] });
    expect(marcadas()).toEqual([22]);
  });

  it('a single person on the page: no choice, the host line with the photo', async () => {
    wrapper = await montar(32);
    expect(no('[data-pessoas]')).toBeNull();
    expect(texto('[data-recebe] p')).toBe('The meeting goes to Rita.');
    expect(texto('[data-recebe]').startsWith('R')).toBe(true);
  });

  it('saves only the people, keeping the page, and in the page order', async () => {
    wrapper = await montar(30);
    await alternar(22);
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_agent_ids: [21, 23] },
    });
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('all checked again saves [] (everyone, including who joins later)', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    await alternar(22);
    await alternar(23);
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_agent_ids: [] },
    });
  });

  it('closes without writing when the people did not change, even with a stale saved id', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21, 99] });
    await salvar();
    expect(loja.dispatch).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
  });

  it('nobody checked: says to check one, links it to the group and does not save', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    await alternar(21);
    const erro = no('[data-pessoas-erro]');
    expect(texto('[data-pessoas-erro]')).toBe('Check at least one person.');
    expect(erro.getAttribute('role')).toBe('alert');
    expect(no('[data-pessoas]').getAttribute('aria-describedby')).toBe(erro.id);
    expect(no('[data-salvar]').disabled).toBe(true);
    await salvar();
    expect(loja.dispatch).not.toHaveBeenCalled();
  });

  it('a saved restriction with nobody left on the page: nobody takes meetings until the owner picks', async () => {
    wrapper = await montar(30, { booking_agent_ids: [99] });
    expect(marcadas()).toEqual([]);
    expect(no('[data-estado-agenda="sem_ninguem"]')).not.toBeNull();
    await alternar(22);
    expect(no('[data-estado-agenda]')).toBeNull();
    expect(no('[data-exemplo]')).not.toBeNull();
  });

  it('only people with the calendar paused checked: the calendar-paused state', async () => {
    wrapper = await montar(30, { booking_agent_ids: [23] });
    expect(no('[data-estado-agenda="agenda_pausada"]')).not.toBeNull();
  });

  it('changing the page starts with everyone on the new page and saves the page with []', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    await escolher(31);
    expect(marcadas()).toEqual([40, 41]);
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_page_id: 31, booking_agent_ids: [] },
    });
  });

  it('changing to a page with one person also clears the old restriction', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    await escolher(32);
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_page_id: 32, booking_agent_ids: [] },
    });
  });

  it('a single person with a stale saved restriction: shows active, and Save fixes it with []', async () => {
    wrapper = await montar(32, { booking_agent_ids: [99] });
    expect(no('[data-pessoas]')).toBeNull();
    expect(no('[data-estado-agenda]')).toBeNull();
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_agent_ids: [] },
    });
  });

  it('a single person already released: closes without writing', async () => {
    wrapper = await montar(32, { booking_agent_ids: [23] });
    await salvar();
    expect(loja.dispatch).not.toHaveBeenCalled();
  });

  it('a saved value that is not a list counts as nobody, like the server', async () => {
    wrapper = await montar(30, { booking_agent_ids: 'x' });
    expect(marcadas()).toEqual([]);
    expect(no('[data-estado-agenda="sem_ninguem"]')).not.toBeNull();
  });

  it('keeps the owner checks when the agent is updated with the drawer open', async () => {
    wrapper = await montar(30);
    await alternar(22);
    await wrapper.setProps({
      agente: { id: 7, config: { booking_page_id: 30, booking_agent_ids: [] } },
    });
    await flushPromises();
    expect(marcadas()).toEqual([21, 23]);
  });

  it('"Change by chatting" in the tip opens Mudar conversando when the agent allows it', async () => {
    wrapper = await montar(30, {}, { podeMudar: true });
    no('[data-ir-mudar]').click();
    expect(wrapper.emitted('mudar')).toHaveLength(1);
  });

  it('without Mudar conversando the tip only names it', async () => {
    wrapper = await montar(30);
    expect(no('[data-ir-mudar]')).toBeNull();
    expect(texto('[data-pessoas-dica] b')).toBe('Change by chatting');
  });

  it('"do not book" saves only the page as null', async () => {
    wrapper = await montar(30, { booking_agent_ids: [21] });
    await escolher('');
    expect(no('[data-pessoas]')).toBeNull();
    await salvar();
    expect(loja.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      config: { booking_page_id: null },
    });
  });
});
