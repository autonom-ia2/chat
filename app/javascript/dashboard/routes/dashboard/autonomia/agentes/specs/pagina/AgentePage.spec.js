import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentePage from '../../pages/AgentePage.vue';

// T07 · página do agente: estados (carregando, erro, não existe, parado, sem canal, escrito à mão,
// sem números, sem conversas), permissões, gavetas pelo :tab antigo, Parar/Voltar a atender,
// Excluir, Mudar conversando, cotação e interno.
const estado = vi.hoisted(() => ({
  podeGerenciar: true,
  quemRecebe: true,
  crm: true,
}));
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  commit: vi.fn(),
  state: null,
  getters: {},
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: nome => computed(() => store.state?.[nome] ?? false),
  };
});
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => estado.podeGerenciar),
      podeEscolherQuemRecebe: computed(() => estado.quemRecebe),
      crmLigado: computed(() => estado.crm),
    }),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const rota = vi.hoisted(() => ({ params: {} }));
const router = vi.hoisted(() => ({
  push: vi.fn(),
  replace: vi.fn(),
  resolve: vi.fn(destino => ({ href: `/app/${destino.name}` })),
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => router,
}));

const agentesApi = vi.hoisted(() => ({
  show: vi.fn(),
  analyticsConversations: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: agentesApi }));
const jornadaApi = vi.hoisted(() => ({
  semana: vi.fn(),
  canaisOcupados: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornadaApi }));
