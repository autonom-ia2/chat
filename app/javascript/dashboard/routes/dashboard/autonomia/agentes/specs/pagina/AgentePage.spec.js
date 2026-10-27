import { nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentePage from '../../pages/AgentePage.vue';
import { comNotaDaGaveta, semMensagens } from './i18nDaNota';

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
  return {
    useCanManage: () => computed(() => estado.podeGerenciar),
    usePermissionGranted: () => computed(() => true),
  };
});
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => estado.podeGerenciar),
      podeEscolherQuemRecebe: computed(() => estado.quemRecebe),
      podeAbrirAgendamento: computed(() => estado.podeGerenciar),
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
  getTools: vi.fn(),
  getAjuda: vi.fn(),
  updateAjuda: vi.fn(),
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
  ondeAtende: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));
const faqApi = vi.hoisted(() => ({ list: vi.fn() }));
vi.mock('dashboard/api/autonomia/faqSuggestions', () => ({ default: faqApi }));
const paginasApi = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('dashboard/api/crmBookingPages', () => ({ default: paginasApi }));
// #1426 (4b) — conferências e autoteste do material.
const materialApi = vi.hoisted(() => ({
  get: vi.fn(),
  resolver: vi.fn(),
  pedirAutoteste: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/material', () => ({ default: materialApi }));
// #1429 F3 — a base de seguros do agente.
const baseApi = vi.hoisted(() => ({
  ler: vi.fn(),
  comparar: vi.fn(),
  atualizar: vi.fn(),
  desfazer: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/baseDoAgente', () => ({ default: baseApi }));

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
  semana = { answered: 12, handed: 3, resolved: 5 },
  canais = L2,
  perguntas = [],
  caixas = [{ id: 1, working_hours_enabled: false }],
} = {}) => {
  store.state = reactive({
    records: [],
    'autonomiaSources/getKnowledgeSources': [],
    'autonomiaSources/getUIFlags': { fetchingList: false },
    'inboxes/getInboxes': caixas,
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
    agentesApi.getTools.mockReset();
    router.push.mockReset();
    router.replace.mockReset();
    alerta.mockReset();
    materialApi.get.mockReset();
    materialApi.get.mockResolvedValue({
      data: { problemas: [], autoteste: null },
    });
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
      expect(heroi.className).not.toContain('overflow-clip');
      // overflow-clip (não hidden): recorta os anéis sem virar contêiner de rolagem.
      expect(
        heroi.querySelector('span[aria-hidden="true"]').className
      ).toContain('overflow-clip');
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
        expect.stringContaining('5'),
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

    // #1366 — ativo e ligado no servidor, sem canal (a Livia da conta 17): Parado, nunca Atendendo.
    it('active with no channel: stopped, "not on any channel", and the switch goes to the channel choice', async () => {
      preparar({
        agente: bia({ channels_count: 0, tem_onde_trabalhar: false }),
        canais: [{ inbox_id: 2, name: 'Instagram', occupied_by: null }],
      });
      const wrapper = await montar();
      expect(no('[role="switch"]').getAttribute('aria-checked')).toBe('false');
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.NENHUM_CANAL'
      );
      expect(texto()).not.toContain('PAGINA.RESPONDE_NO');

      await clicar('[role="switch"]');
      expect(no('[role="dialog"]').textContent).toContain('ONDE_QUANDO.TITULO');
      expect(no('[role="dialog"] [data-confirmar]').textContent).toContain(
        'PAGINA.ONDE.COMECAR'
      );
      expect(store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaAgents/update',
        expect.anything()
      );
      wrapper.unmount();
    });

    it('reads the agent again after leaving the last channel (the server stopped it)', async () => {
      canaisApi.disconnect.mockResolvedValue({});
      const wrapper = await montar();
      await clicar('[data-alterar="onde"]');
      await clicar('[data-nao-atender]');
      await clicar('dialog[open] [data-botoes] [data-confirmar]');

      expect(canaisApi.disconnect).toHaveBeenCalledWith(7, 1);
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7);
      wrapper.unmount();
    });

    it('active with no channel: a view only seat reads "Parado" in the pill', async () => {
      estado.podeGerenciar = false;
      preparar({
        agente: bia({ channels_count: 0, tem_onde_trabalhar: false }),
      });
      const wrapper = await montar();
      expect(no('[data-heroi]').textContent).toContain(
        'AGENTS.JORNADA.STATUS.PARADO'
      );
      expect(no('[data-heroi]').textContent).not.toContain(
        'AGENTS.JORNADA.STATUS.ATENDENDO'
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
        'PAGINA.ONDE.COMECAR'
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
        metric: 'passadas',
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

    // #1426 — na Fase 2 o quadro avisa quantos materiais precisam do dono (reprovados ou não lidos), sem o cartão.
    describe('material that needs the owner', () => {
      const MATERIAL = [
        {
          id: 1,
          status: 'ready',
          review: { status: 'needs_resend', reviewed_at: '2026-10-19' },
        },
        { id: 2, status: 'failed' },
        {
          id: 3,
          status: 'ready',
          review: { status: 'needs_review', reviewed_at: null },
        },
        {
          id: 4,
          status: 'ready',
          review: { status: 'accepted', reviewed_at: '2026-10-19' },
        },
      ];
      const comMaterial = async ligada => {
        store.state.getCurrentAccountId = 1;
        store.state['accounts/getAccount'] = () => ({
          autonomia_agents_fase2: ligada,
        });
        const wrapper = await montar();
        store.state['autonomiaSources/getKnowledgeSources'] = MATERIAL;
        await flushPromises();
        return wrapper;
      };

      it('counts them with the Fase 2', async () => {
        const wrapper = await comMaterial(true);
        const aviso = no('[data-problemas-no-material]');
        expect(aviso.textContent).toContain('BLOCO_SABE.N_PROBLEMAS');
        expect(
          wrapper
            .findComponent({ name: 'PaginaBlocos' })
            .props('problemasNoMaterial')
        ).toBe(2);
        wrapper.unmount();
      });

      it('says nothing without the Fase 2', async () => {
        const wrapper = await comMaterial(false);
        expect(no('[data-problemas-no-material]')).toBeNull();
        wrapper.unmount();
      });

      // #1426 (4b) — os cartões do "um problema por vez" também contam, sem contar duas vezes o mesmo material.
      it('adds the cards of the checks, once per material', async () => {
        materialApi.get.mockResolvedValue({
          data: {
            problemas: [
              { id: 'contradicao-a', tipo: 'contradicao', fontes: [4, 1] },
              { id: 'autoteste-r-0', tipo: 'autoteste', fontes: [] },
            ],
            autoteste: null,
          },
        });
        const wrapper = await comMaterial(true);
        await flushPromises();

        expect(materialApi.get).toHaveBeenCalledWith(7);
        // 2 cartões + o material 2 (não deu para ler, sem cartão); o 1 já está no cartão da contradição
        expect(
          wrapper
            .findComponent({ name: 'PaginaBlocos' })
            .props('problemasNoMaterial')
        ).toBe(3);
        wrapper.unmount();
      });

      it('does not read the checks without the Fase 2', async () => {
        const wrapper = await comMaterial(false);
        expect(materialApi.get).not.toHaveBeenCalled();
        wrapper.unmount();
      });
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

    // #1370 — `?gaveta=` (a volta do assistente de páginas de agendamento) abre a gaveta uma vez:
    // a consulta sai da URL ao abrir, sem levar o resto dela.
    it('opens a drawer from ?gaveta= and drops only that query from the URL', async () => {
      rota.query = { gaveta: 'sabe', origem: 'x' };
      const wrapper = await montar({ gaveta: 'sabe' });
      expect(no('[role="dialog"]').textContent).toContain('PAGINA.SABE.TITULO');
      expect(router.replace).toHaveBeenCalledWith({ query: { origem: 'x' } });
      delete rota.query;
      wrapper.unmount();
    });

    // #1525 — o módulo de Cotação e o cartão da lista chegam por /channels com a Lia parada e sem canal:
    // abre a escolha de canal que liga (a mesma do "Escolher canal"), não a gaveta só de leitura.
    it('opens the channel choice that starts answering for a stopped agent on the old channels tab', async () => {
      preparar({
        agente: bia({
          agent_type: 'insurance_quote',
          status: 'paused',
          enabled: false,
          channels_count: 0,
          tem_onde_trabalhar: false,
        }),
        canais: [{ inbox_id: 2, name: 'Instagram', occupied_by: null }],
      });
      rota.params = { agentId: '7', tab: 'channels' };
      const wrapper = await montar({ gaveta: 'onde' });
      expect(no('[role="dialog"] [data-confirmar]').textContent).toContain(
        'PAGINA.ONDE.COMECAR'
      );
      wrapper.unmount();
    });

    it('keeps where and when for an answering agent on the old channels tab', async () => {
      rota.params = { agentId: '7', tab: 'channels' };
      const wrapper = await montar({ gaveta: 'onde' });
      // A gaveta de onde e quando no modo 'alterar': o título dela (o modo 'voltar' usa ONDE_QUANDO.TITULO)
      // e o "Salvar", nunca o começar/voltar a atender.
      const gaveta = no('[role="dialog"]').textContent;
      expect(gaveta).toContain('PAGINA.ONDE.TITULO');
      expect(gaveta).not.toContain('ONDE_QUANDO.TITULO');
      const confirmar = no('[role="dialog"] [data-confirmar]').textContent;
      expect(confirmar).toContain('PAGINA.ONDE.SALVAR');
      expect(confirmar).not.toContain('PAGINA.ONDE.VOLTAR');
      expect(confirmar).not.toContain('PAGINA.ONDE.COMECAR');
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

    it('links the performance panel for a support agent, never for the quoting agent (#2251)', async () => {
      const ligarPainel = () => {
        store.state.getCurrentAccountId = 1;
        store.state['accounts/getAccount'] = () => ({
          autonomia_agents_enabled: true,
          features: {
            autonomia_agents_journey: true,
            agentes_painel_desempenho: true,
          },
        });
      };
      preparar({ agente: bia() });
      ligarPainel();
      const atendimento = await montar();
      expect(no('[data-ver-tudo]')).not.toBeNull();
      atendimento.unmount();

      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      ligarPainel();
      const cotacao = await montar();
      expect(no('[data-ver-tudo]')).toBeNull();
      cotacao.unmount();
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

    it('keeps the Team copilot answering without a channel (#1366)', async () => {
      preparar({
        agente: bia({
          actuation: 'internal',
          channels_count: 0,
          tem_onde_trabalhar: true,
        }),
      });
      const wrapper = await montar();
      expect(no('[role="switch"]').getAttribute('aria-checked')).toBe('true');
      expect(no('[data-heroi] [data-onde]')).toBeNull();
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

  // O agente externo aparece para o cliente com a foto do canal conectado; o interno tem foto própria.
  describe('foto do canal', () => {
    const FOTO_CANAL = 'https://x/whats.png';
    const comFotoNoCanal = (extra = {}) =>
      preparar({
        agente: bia({ avatar_url: 'https://x/propria.png' }),
        caixas: [
          { id: 1, working_hours_enabled: false, avatar_url: FOTO_CANAL },
        ],
        ...extra,
      });
    const fotoDoHeroi = () =>
      no('[data-heroi] [data-avatar] img')?.getAttribute('src');

    it('shows the channel photo in the hero and offers only the name', async () => {
      comFotoNoCanal();
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe(FOTO_CANAL);

      await clicar('[data-mais]');
      const item = no('[data-item="foto"]');
      expect(item.textContent).toContain('FOTO.TITULO_NOME');
      item.click();
      await flushPromises();

      const gaveta = no('[role="dialog"]');
      expect(gaveta.textContent).toContain('FOTO.TITULO_NOME');
      expect(gaveta.querySelector('[data-trocar-foto]')).toBeNull();
      expect(gaveta.querySelector('[data-tirar-foto]')).toBeNull();
      expect(gaveta.querySelector('[data-seletor]')).toBeNull();
      expect(
        gaveta.querySelector('[data-avatar] img').getAttribute('src')
      ).toBe(FOTO_CANAL);
      expect(
        gaveta.querySelector('[data-foto-do-canal]').textContent
      ).toContain('FOTO.FOTO_DO_CANAL');
      wrapper.unmount();
    });

    it('falls back to the agent photo when the inbox has none', async () => {
      comFotoNoCanal({
        caixas: [{ id: 1, working_hours_enabled: false, avatar_url: '' }],
      });
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe('https://x/propria.png');
      wrapper.unmount();
    });

    it('uses the first inbox, in the order of "Answers on…", with more than one', async () => {
      comFotoNoCanal({
        canais: [
          {
            inbox_id: 2,
            name: 'Instagram',
            occupied_by: { kind: 'agent', agent_id: 7 },
          },
          L2[0],
        ],
        caixas: [
          { id: 1, working_hours_enabled: false, avatar_url: FOTO_CANAL },
          {
            id: 2,
            working_hours_enabled: false,
            avatar_url: 'https://x/i.png',
          },
        ],
      });
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe('https://x/i.png');
      wrapper.unmount();
    });

    it('keeps the own photo and "Change photo" for the internal agent', async () => {
      comFotoNoCanal({
        agente: bia({
          actuation: 'internal',
          channels_count: 0,
          avatar_url: 'https://x/propria.png',
        }),
      });
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe('https://x/propria.png');
      await clicar('[data-mais]');
      const item = no('[data-item="foto"]');
      expect(item.textContent).toContain('FOTO.TITULO');
      expect(item.textContent).not.toContain('TITULO_NOME');
      item.click();
      await flushPromises();
      expect(no('[role="dialog"] [data-trocar-foto]')).not.toBeNull();
      expect(no('[data-foto-do-canal]')).toBeNull();
      wrapper.unmount();
    });

    it('keeps the quoting agent with its own photo and "Photo and name"', async () => {
      comFotoNoCanal({
        agente: bia({
          agent_type: 'insurance_quote',
          avatar_url: 'https://x/propria.png',
        }),
      });
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe('https://x/propria.png');
      await clicar('[data-mais]');
      expect(no('[data-item="foto"]').textContent).not.toContain('TITULO_NOME');
      wrapper.unmount();
    });

    it('goes from the drawer note to Mudar conversando, like the hero button', async () => {
      comNotaDaGaveta();
      onTestFinished(semMensagens);
      comFotoNoCanal();
      const wrapper = await montar();
      await clicar('[data-mais]');
      await clicar('[data-item="foto"]');
      const link = no('[role="dialog"] [data-ir-mudar]');
      expect(link.textContent).toContain('FOTO.NOTA_ACAO');
      await clicar('[data-ir-mudar]');
      expect(no('[role="dialog"]')).toBeNull();
      expect(no('[data-heroi]')).toBeNull();
      expect(no('[data-abertura]')).not.toBeNull();
      wrapper.unmount();
    });

    it('shows "Mudar conversando" only in bold for an agent written by hand', async () => {
      comNotaDaGaveta();
      onTestFinished(semMensagens);
      comFotoNoCanal({ agente: bia({ mode: 'manual' }) });
      const wrapper = await montar();
      await clicar('[data-mais]');
      await clicar('[data-item="foto"]');
      expect(no('[data-ir-mudar]')).toBeNull();
      expect(no('[role="dialog"] [data-acao-texto]').textContent).toContain(
        'FOTO.NOTA_ACAO'
      );
      wrapper.unmount();
    });

    it('shows the channel photo to view-only seats, with nothing to write', async () => {
      estado.podeGerenciar = false;
      comFotoNoCanal();
      const wrapper = await montar();
      expect(fotoDoHeroi()).toBe(FOTO_CANAL);
      await clicar('[data-mais]');
      expect(no('[data-item="foto"]')).toBeNull();
      wrapper.unmount();
    });
  });

  // Regressão do piloto (conta 16): o painel antigo tinha a aba "Ferramentas" para o SuperAdmin que
  // gerencia; a página nova a oferece em "Mais opções", numa gaveta com o PanelTools existente.
  describe('ferramentas (SuperAdmin)', () => {
    const comoSuperAdmin = () => {
      store.state.getCurrentUser = { id: 1, type: 'SuperAdmin' };
      agentesApi.getTools.mockResolvedValue({ data: { payload: [] } });
    };

    it('lets a SuperAdmin open Tools from More options, in a trapped drawer', async () => {
      comoSuperAdmin();
      const wrapper = await montar();
      await clicar('[data-mais]');
      expect(todos('[role="menuitem"]').map(i => i.dataset.item)).toEqual([
        'foto',
        'versoes',
        'instrucoes',
        'ferramentas',
        'excluir',
      ]);
      expect(no('[data-item="ferramentas"]').textContent).toContain(
        'FERRAMENTAS.MENU'
      );
      await clicar('[data-item="ferramentas"]');
      const gaveta = no('[role="dialog"]');
      expect(gaveta.getAttribute('aria-modal')).toBe('true');
      expect(gaveta.textContent).toContain('FERRAMENTAS.TITULO');
      expect(gaveta.querySelector('[data-ferramentas]')).not.toBeNull();
      expect(agentesApi.getTools).toHaveBeenCalledWith(7);
      wrapper.unmount();
    });

    it('hides Tools from an account admin who is not SuperAdmin', async () => {
      store.state.getCurrentUser = {
        id: 2,
        type: 'User',
        role: 'administrator',
      };
      const wrapper = await montar({ gaveta: 'ferramentas' });
      expect(no('[role="dialog"]')).toBeNull();
      await clicar('[data-mais]');
      expect(no('[data-item="ferramentas"]')).toBeNull();
      expect(agentesApi.getTools).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('hides Tools from a SuperAdmin seat that only views', async () => {
      comoSuperAdmin();
      estado.podeGerenciar = false;
      const wrapper = await montar();
      await clicar('[data-mais]');
      expect(no('[data-item="ferramentas"]')).toBeNull();
      wrapper.unmount();
    });

    it('offers Tools on the quoting agent too, like the old panel', async () => {
      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      comoSuperAdmin();
      const wrapper = await montar();
      await clicar('[data-mais]');
      expect(todos('[role="menuitem"]').map(i => i.dataset.item)).toEqual([
        'foto',
        'ferramentas',
      ]);
      wrapper.unmount();
    });

    it('opens Tools from the old :tab "tools" for a SuperAdmin', async () => {
      comoSuperAdmin();
      const wrapper = await montar({ gaveta: 'ferramentas' });
      expect(no('[role="dialog"] [data-ferramentas]')).not.toBeNull();
      wrapper.unmount();
    });
  });

  // #1433 (tema 13) — agente da equipe: "Na equipe", "Onde {nome} trabalha" (caixa e papel) e "Mudar"
  // direto nos passos do agente da equipe.
  // #1433 ("a, para todos os agentes"): quem atende primeiro também recebe em outras caixas quando alguém
  // passa — a seção na gaveta "Onde e quando" e a linha no resumo. Só com a Fase 2.
  describe('também recebe em outras caixas', () => {
    const COM_AREA = [
      ...L2,
      {
        inbox_id: 3,
        name: 'WhatsApp dos Jardins',
        occupied_by: {
          kind: 'agent',
          agent_id: 9,
          agent_name: 'Duda',
          operating: true,
        },
        areas: [{ agent_id: 7, agent_name: 'Bia', operating: true }],
      },
      {
        inbox_id: 4,
        name: 'WhatsApp Recepção',
        occupied_by: null,
        so_de_pessoas: true,
      },
    ];
    const ligarFase2 = ligada => {
      store.state.getCurrentAccountId = 1;
      store.state['accounts/getAccount'] = () => ({
        autonomia_agents_fase2: ligada,
      });
    };

    it('shows the other inboxes in the summary and the section in the drawer', async () => {
      preparar({ canais: COM_AREA });
      ligarFase2(true);
      const wrapper = await montar();
      // #1720, com a Fase 2: uma linha só, a mesma do herói.
      expect(
        no('[data-linha="onde"] [data-resumo-onde]').textContent
      ).toContain('BLOCO_ONDE.PRIMEIRO_E_RECEBE');
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'BLOCO_ONDE.PRIMEIRO_E_RECEBE'
      );
      await clicar('[data-alterar="onde"]');
      const secao = no('aside[role="dialog"] [data-tambem-recebe]');
      expect(secao).not.toBeNull();
      expect(
        secao.querySelector('[data-opcao="3"]').getAttribute('aria-checked')
      ).toBe('true');
      expect(
        secao.querySelector('[data-opcao="4"]').getAttribute('aria-disabled')
      ).toBeNull();
      expect(secao.querySelector('[data-opcao="1"]')).toBeNull();
      wrapper.unmount();
    });

    it('reads the agent again after saving where it answers (the server may have stopped it)', async () => {
      canaisApi.ondeAtende.mockResolvedValue({});
      preparar({ canais: COM_AREA });
      ligarFase2(true);
      const wrapper = await montar();
      await clicar('[data-alterar="onde"]');
      await clicar('aside[role="dialog"] [data-confirmar]');

      expect(canaisApi.ondeAtende).toHaveBeenCalledWith(
        7,
        expect.objectContaining({ primeiroInboxId: 1, manterPrimeiro: true })
      );
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7);
      wrapper.unmount();
    });

    it('with the Fase 2, a stopped agent hero lists the channels and never says "answers first"', async () => {
      preparar({ agente: bia({ status: 'paused' }), canais: COM_AREA });
      ligarFase2(true);
      const wrapper = await montar();
      const heroi = no('[data-heroi] [data-onde]').textContent;
      expect(heroi).toContain('BLOCO_ONDE.PARADO');
      expect(heroi).not.toContain('BLOCO_ONDE.PRIMEIRO');
      expect(no('[data-resumo-onde]').textContent).toContain(
        'BLOCO_ONDE.PARADO'
      );
      wrapper.unmount();
    });

    it('the quote agent (Lia) gets the section too', async () => {
      preparar({
        agente: bia({ name: 'Lia', agent_type: 'insurance_quote' }),
        canais: COM_AREA,
      });
      ligarFase2(true);
      const wrapper = await montar();
      await clicar('[data-alterar="onde"]');
      expect(no('aside[role="dialog"] [data-tambem-recebe]')).not.toBeNull();
      wrapper.unmount();
    });

    it('without the Fase 2, nothing changes (no regression)', async () => {
      preparar({ canais: COM_AREA });
      ligarFase2(false);
      const wrapper = await montar();
      expect(no('[data-tambem-recebe]')).toBeNull();
      // #1720: sem a Fase 2, os textos de antes (herói e resumo) e a gaveta de antes.
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.RESPONDE_NO'
      );
      expect(no('[data-linha="onde"]').textContent).toContain(
        'PAGINA.BLOCO_ONDE.TEXTO'
      );
      expect(no('[data-resumo-onde]')).toBeNull();
      await clicar('[data-alterar="onde"]');
      expect(no('aside[role="dialog"]')).not.toBeNull();
      expect(no('[data-tambem-recebe]')).toBeNull();
      expect(no('aside[role="dialog"] [data-nao-atender]')).not.toBeNull();
      expect(no('aside[role="dialog"] [data-primeiro]')).toBeNull();
      wrapper.unmount();
    });
  });

  describe('agente da equipe', () => {
    const L2_EQUIPE = [
      {
        inbox_id: 1,
        name: 'WhatsApp do Centro',
        channel_type: 'Channel::Whatsapp',
        occupied_by: {
          kind: 'agent',
          agent_id: 3,
          agent_name: 'Sofia',
          operating: true,
        },
        areas: [{ agent_id: 7, agent_name: 'Bia', operating: true }],
      },
      {
        inbox_id: 2,
        name: 'Instagram',
        channel_type: 'Channel::Instagram',
        occupied_by: {
          kind: 'agent',
          agent_id: 4,
          agent_name: 'Leo',
          operating: true,
        },
        areas: [],
      },
      { inbox_id: 5, name: 'Site', occupied_by: null, areas: [] },
    ];

    const prepararEquipe = (extra = {}) =>
      preparar({
        agente: bia({ na_equipe: true, tem_onde_trabalhar: true, ...extra }),
        canais: L2_EQUIPE,
      });
    const ligarFase2 = ligada => {
      store.state.getCurrentAccountId = 1;
      store.state['accounts/getAccount'] = () => ({
        autonomia_agents_fase2: ligada,
      });
    };

    it('says "Na equipe" (switch on), where it receives, and never the parked banner', async () => {
      prepararEquipe();
      const wrapper = await montar();
      expect(no('[data-interruptor]').getAttribute('aria-checked')).toBe(
        'true'
      );
      expect(no('[data-interruptor]').textContent).toContain(
        'AGENTS.JORNADA.STATUS.NA_EQUIPE'
      );
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'AGENTS.JORNADA.CARTAO.RECEBE_EM'
      );
      expect(no('[data-faixa-parado]')).toBeNull();
      wrapper.unmount();
    });

    it('swaps "Onde e quando responde" for "Onde {nome} trabalha", with only the inbox and the role', async () => {
      prepararEquipe();
      const wrapper = await montar();
      const bloco = no('[data-linha="onde-trabalha"]');
      expect(bloco.textContent).toContain('AGENTS.JORNADA.ONDE.TITULO');
      expect(bloco.textContent).toContain('WhatsApp do Centro');
      expect(bloco.textContent).toContain('AGENTS.JORNADA.ONDE.RECEBE');
      expect(bloco.textContent).not.toContain('Instagram');
      expect(no('[data-linha="onde"]')).toBeNull();
      wrapper.unmount();
    });

    it('"Mudar" opens straight in the team steps, saves the change and reads the agent again', async () => {
      prepararEquipe();
      const wrapper = await montar();
      await clicar('[data-mudar-equipe]');
      expect(no('[data-equipe-canais]').dataset.passo).toBe('canais');
      expect(no('[data-opcao="1"]').getAttribute('aria-checked')).toBe('true');
      expect(no('[data-opcao="5"]').getAttribute('aria-disabled')).toBe('true');

      await clicar('[data-opcao="2"]');
      await clicar('[data-seguir-equipe]');
      expect(no('[data-equipe-canais]').dataset.passo).toBe('confira');
      await clicar('[data-seguir-equipe]');

      expect(canaisApi.connect).toHaveBeenCalledWith(7, 2, { papel: 'area' });
      expect(canaisApi.disconnect).not.toHaveBeenCalled();
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.EQUIPE.FEITO');
      expect(no('[data-equipe-canais]')).toBeNull();
      wrapper.unmount();
    });

    it('with the Fase 2, the hero says the same line: receives when someone hands over', async () => {
      prepararEquipe();
      ligarFase2(true);
      const wrapper = await montar();
      expect(no('[data-interruptor]').textContent).toContain(
        'AGENTS.JORNADA.STATUS.NA_EQUIPE'
      );
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'PAGINA.BLOCO_ONDE.RECEBE'
      );
      wrapper.unmount();
    });

    it('uses "Onde e quando responde" and the same drawer, answering "Não" with its team inboxes', async () => {
      prepararEquipe();
      ligarFase2(true);
      const wrapper = await montar();
      expect(no('[data-linha="onde-trabalha"]')).toBeNull();
      expect(
        no('[data-linha="onde"] [data-resumo-onde]').textContent
      ).toContain('BLOCO_ONDE.RECEBE');
      await clicar('[data-alterar="onde"]');
      const gaveta = no('aside[role="dialog"]');
      expect(gaveta.textContent).toContain('PAGINA.ONDE.TITULO');
      const nao = [...gaveta.querySelectorAll('[role="radio"]')].find(item =>
        item.textContent.includes('PRIMEIRO_NAO')
      );
      expect(nao.getAttribute('aria-checked')).toBe('true');
      expect(
        gaveta.querySelector('[data-opcao="1"]').getAttribute('aria-checked')
      ).toBe('true');
      await clicar('aside[role="dialog"] [data-confirmar]');
      expect(canaisApi.ondeAtende).toHaveBeenCalledWith(7, {
        primeiroInboxId: null,
        manterPrimeiro: false,
        areaInboxIds: [1],
        responseWindow: 'always',
        parar: false,
      });
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7);
      wrapper.unmount();
    });

    it('without the inbox reading, says only that it receives when someone hands over', async () => {
      prepararEquipe();
      ligarFase2(true);
      canaisApi.get.mockRejectedValue(new Error('500'));
      jornadaApi.canaisOcupados.mockRejectedValue(new Error('500'));
      const wrapper = await montar();
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'AGENTS.JORNADA.ONDE.RECEBE'
      );
      expect(no('[data-heroi] [data-onde]').textContent).not.toContain(
        'NENHUM_LUGAR'
      );
      wrapper.unmount();
    });

    it('turning a stopped team agent back on does not ask for an inbox', async () => {
      prepararEquipe({ status: 'paused', enabled: false });
      const wrapper = await montar();
      expect(no('[data-faixa-parado]')).not.toBeNull();
      await clicar('[data-interruptor]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        enabled: true,
        status: 'active',
      });
      expect(no('aside[role="dialog"]')).toBeNull();
      wrapper.unmount();
    });

    it('keeps the main agent page as it was (no regression)', async () => {
      const wrapper = await montar();
      expect(no('[data-linha="onde"]')).not.toBeNull();
      expect(no('[data-linha="onde-trabalha"]')).toBeNull();
      expect(no('[data-interruptor]').textContent).toContain(
        'AGENTS.JORNADA.STATUS.ATENDENDO'
      );
      wrapper.unmount();
    });
  });

  // Tema 14 (#1434) — a página do ajudante: "Ajudando", sem "Testar" (como cliente) e sem "Quando passa para a
  // equipe"; "Quem {nome} ajuda" e "Quando chamar", com "Mudar" abrindo direto os passos do ajudante.
  describe('ajudante', () => {
    const CLARA = { id: 3, name: 'Clara' };
    const BRUNO = { id: 4, name: 'Bruno' };
    const DA_CONTA = [
      { ...bia({ id: 3, name: 'Clara' }) },
      { ...bia({ id: 4, name: 'Bruno' }) },
      bia({ id: 5, name: 'Ana', actuation: 'internal' }),
      bia({ id: 6, name: 'Lia', agent_type: 'insurance_quote' }),
    ];
    const ajudanteBia = (extra = {}) =>
      bia({
        actuation: 'internal',
        ajudante: true,
        ajuda: [CLARA, BRUNO],
        tem_onde_trabalhar: true,
        channels_count: 0,
        ...extra,
      });

    const prepararAjudante = (extra = {}) => {
      preparar({ agente: ajudanteBia(extra), canais: [] });
      agentesApi.getAjuda.mockResolvedValue({
        data: { quando: 'Dúvidas de troca', principais: [CLARA, BRUNO] },
      });
      agentesApi.updateAjuda.mockReset();
      agentesApi.updateAjuda.mockResolvedValue({
        data: { quando: 'Dúvidas de prazo', principais: [CLARA] },
      });
      const original = store.dispatch.getMockImplementation();
      store.dispatch.mockImplementation(async (acao, dados) => {
        if (acao === 'autonomiaAgents/get') {
          store.state['autonomiaAgents/getRecords'] = [
            ...DA_CONTA,
            ajudanteBia(extra),
          ];
          return null;
        }
        return original(acao, dados);
      });
    };

    it('says "Ajudando" (switch on, named for helping agents) and who it helps in the hero', async () => {
      prepararAjudante();
      const wrapper = await montar();
      const interruptor = no('[data-interruptor]');
      expect(interruptor.getAttribute('aria-checked')).toBe('true');
      expect(interruptor.textContent).toContain(
        'AGENTS.JORNADA.STATUS.AJUDANDO'
      );
      expect(interruptor.getAttribute('aria-label')).toBe(
        'AGENTS.JORNADA.PAGINA.INTERRUPTOR_AJUDANTE'
      );
      expect(no('[data-heroi] [data-onde]').textContent).toContain(
        'AGENTS.JORNADA.ONDE.AJUDA'
      );
      expect(no('[data-faixa-parado]')).toBeNull();
      wrapper.unmount();
    });

    it('hides "Testar" as a customer and "Quando passa para a equipe", and shows who it helps and when to call', async () => {
      prepararAjudante();
      const wrapper = await montar();
      expect(no('[data-bloco="testar"]')).toBeNull();
      expect(no('[data-bloco="passa"]')).toBeNull();
      expect(no('[data-linha="onde"]')).toBeNull();
      expect(no('[data-linha="quem-ajuda"]').textContent).toContain(
        'AGENTS.JORNADA.AJUDANTE.QUEM_AJUDA'
      );
      expect(no('[data-quem-ajuda]').textContent).toContain('Clara, Bruno');
      expect(agentesApi.getAjuda).toHaveBeenCalledWith(7);
      expect(no('[data-quando-chamar]').textContent).toContain(
        'Dúvidas de troca'
      );
      // O que sabe e o jeito de falar continuam.
      expect(no('[data-linha="sabe"]')).not.toBeNull();
      expect(no('[data-linha="jeito"]')).not.toBeNull();
      wrapper.unmount();
    });

    it('"Mudar" on "Quando chamar" opens straight in the second step and saves with one PUT', async () => {
      prepararAjudante();
      const wrapper = await montar();
      await clicar('[data-mudar-ajuda="quando"]');
      expect(no('[data-ajudante-passos]').dataset.passo).toBe('quando');
      const campo = no('[data-quando]');
      expect(campo.value).toBe('Dúvidas de troca');
      campo.value = 'Dúvidas de prazo';
      campo.dispatchEvent(new Event('input'));
      await flushPromises();
      await clicar('[data-seguir-ajudante]');

      expect(agentesApi.updateAjuda).toHaveBeenCalledWith(7, {
        principalIds: [3, 4],
        quando: 'Dúvidas de prazo',
      });
      expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.AJUDANTE.FEITO');
      expect(no('[data-ajudante-passos]')).toBeNull();
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/show', 7);
      wrapper.unmount();
    });

    it('"Mudar" on who it helps reads the account agents, keeps the copilot out and the quote agent locked with the reason', async () => {
      prepararAjudante();
      const wrapper = await montar();
      await clicar('[data-mudar-ajuda="quem"]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/get');
      expect(no('[data-ajudante-passos]').dataset.passo).toBe('quem');
      expect(no('[data-opcao="3"]').getAttribute('aria-checked')).toBe('true');
      expect(no('[data-opcao="5"]')).toBeNull();
      expect(no('[data-opcao="7"]')).toBeNull();
      expect(no('[data-opcao="6"]').getAttribute('aria-disabled')).toBe('true');
      expect(no('[data-aviso-ajudante]').textContent).toContain(
        'AGENTS.JORNADA.AJUDANTE.AVISO'
      );

      await clicar('[data-opcao="4"]');
      await clicar('[data-seguir-ajudante]');
      await clicar('[data-seguir-ajudante]');
      expect(agentesApi.updateAjuda).toHaveBeenCalledWith(7, {
        principalIds: [3],
        quando: 'Dúvidas de troca',
      });
      wrapper.unmount();
    });

    it('keeps the drawer open with the server reason when the change is refused', async () => {
      prepararAjudante();
      agentesApi.updateAjuda.mockRejectedValue({
        response: {
          status: 422,
          data: { error: 'Ajudante não chama outro ajudante.' },
        },
      });
      const wrapper = await montar();
      await clicar('[data-mudar-ajuda="quando"]');
      await clicar('[data-seguir-ajudante]');
      expect(no('[data-erro-salvar]').textContent).toContain(
        'Ajudante não chama outro ajudante.'
      );
      expect(no('[data-ajudante-passos]')).not.toBeNull();
      expect(alerta).not.toHaveBeenCalled();
      wrapper.unmount();
    });

    it('stopping speaks of helping, never of answering nor of conversations going to the team', async () => {
      prepararAjudante();
      const wrapper = await montar();
      await clicar('[role="switch"]');
      const dialogo = no('dialog[open]').textContent;
      expect(dialogo).toContain(
        'AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_TITULO'
      );
      expect(dialogo).toContain(
        'AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_TEXTO'
      );
      expect(dialogo).not.toContain('PAGINA.PARAR.TEXTO');
      await clicar('dialog[open] [data-confirmar]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        status: 'paused',
      });
      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.PARAR_FEITO'
      );
      wrapper.unmount();
    });

    it('turning a stopped helper back on says it helps again, without asking for an inbox', async () => {
      prepararAjudante({ status: 'paused', enabled: false });
      const wrapper = await montar();
      await clicar('[role="switch"]');
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        enabled: true,
        status: 'active',
      });
      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.VOLTOU'
      );
      expect(no('[data-ajudante-passos]')).toBeNull();
      wrapper.unmount();
    });

    it('a stopped helper with nobody to help opens "who it helps" instead of turning on, and turns on after saving', async () => {
      prepararAjudante({ status: 'paused', enabled: false, ajuda: [] });
      const wrapper = await montar();
      await clicar('[role="switch"]');
      expect(no('[data-ajudante-passos]').dataset.passo).toBe('quem');
      expect(
        store.dispatch.mock.calls.some(
          ([acao]) => acao === 'autonomiaAgents/update'
        )
      ).toBe(false);

      await clicar('[data-opcao="3"]');
      await clicar('[data-seguir-ajudante]');
      await clicar('[data-seguir-ajudante]');
      expect(agentesApi.updateAjuda).toHaveBeenCalledWith(7, {
        principalIds: [3],
        quando: 'Dúvidas de troca',
      });
      expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
        id: 7,
        enabled: true,
        status: 'active',
      });
      expect(alerta).toHaveBeenCalledWith(
        'AGENTS.JORNADA.AJUDANTE.INTERRUPTOR.VOLTOU'
      );
      wrapper.unmount();
    });

    it('a view only seat reads who it helps without any "Mudar"', async () => {
      estado.podeGerenciar = false;
      prepararAjudante();
      const wrapper = await montar();
      expect(no('[data-quem-ajuda]').textContent).toContain('Clara, Bruno');
      expect(no('[data-mudar-ajuda]')).toBeNull();
      wrapper.unmount();
    });

    it('keeps the team copilot page as it was: testing, the hand over block and no "Quem ajuda"', async () => {
      preparar({
        agente: bia({ actuation: 'internal', ajudante: false, ajuda: [] }),
        canais: [],
      });
      agentesApi.getAjuda.mockReset();
      const wrapper = await montar();
      expect(no('[data-bloco="testar"]')).not.toBeNull();
      expect(no('[data-bloco="passa"]')).not.toBeNull();
      expect(no('[data-linha="quem-ajuda"]')).toBeNull();
      expect(agentesApi.getAjuda).not.toHaveBeenCalled();
      expect(no('[data-interruptor]').getAttribute('aria-label')).toBe(
        'AGENTS.JORNADA.PAGINA.INTERRUPTOR'
      );
      wrapper.unmount();
    });
  });

  // #1429 F3 — a linha "Base de seguros", só com a Fase 2 e fora da Lia.
  describe('base de seguros', () => {
    const comFase2 = () => {
      store.state['accounts/getAccount'] = () => ({
        autonomia_agents_fase2: true,
      });
      store.state.getCurrentAccountId = 1;
    };
    const semBase = {
      situacao: 'sem_base',
      atual: null,
      nova: { segmento: 'seguros/corretora', data: '2026-10-21', versao: 'v' },
      pode_atualizar: true,
      desfazer: null,
    };

    beforeEach(() => {
      Object.values(baseApi).forEach(fn => fn.mockReset());
      baseApi.ler.mockResolvedValue({ data: semBase });
    });

    it('shows the line below the name and voice, with the button for who manages', async () => {
      comFase2();
      const wrapper = await montar();
      expect(baseApi.ler).toHaveBeenCalledWith(7);
      expect(no('[data-linha="base"]')).not.toBeNull();
      expect(no('[data-base-atualizar]')).not.toBeNull();
      wrapper.unmount();
    });

    it('opens the before and after drawer from the button', async () => {
      comFase2();
      baseApi.comparar.mockReturnValue(new Promise(() => {}));
      const wrapper = await montar();
      await clicar('[data-base-atualizar]');
      expect(no('[data-comparando]')).not.toBeNull();
      expect(baseApi.comparar).toHaveBeenCalledWith(7, expect.any(AbortSignal));
      wrapper.unmount();
    });

    it('who only views sees the line without the button', async () => {
      comFase2();
      estado.podeGerenciar = false;
      const wrapper = await montar();
      expect(no('[data-linha="base"]')).not.toBeNull();
      expect(no('[data-base-atualizar]')).toBeNull();
      wrapper.unmount();
    });

    it('without the Fase 2 it does not even ask', async () => {
      const wrapper = await montar();
      expect(baseApi.ler).not.toHaveBeenCalled();
      expect(no('[data-linha="base"]')).toBeNull();
      wrapper.unmount();
    });

    it('the quote agent (Lia) has no line', async () => {
      preparar({ agente: bia({ agent_type: 'insurance_quote' }) });
      comFase2();
      const wrapper = await montar();
      expect(baseApi.ler).not.toHaveBeenCalled();
      expect(no('[data-linha="base"]')).toBeNull();
      wrapper.unmount();
    });

    it('a failed read hides the line, with no error', async () => {
      comFase2();
      baseApi.ler.mockRejectedValue(new Error('404'));
      const wrapper = await montar();
      expect(no('[data-linha="base"]')).toBeNull();
      expect(alerta).not.toHaveBeenCalled();
      wrapper.unmount();
    });
  });
});
