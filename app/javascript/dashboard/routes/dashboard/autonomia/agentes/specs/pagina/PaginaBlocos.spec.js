import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import PaginaBlocos from '../../components/pagina/PaginaBlocos.vue';

// #1253 — linha "Marca reuniões" do resumo: frase do estado com a página salva, "Alterar" só para
// quem gerencia, e nada sem a agenda nova na conta, na cotação ou quando a API de páginas falha.
const conta = vi.hoisted(() => ({
  agendaNova: true,
  podeAbrirAgendamento: true,
  atendimento: false,
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    getCurrentAccountId: 1,
    'accounts/getAccount': () => ({
      features: {
        crm_booking_v2: conta.agendaNova,
        agentes_enviar_local_e_contato: conta.atendimento,
      },
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

// #1433 ("a, para todos os agentes"): o resumo "Onde e quando responde" mostra também as outras caixas em que
// o agente recebe quando alguém passa.
describe('PaginaBlocos · Também recebe', () => {
  beforeEach(() => {
    conta.agendaNova = false;
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
  });

  it('lists the other inboxes under "Onde e quando responde"', async () => {
    const wrapper = await montar({
      temCanal: true,
      textoOnde: 'No WhatsApp Vendas, sempre.',
      tambemRecebe: ['WhatsApp Recepção', 'WhatsApp Suporte'],
    });
    const linha = wrapper.get('[data-linha="onde"]');
    expect(linha.text()).toContain('No WhatsApp Vendas, sempre.');
    expect(linha.get('[data-tambem-recebe]').text()).toContain(
      'WhatsApp Recepção, WhatsApp Suporte'
    );
  });

  it('says nothing more when the agent receives on no other inbox (no regression)', async () => {
    const wrapper = await montar({
      temCanal: true,
      textoOnde: 'No X, sempre.',
    });
    expect(wrapper.find('[data-tambem-recebe]').exists()).toBe(false);
  });
});

// #1720 — o resumo "Onde e quando responde" é uma linha só (a mesma do herói, utils/resumoOnde).
describe('PaginaBlocos · resumo de onde atende (Fase 2)', () => {
  beforeEach(() => {
    conta.agendaNova = false;
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
  });

  it('shows the one-line summary and "Alterar" for an agent that only receives', async () => {
    const wrapper = await montar({
      fase2: true,
      temCanal: false,
      textoOnde:
        'Recebe no 5511944547873 quando alguém passar a conversa · sempre',
      tambemRecebe: ['5511944547873'],
    });
    const linha = wrapper.get('[data-linha="onde"]');
    expect(linha.get('[data-resumo-onde]').text()).toBe(
      'Recebe no 5511944547873 quando alguém passar a conversa · sempre'
    );
    expect(linha.find('[data-alterar="onde"]').exists()).toBe(true);
    expect(linha.find('[data-escolher-canal]').exists()).toBe(false);
  });

  it('offers to choose a channel when it answers nowhere', async () => {
    const wrapper = await montar({
      fase2: true,
      temCanal: false,
      textoOnde: 'Não atende em lugar nenhum.',
    });
    const linha = wrapper.get('[data-linha="onde"]');
    expect(linha.text()).toContain('Não atende em lugar nenhum.');
    expect(linha.find('[data-escolher-canal]').exists()).toBe(true);
  });

  it('no longer has "Onde {nome} trabalha"', async () => {
    const wrapper = await montar({
      fase2: true,
      temCanal: true,
      textoOnde: 'x',
    });
    expect(wrapper.find('[data-linha="onde-trabalha"]').exists()).toBe(false);
  });
});

// #1479 / #2723 — o bloco "Endereço e telefone": só com a flag E a Fase 2, e nunca na cotação, no agente interno
// (copiloto) nem no ajudante. Telefone que não formata aparece cru, nunca como "ainda não tem telefone".
describe('PaginaBlocos · Endereço e telefone', () => {
  const COM_DADOS = {
    config: {
      atendimento: {
        endereco: 'Rua das Flores, 120',
        telefone: '+5511940001234',
      },
    },
  };
  const linha = wrapper => wrapper.find('[data-linha="atendimento"]');

  beforeEach(() => {
    conta.atendimento = true;
    conta.agendaNova = false;
    paginasApi.get.mockReset();
    paginasApi.get.mockResolvedValue({ data: { payload: [] } });
  });

  afterEach(() => {
    conta.atendimento = false;
    conta.agendaNova = true;
  });

  it('aparece com a flag e a Fase 2, com o endereço e o telefone', async () => {
    const wrapper = await montar({ agente: COM_DADOS, fase2: true });

    expect(linha(wrapper).exists()).toBe(true);
    expect(wrapper.find('[data-resumo-endereco]').text()).toContain(
      'Rua das Flores, 120'
    );
    expect(wrapper.find('[data-resumo-telefone]').exists()).toBe(true);
  });

  it('não aparece com a flag desligada', async () => {
    conta.atendimento = false;
    const wrapper = await montar({ agente: COM_DADOS, fase2: true });
    expect(linha(wrapper).exists()).toBe(false);
  });

  it('não aparece sem a Fase 2', async () => {
    const wrapper = await montar({ agente: COM_DADOS, fase2: false });
    expect(linha(wrapper).exists()).toBe(false);
  });

  it('não aparece na cotação', async () => {
    const wrapper = await montar({
      agente: COM_DADOS,
      fase2: true,
      cotacao: true,
    });
    expect(linha(wrapper).exists()).toBe(false);
  });

  it('não aparece no agente interno nem no ajudante', async () => {
    const interno = await montar({
      agente: COM_DADOS,
      fase2: true,
      interno: true,
    });
    expect(linha(interno).exists()).toBe(false);

    const ajudante = await montar({
      agente: COM_DADOS,
      fase2: true,
      ajuda: { principais: [{ id: 1, name: 'Ana' }], quando: 'Sempre' },
    });
    expect(linha(ajudante).exists()).toBe(false);
  });

  it('telefone gravado que não formata aparece cru', async () => {
    const wrapper = await montar({
      agente: {
        config: { atendimento: { endereco: '', telefone: '+999123' } },
      },
      fase2: true,
    });

    expect(wrapper.find('[data-resumo-telefone]').text()).toContain('+999123');
    expect(wrapper.find('[data-atendimento-vazio]').exists()).toBe(false);
  });
});