const canaisApi = vi.hoisted(() => ({
  get: vi.fn(),
  connect: vi.fn(),
  disconnect: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));
const faqApi = vi.hoisted(() => ({ list: vi.fn() }));
vi.mock('dashboard/api/autonomia/faqSuggestions', () => ({ default: faqApi }));
const paginasApi = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({ default: paginasApi }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};

const bia = (extra = {}) => ({
  id: 7,
  name: 'Bia',
  status: 'active',
  enabled: true,
  mode: 'guided',
  agent_type: 'support',
  actuation: 'external',
  channels_count: 1,
  has_instruction: true,
  config: { response_window: 'always' },
  ...extra,
});

const L2 = [
  {
    inbox_id: 1,
    name: 'WhatsApp do Centro',
    occupied_by: { kind: 'agent', agent_id: 7, agent_name: 'Bia' },
  },
  { inbox_id: 2, name: 'Instagram', occupied_by: null },
];

const preparar = ({
  agente = bia(),
  show = null,
  semana = { answered: 12, handed: 3 },
  canais = L2,
  perguntas = [],
} = {}) => {
  store.state = reactive({
    records: [],
    'autonomiaSources/getKnowledgeSources': [],
    'autonomiaSources/getUIFlags': { fetchingList: false },
    'inboxes/getInboxes': [{ id: 1, working_hours_enabled: false }],
    'autonomiaBuildThreads/getMessages': [],
    'autonomiaBuildThreads/getUIFlags': {},
  });
  store.getters = {
    'autonomiaAgents/getRecord': id =>
      store.state.records.find(item => item.id === Number(id)) || {},
  };
  store.dispatch.mockImplementation(async (acao, dados) => {
    if (acao === 'autonomiaAgents/upsert') store.state.records = [dados];
    if (acao === 'autonomiaAgents/update') {
      store.state.records = [{ ...store.state.records[0], ...dados }];
    }
    return null;
  });
  agentesApi.show.mockImplementation(show || (async () => ({ data: agente })));
  jornadaApi.semana.mockImplementation(async () => {
    if (!semana) throw new Error('404');
    return { data: { payload: [{ agent_id: 7, ...semana }] } };
  });
  jornadaApi.canaisOcupados.mockResolvedValue({ data: { payload: canais } });
  faqApi.list.mockResolvedValue({ data: { payload: perguntas } });
};

const montar = async (props = {}) => {
  const wrapper = mount(AgentePage, {
    attachTo: document.body,
    props: { agentId: '7', ...props },
  });
  await flushPromises();
  return wrapper;
};

const texto = () => document.body.textContent;

describe('AgentePage', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function fechar() {
      this.removeAttribute('open');
    });
  });

  beforeEach(() => {
    estado.podeGerenciar = true;
    estado.quemRecebe = true;
    estado.crm = true;
    rota.params = { agentId: '7' };
    store.dispatch.mockReset();
    store.commit.mockReset();
    router.push.mockReset();
    router.replace.mockReset();
    alerta.mockReset();
    preparar();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('estados de carga', () => {
    it('shows the skeleton while loading (t07-carregando)', async () => {
      preparar({ show: () => new Promise(() => {}) });
      const wrapper = await montar();
      expect(no('[role="status"]').textContent).toContain('PAGINA.CARREGANDO');
      expect(no('[data-esqueleto]')).not.toBeNull();
      expect(no('[data-heroi]')).toBeNull();
      wrapper.unmount();
    });

    it('says the agent no longer exists and goes back to the list (t07-naoexiste)', async () => {
      preparar({
        show: async () => {
          throw Object.assign(new Error('404'), { response: { status: 404 } });
        },
      });
      const wrapper = await montar();
      expect(no('[data-nao-existe]').textContent).toContain(
        'PAGINA.NAO_EXISTE'
      );
      await clicar('[data-nao-existe] button');
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
      wrapper.unmount();
    });

    it('shows the standard error and tries again (t07-erro)', async () => {
      let falhar = true;
      preparar({
        show: async () => {
          if (falhar)
            throw Object.assign(new Error('500'), {
              response: { status: 500 },
            });
          return { data: bia() };
        },
      });
      const wrapper = await montar();
      expect(no('[data-erro-abrir]').textContent).toContain(
        'PAGINA.ERRO_ABRIR_GARANTIA'
      );
      falhar = false;
      await clicar('[data-erro-abrir] button');
      expect(no('[data-heroi]')).not.toBeNull();
      wrapper.unmount();
    });
  });

  describe('T07 · atendendo', () => {
    it('has a single navy hero with the name, where it answers and the switch on', async () => {
      const wrapper = await montar();
      expect(todos('[data-heroi]')).toHaveLength(1);
      expect(no('h1').textContent.trim()).toBe('Bia');
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.RESPONDE_NO'
      );
      const interruptor = no('[role="switch"]');
      expect(interruptor.getAttribute('aria-checked')).toBe('true');
      expect(interruptor.className).toContain('min-h-11');
      expect(no('[data-acao-principal]').textContent).toContain('PAGINA.MUDAR');
      expect(no('[data-mais]')).not.toBeNull();
      expect(no('[data-faixa-parado]')).toBeNull();
      wrapper.unmount();
    });

    it('lets the More options menu out of the hero: only the rings are clipped', async () => {
      const wrapper = await montar();
      const heroi = no('[data-heroi]');
      expect(heroi.className).not.toContain('overflow-hidden');
      expect(
        heroi.querySelector('span[aria-hidden="true"]').className
      ).toContain('overflow-hidden');
      await clicar('[data-mais]');
      expect(todos('[role="menuitem"]').map(i => i.dataset.item)).toEqual([
        'foto',
        'versoes',
        'instrucoes',
        'excluir',
      ]);
      wrapper.unmount();
    });

    it('keeps icon and text side by side on narrow screens', async () => {
      const wrapper = await montar();
      ['sabe', 'onde', 'jeito'].forEach(linha => {
        const coluna = no(`[data-linha="${linha}"] h3`).parentElement;
        expect(coluna.className).toContain('min-w-0');
        expect(coluna.className).toContain('flex-1');
        expect(coluna.parentElement.className).not.toContain('flex-wrap');
      });
      wrapper.unmount();
    });

    it('reads the week numbers for this agent only, with no percentage', async () => {
      const wrapper = await montar();
      expect(jornadaApi.semana).toHaveBeenCalledWith({ agentId: 7 });
      expect(todos('[data-numero]').map(n => n.textContent)).toEqual([
        expect.stringContaining('12'),
        expect.stringContaining('3'),
      ]);
      expect(texto()).not.toContain('%');
      wrapper.unmount();
    });

    it('has no native select and none of the forbidden words', async () => {
      const wrapper = await montar();
      expect(no('select')).toBeNull();
      ['Ligar', 'confiança', 'certeza', 'Primeira mensagem'].forEach(palavra =>
        expect(texto()).not.toContain(palavra)
      );
      wrapper.unmount();
    });

    it('shows the Assignment link only with permission', async () => {
      const com = await montar();
      expect(no('[data-quem-recebe]').getAttribute('href')).toBe(
        '/app/crm_handoff_settings_index'
      );
      com.unmount();

      estado.quemRecebe = false;
      const sem = await montar();
      expect(no('[data-quem-recebe]')).toBeNull();
      expect(no('[data-sem-permissao]')).not.toBeNull();
      sem.unmount();
    });

    it('does not ask for an administrator when the install has no CRM assignment screen', async () => {
      estado.quemRecebe = false;
      estado.crm = false;
      const wrapper = await montar();
      expect(no('[data-quem-recebe]')).toBeNull();
      expect(no('[data-sem-permissao]')).toBeNull();
      wrapper.unmount();
    });

    it('asks before stopping and saves only the status (T15)', async () => {
      const wrapper = await montar();
      await clicar('[role="switch"]');
      expect(no('dialog[open]').textContent).toContain('PAGINA.PARAR.TITULO');
      await clicar('dialog[open] [data-confirmar]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        status: 'paused',
      });
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.PARAR.FEITO');
      expect(no('[data-faixa-parado]')).not.toBeNull();
      wrapper.unmount();
    });

    it('sends the question from the Testar block to the test drawer', async () => {
      store.dispatch.mockImplementation(async (acao, dados) => {
        if (acao === 'autonomiaAgents/upsert') store.state.records = [dados];
        if (acao === 'autonomiaAgents/test') return { reply: 'Abrimos sim.' };
        return null;
      });
      const wrapper = await montar();
      const campo = no('[data-pergunta]');
      campo.value = 'Vocês abrem no sábado?';
      campo.dispatchEvent(new Event('input'));
      await clicar('[data-perguntar]');
      expect(store.dispatch).toHaveBeenCalledWith(
        'autonomiaAgents/test',
        expect.objectContaining({ message: 'Vocês abrem no sábado?' })
      );
      expect(no('[role="dialog"]').textContent).toContain(
        'PAGINA.TESTE.TITULO'
      );
      wrapper.unmount();
    });

    it('swaps the page for Mudar conversando and comes back', async () => {
      const wrapper = await montar();
      await clicar('[data-acao-principal]');
      expect(no('[data-heroi]')).toBeNull();
      expect(no('[data-abertura]')).not.toBeNull();
      await clicar('[data-pronto]');
      expect(no('[data-heroi]')).not.toBeNull();
      wrapper.unmount();
    });

    it('deletes after confirming and goes back to the list (T16)', async () => {
      const wrapper = await montar();
      await clicar('[data-mais]');
      await clicar('[data-item="excluir"]');
      expect(no('dialog[open]').textContent).toContain('PAGINA.EXCLUIR.EXTRA');
      await clicar('dialog[open] [data-confirmar]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/delete', 7);
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.JORNADA.PAGINA.EXCLUIR.FEITO'
      );
      wrapper.unmount();
    });

    it('keeps a calm screen while deleting, never the open error (T16)', async () => {
      const wrapper = await montar();
      const anterior = store.dispatch.getMockImplementation();
      store.dispatch.mockImplementation(async (acao, dados) => {
        if (acao === 'autonomiaAgents/delete') store.state.records = [];
        return anterior(acao, dados);
      });
      await clicar('[data-mais]');
      await clicar('[data-item="excluir"]');
      await clicar('dialog[open] [data-confirmar]');
      expect(no('[data-erro-abrir]')).toBeNull();
      expect(router.push).toHaveBeenCalledWith({
        name: 'autonomia_agents_index',
      });
      wrapper.unmount();
    });

    it('offers "Stop answering" from the delete dialog when the agent is answering', async () => {
      const wrapper = await montar();
      await clicar('[data-mais]');
      await clicar('[data-item="excluir"]');
      await clicar('dialog[open] [data-atalho-parar]');
      const abertos = todos('dialog[open]');
      expect(abertos).toHaveLength(1);
      expect(abertos[0].textContent).toContain('PARAR.TITULO');
      wrapper.unmount();
    });

    it('drops the old tab from the URL when going to Mudar conversando', async () => {
      rota.params = { agentId: '7', tab: 'test' };
      const wrapper = await montar({ gaveta: 'testar' });
      router.replace.mockClear();
      await clicar('[data-acao-principal]');
      expect(router.replace).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: '7' },
      });
      rota.params = {};
      wrapper.unmount();
    });

    it('keeps the file count steady while the files are read again', async () => {
      const wrapper = await montar();
      store.state['autonomiaSources/getKnowledgeSources'] = [
        { id: 1, status: 'processing' },
        { id: 2, status: 'ready' },
      ];
      await flushPromises();
      const linha = () => no('[data-linha="sabe"]').textContent;
      expect(linha()).toContain('BLOCO_SABE.N_FONTES');

      store.state['autonomiaSources/getUIFlags'] = { fetchingList: true };
      store.state['autonomiaSources/getKnowledgeSources'] = [];
      await flushPromises();
      expect(linha()).toContain('BLOCO_SABE.N_FONTES');
      expect(linha()).not.toContain('SO_CONVERSA');
      wrapper.unmount();
    });

    it('warns before writing the instructions by hand (T14)', async () => {
      const wrapper = await montar();
      await clicar('[data-mais]');
      await clicar('[data-item="instrucoes"]');
      expect(no('dialog[open]').textContent).toContain(
        'INSTRUCOES.AVISO_TITULO'
      );
      expect(no('dialog[open] [data-aviso]').textContent).toContain(
        'INSTRUCOES.AVISO_TEXTO'
      );
      expect(no('[data-instrucao]')).toBeNull();
      await clicar('dialog[open] [data-confirmar]');
      expect(no('[data-instrucao]')).not.toBeNull();
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/update',
        expect.anything()
      );
      wrapper.unmount();
    });
  });

  describe('variantes', () => {
    it('stopped: amber band, switch off, turning on goes through the channel confirmation (t07-parado)', async () => {
      preparar({ agente: bia({ status: 'paused' }) });
      const wrapper = await montar();
      expect(no('[data-faixa-parado]').textContent).toContain(
        'PAGINA.PARADO_FAIXA'
      );
      expect(no('[role="switch"]').getAttribute('aria-checked')).toBe('false');
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.PARADO_NO'
      );

      await clicar('[role="switch"]');
      expect(no('[role="dialog"]').textContent).toContain('ONDE_QUANDO.TITULO');
      expect(no('[role="dialog"] [data-confirmar]').textContent).toContain(
        'PAGINA.ONDE.VOLTAR'
      );
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/update',
        expect.anything()
      );
      wrapper.unmount();
    });

    it('no channel: says so and offers to choose one (t07-semcanal)', async () => {
      preparar({
        agente: bia({ status: 'paused', channels_count: 0 }),
        canais: [{ inbox_id: 2, name: 'Instagram', occupied_by: null }],
      });
      const wrapper = await montar();
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.NENHUM_CANAL'
      );
      await clicar('[data-escolher-canal]');
      expect(no('[role="dialog"] [data-confirmar]').textContent).toContain(
        'PAGINA.ONDE.VOLTAR'
      );
      wrapper.unmount();
    });

    it('written by hand: Edit instructions instead of Mudar conversando (t07-manual)', async () => {
      preparar({ agente: bia({ mode: 'manual', instruction: 'Atenda.' }) });
      const wrapper = await montar();
      expect(no('[data-acao-principal]').textContent).toContain(
        'PAGINA.EDITAR_INSTRUCOES'
      );
      expect(no('[data-alterar="jeito"]')).toBeNull();
      await clicar('[data-acao-principal]');
      expect(no('[data-instrucao]').value).toBe('Atenda.');
      wrapper.unmount();
    });

    it('hides the numbers when L1 fails (t07-semnumeros)', async () => {
      preparar({ semana: null });
      const wrapper = await montar();
      expect(no('[data-semana]')).toBeNull();
      expect(no('[data-semana-vazia]')).toBeNull();
      wrapper.unmount();
    });

    it('says the numbers come later when there is nothing this week (t07-semconversas)', async () => {
      preparar({ semana: { answered: 0, handed: 0 } });
      const wrapper = await montar();
      expect(no('[data-semana-vazia]')).not.toBeNull();
      wrapper.unmount();
    });

    it('opens the conversations of the week from the numbers (t07-conversas)', async () => {
      agentesApi.analyticsConversations.mockResolvedValue({
        data: { payload: [] },
      });
      const wrapper = await montar();
      await clicar('[data-numero="passadas"]');
      expect(agentesApi.analyticsConversations).toHaveBeenCalledWith(7, {
        range: '7d',
        metric: 'handed_off',
      });
      wrapper.unmount();
    });

    it('counts the customer questions to check', async () => {
      preparar({ perguntas: [{ id: 1 }, { id: 2 }] });
      const wrapper = await montar();
      expect(no('[data-perguntas-para-conferir]').textContent).toContain(
        'BLOCO_SABE.N_PERGUNTAS'
      );
      wrapper.unmount();
    });
  });

  describe('só ver', () => {
    beforeEach(() => {
      estado.podeGerenciar = false;
    });

    it('reads and tests, with no writing action at all', async () => {
      const wrapper = await montar();
      expect(no('[role="switch"]')).toBeNull();
      expect(no('[data-acao-principal]')).toBeNull();
      expect(no('[data-faixa-so-ver]').textContent).toContain('PAGINA.SO_VER');
      expect(no('[data-heroi]').textContent).toContain('STATUS.ATENDENDO');
      expect(no('[data-bloco="testar"]')).not.toBeNull();
      expect(no('[data-alterar="sabe"]').textContent).toContain('PAGINA.VER');
      expect(no('[data-alterar="onde"]')).toBeNull();
      expect(no('[data-alterar="jeito"]')).toBeNull();
      expect(no('[data-numero]').tagName).toBe('DIV');
      expect(faqApi.list).not.toHaveBeenCalled();

      await clicar('[data-mais]');
      expect(todos('[role="menuitem"]').map(i => i.dataset.item)).toEqual([
        'versoes',
      ]);
      wrapper.unmount();
    });

    it('ignores an old tab that would write', async () => {
      rota.params = { agentId: '7', tab: 'channels' };
      const wrapper = await montar({ gaveta: 'onde' });
      expect(no('[role="dialog"]')).toBeNull();
      wrapper.unmount();
    });
  });

  describe('gaveta pelo :tab antigo', () => {
    it('opens What it knows and drops the tab from the URL when closing', async () => {
      rota.params = { agentId: '7', tab: 'knowledge' };
      const wrapper = await montar({ gaveta: 'sabe' });
      expect(no('[role="dialog"]').textContent).toContain('PAGINA.SABE.TITULO');
      await clicar('[data-fechar]');
      expect(no('[role="dialog"]')).toBeNull();
      expect(router.replace).toHaveBeenCalledWith({
        name: 'autonomia_agent_panel',
        params: { agentId: '7' },
      });
      wrapper.unmount();
    });

    it('opens the conversations of the week for the old performance tab', async () => {
      agentesApi.analyticsConversations.mockResolvedValue({
        data: { payload: [] },
      });
      rota.params = { agentId: '7', tab: 'performance' };
      const wrapper = await montar({ gaveta: 'conversas' });
      expect(no('[role="dialog"]').textContent).toContain('CONVERSAS.TITULO');
      wrapper.unmount();
    });
  });

  describe('cotação e interno', () => {
    it('keeps the quoting agent to name, photo, hours, status and numbers', async () => {
      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      const wrapper = await montar();
      expect(no('[data-bloco="testar"]')).toBeNull();
      expect(no('[data-acao-principal]')).toBeNull();
      expect(no('[data-linha="sabe"]')).toBeNull();
      expect(no('[data-linha="onde"]')).not.toBeNull();
      expect(no('[data-abrir-cotacao]').getAttribute('href')).toBe(
        '/app/autonomia_insurance_agent'
      );
      await clicar('[data-mais]');
      expect(todos('[role="menuitem"]').map(i => i.dataset.item)).toEqual([
        'foto',
      ]);
      expect(faqApi.list).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('shows an active quoting agent as answering and lets it stop', async () => {
      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      const wrapper = await montar();
      expect(no('[role="switch"]').getAttribute('aria-checked')).toBe('true');
      expect(no('[data-faixa-parado]')).toBeNull();
      await clicar('[role="switch"]');
      expect(no('dialog[open]').textContent).toContain('PARAR.TITULO');
      wrapper.unmount();
    });

    it('starts an internal agent without a channel', async () => {
      preparar({
        agente: bia({
          actuation: 'internal',
          status: 'paused',
          channels_count: 0,
        }),
      });
      const wrapper = await montar();
      expect(no('[data-linha="onde"]')).toBeNull();
      expect(no('[data-heroi] [data-onde]')).toBeNull();
      await clicar('[role="switch"]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        enabled: true,
        status: 'active',
      });
      wrapper.unmount();
    });
  });

  it('stops the sources poll when leaving the page', async () => {
    const wrapper = await montar();
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/fetch', {
      agentId: 7,
    });
    wrapper.unmount();
    expect(store.dispatch).toHaveBeenCalledWith('autonomiaSources/stopPolling');
    await nextTick();
  });

  // #1253 — Marca reuniões só com a agenda nova na conta (crm_booking_v2 + calendário da instalação).
  describe('marca reuniões', () => {
    const ligarAgendaNova = ligada => {
      window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
      store.state.getCurrentAccountId = 1;
      store.state['accounts/getAccount'] = () => ({
        features: { crm_booking_v2: ligada },
      });
    };

    beforeEach(() => {
      paginasApi.get.mockReset();
      paginasApi.get.mockResolvedValue({
        data: { payload: [{ id: 3, title: 'Visita', enabled: true }] },
      });
    });
    afterEach(() => {
      delete window.globalConfig;
    });

    it('shows the line and opens the booking drawer for who manages', async () => {
      ligarAgendaNova(true);
      const wrapper = await montar();
      expect(no('[data-linha="agenda"]')).not.toBeNull();
      await clicar('[data-alterar="agenda"]');
      expect(no('[role="dialog"]').textContent).toContain(
        'GAVETA_AGENDA.TITULO'
      );
      expect(no('[data-salvar]')).not.toBeNull();
      wrapper.unmount();
    });

    it('shows nothing new, and reads no pages, with the account flag off', async () => {
      ligarAgendaNova(false);
      const wrapper = await montar();
      expect(no('[data-linha="agenda"]')).toBeNull();
      expect(paginasApi.get).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('hides the line when the pages API answers an error', async () => {
      ligarAgendaNova(true);
      paginasApi.get.mockRejectedValue(new Error('404'));
      const wrapper = await montar();
      expect(no('[data-linha="agenda"]')).toBeNull();
      wrapper.unmount();
    });

    it('gives view-only seats the line without the change button', async () => {
      estado.podeGerenciar = false;
      ligarAgendaNova(true);
      const wrapper = await montar();
      expect(no('[data-linha="agenda"]')).not.toBeNull();
      expect(no('[data-alterar="agenda"]')).toBeNull();
      wrapper.unmount();
    });

    it('has no booking line for the quoting agent', async () => {
      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      ligarAgendaNova(true);
      const wrapper = await montar();
      expect(no('[data-linha="agenda"]')).toBeNull();
      expect(paginasApi.get).not.toHaveBeenCalled();
      wrapper.unmount();
    });
  });
});
