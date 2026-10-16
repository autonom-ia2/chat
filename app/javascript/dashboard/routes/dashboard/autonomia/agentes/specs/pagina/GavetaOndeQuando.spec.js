import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import GavetaOndeQuando from '../../components/pagina/GavetaOndeQuando.vue';

// T10 · Onde e quando, e "Voltar a atender" (a confirmação de canal do T05).
const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const permissoes = vi.hoisted(() => ({ conectar: true }));
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => permissoes.conectar),
      podeEscolherQuemRecebe: computed(() => true),
      crmLigado: computed(() => true),
    }),
  };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));
const canaisApi = vi.hoisted(() => ({
  connect: vi.fn(),
  disconnect: vi.fn(),
  ondeAtende: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};

const AGENTE = {
  id: 7,
  name: 'Bia',
  status: 'active',
  enabled: true,
  config: { response_window: 'always' },
};
const CANAIS = [
  {
    inbox_id: 1,
    name: 'WhatsApp do Centro',
    occupied_by: { kind: 'agent', agent_id: 7, agent_name: 'Bia' },
  },
  { inbox_id: 2, name: 'Instagram', occupied_by: null },
  {
    inbox_id: 3,
    name: 'WhatsApp dos Jardins',
    occupied_by: { kind: 'agent', agent_id: 9, agent_name: 'Duda' },
  },
  { inbox_id: 4, name: 'Site', occupied_by: { kind: 'external' } },
];

const montar = props =>
  mount(GavetaOndeQuando, {
    attachTo: document.body,
    props: {
      agente: AGENTE,
      nome: 'Bia',
      atendendo: true,
      canais: CANAIS,
      atuais: [CANAIS[0]],
      horarios: { 1: 'seg. a sex., das 9h às 18h', 2: null },
      ...props,
    },
  });

const radio = texto =>
  todos('[role="radio"]').find(item => item.textContent.includes(texto));

const naoMandouCamposDoPainelAntigo = () => {
  const proibidos = [
    'greeting',
    'fallback_message',
    'handoff_strategy',
    'confidence_threshold',
  ];
  store.dispatch.mock.calls.forEach(([, dados]) => {
    proibidos.forEach(campo => expect(dados).not.toHaveProperty(campo));
  });
};

describe('GavetaOndeQuando', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
      this.setAttribute('open', '');
    });
    HTMLDialogElement.prototype.close = vi.fn(function fechar() {
      this.removeAttribute('open');
    });
  });

  beforeEach(() => {
    store.dispatch.mockReset();
    store.dispatch.mockResolvedValue({});
    canaisApi.connect.mockReset();
    canaisApi.connect.mockResolvedValue({});
    canaisApi.disconnect.mockReset();
    canaisApi.disconnect.mockResolvedValue({});
    canaisApi.ondeAtende.mockReset();
    canaisApi.ondeAtende.mockResolvedValue({});
    alerta.mockReset();
    permissoes.conectar = true;
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  // #1720 — o "Salvar" do modo alterar é um pedido só (PUT onde_atende), gravado numa transação.
  const pedido = () => canaisApi.ondeAtende.mock.calls[0];

  it('saves the response window in the single request when only "when" changed', async () => {
    const wrapper = montar();
    radio('AGENTS.JORNADA.ONDE_QUANDO.DENTRO').click();
    await nextTick();
    await clicar('[data-confirmar]');

    expect(pedido()).toEqual([
      7,
      {
        primeiroInboxId: 1,
        areaInboxIds: null,
        responseWindow: 'business_hours',
        parar: false,
      },
    ]);
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.ONDE.PRONTO');
    expect(wrapper.emitted('pronto')).toHaveLength(1);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('moves to a free inbox in one request; the server leaves the old one', async () => {
    const wrapper = montar();
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    expect(pedido()[1]).toMatchObject({ primeiroInboxId: 2, parar: false });
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(canaisApi.disconnect).not.toHaveBeenCalled();
    naoMandouCamposDoPainelAntigo();
    wrapper.unmount();
  });

  it('warns about the swap of a busy inbox and sends it in the same request', async () => {
    const wrapper = montar();
    expect(radio('ONDE_QUANDO.OCUPADO').className).toContain('bg-n-amber-2');
    expect(radio('Instagram').className).not.toContain('bg-n-amber-2');
    radio('ONDE_QUANDO.OCUPADO').click();
    await nextTick();
    expect(no('[data-troca]').textContent).toContain('ONDE_QUANDO.TROCA');
    expect(no('[data-troca]').className).toContain('ring-n-amber-6');
    expect(no('[data-troca] .i-lucide-triangle-alert')).not.toBeNull();
    await clicar('[data-confirmar]');

    expect(pedido()[1]).toMatchObject({ primeiroInboxId: 3 });
    expect(canaisApi.disconnect).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows the server explanation and keeps the drawer open when it refuses (nothing changed)', async () => {
    canaisApi.ondeAtende.mockRejectedValueOnce(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: {
            error: 'Não deu para tirar Bia de WhatsApp do Centro. Nada mudou.',
            code: 'saida_recusada',
          },
        },
      })
    );
    const wrapper = montar();
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    const erro = no('[data-erro]');
    expect(erro.textContent).toContain(
      'Não deu para tirar Bia de WhatsApp do Centro. Nada mudou.'
    );
    expect(erro.textContent).toContain('PAGINA.ONDE.ERRO_GARANTIA');
    expect(wrapper.emitted('pronto')).toHaveLength(1);
    expect(wrapper.emitted('fechar')).toBeUndefined();
    expect(alerta).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('says the standard save error when the request does not reach the server', async () => {
    canaisApi.ondeAtende.mockRejectedValueOnce(new Error('network'));
    const wrapper = montar();
    radio('AGENTS.JORNADA.ONDE_QUANDO.FORA').click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(no('[data-erro]').textContent).toContain(
      'AGENTS.JORNADA.ERRO.OFFLINE'
    );
    wrapper.unmount();
  });

  it('no longer offers "do not answer anywhere"', () => {
    const wrapper = montar();
    expect(no('[data-nao-atender]')).toBeNull();
    expect(document.querySelector('dialog')).toBeNull();
    wrapper.unmount();
  });

  it('keeps the inbox read-only for a stopped agent and offers to start again (t10-parado)', async () => {
    const wrapper = montar({ atendendo: false });
    expect(no('[data-parado]').textContent).toContain('WhatsApp do Centro');
    expect(no('[data-parado]').textContent).toContain('PAGINA.ONDE.PARADO');
    expect(radio('Instagram')).toBeUndefined();

    await clicar('[data-voltar]');
    expect(wrapper.emitted('voltarAAtender')).toHaveLength(1);

    radio('AGENTS.JORNADA.ONDE_QUANDO.DENTRO').click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(store.dispatch.mock.calls).toEqual([
      [
        'autonomiaAgents/update',
        { id: 7, config: { response_window: 'business_hours' } },
      ],
    ]);
    wrapper.unmount();
  });

  // #1525 — quem não está em canal nenhum (a Lia que nasceu parada) começa a atender; não "volta".
  it('says "start answering" to an agent that is on no channel', async () => {
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      atuais: [],
      agente: {
        ...AGENTE,
        status: 'paused',
        enabled: false,
        channels_count: 0,
      },
    });
    radio('Instagram').click();
    await nextTick();
    const botao = no('[data-confirmar]').textContent;
    expect(botao).toContain('PAGINA.ONDE.COMECAR');
    expect(botao).not.toContain('PAGINA.ONDE.VOLTAR');
    await clicar('[data-confirmar]');
    expect(canaisApi.connect).toHaveBeenCalledWith(7, 2, { ativar: true });
    wrapper.unmount();
  });

  it('keeps "start answering again" while the channel count says it still has one', async () => {
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      atuais: [],
      estadoCanais: 'carregando',
      canais: CANAIS,
      agente: { ...AGENTE, status: 'paused', channels_count: 1 },
    });
    expect(no('[data-confirmar]').textContent).toContain('PAGINA.ONDE.VOLTAR');
    wrapper.unmount();
  });

  it('starts answering again on the same inbox with only the active PATCH', async () => {
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      agente: { ...AGENTE, status: 'paused' },
    });
    expect(no('[data-confirmar]').textContent).toContain('PAGINA.ONDE.VOLTAR');
    await clicar('[data-confirmar]');

    expect(store.dispatch.mock.calls).toEqual([
      ['autonomiaAgents/update', { id: 7, enabled: true, status: 'active' }],
    ]);
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.ONDE.VOLTOU');
    wrapper.unmount();
  });

  it('shows "could not start answering" with the guarantee (t17-comecar)', async () => {
    canaisApi.connect.mockRejectedValueOnce(
      Object.assign(new Error('500'), { response: { status: 500 } })
    );
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      atuais: [],
      agente: { ...AGENTE, status: 'paused' },
    });
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('AGENTS.JORNADA.ERRO.COMECAR_ATENDER');
    expect(erro.textContent).toContain('COMECAR_ATENDER_GARANTIA');
    // Nada foi ligado: não há o que desfazer.
    expect(store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaAgents/update',
      expect.anything()
    );
    wrapper.unmount();
  });

  it('shows the server explanation when it refuses to start (422, #1366)', async () => {
    canaisApi.connect.mockRejectedValueOnce(
      Object.assign(new Error('422'), {
        response: { status: 422, data: { message: 'Escolha um canal.' } },
      })
    );
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      atuais: [],
      agente: { ...AGENTE, status: 'paused' },
    });
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('Escolha um canal.');
    expect(erro.textContent).toContain('AGENTS.JORNADA.ERRO.CANAL_GARANTIA');
    wrapper.unmount();
  });

  it('asks to connect a channel when the account has none, only for whoever can', async () => {
    const com = montar({ canais: [], atuais: [] });
    expect(no('[data-sem-canal]').textContent).toContain(
      'PAGINA.ONDE.SEM_CANAL'
    );
    expect(no('[data-conectar]').getAttribute('href')).toBe(
      '/app/settings_inbox_new'
    );
    com.unmount();

    permissoes.conectar = false;
    const sem = montar({ canais: [], atuais: [] });
    expect(no('[data-conectar]')).toBeNull();
    expect(no('[data-sem-canal]').textContent).toContain(
      'SEM_CANAL_SEM_PERMISSAO'
    );
    sem.unmount();
  });

  it('keeps "when" and the hand-off note without a channel, saving only the window (t10-semcanal)', async () => {
    const wrapper = montar({ canais: [], atuais: [] });
    expect(no('[data-quem-recebe]')).not.toBeNull();
    radio('AGENTS.JORNADA.ONDE_QUANDO.SEMPRE').click();
    expect(radio('AGENTS.JORNADA.ONDE_QUANDO.FORA')).not.toBeUndefined();
    radio('AGENTS.JORNADA.ONDE_QUANDO.FORA').click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(store.dispatch.mock.calls).toEqual([
      [
        'autonomiaAgents/update',
        { id: 7, config: { response_window: 'outside_business_hours' } },
      ],
    ]);
    wrapper.unmount();
  });

  it('shows who receives the hand-off for a stopped agent too (t10-parado)', () => {
    const wrapper = montar({ atendendo: false });
    expect(no('[data-quem-recebe]')).not.toBeNull();
    wrapper.unmount();
  });

  it('waits for the inboxes instead of saying there is none, then marks the current one', async () => {
    const wrapper = montar({
      modo: 'voltar',
      atendendo: false,
      canais: [],
      atuais: [],
      estadoCanais: 'carregando',
    });
    expect(no('[data-sem-canal]')).toBeNull();
    expect(no('[data-carregando-canais]')).not.toBeNull();

    await wrapper.setProps({
      canais: CANAIS,
      atuais: [CANAIS[0]],
      estadoCanais: 'pronto',
    });
    expect(no('[data-carregando-canais]')).toBeNull();
    expect(radio('WhatsApp do Centro').getAttribute('aria-checked')).toBe(
      'true'
    );
    expect(no('[data-confirmar]').disabled).toBe(false);
    wrapper.unmount();
  });

  it('shows the standard error with "Try again" when the inboxes could not be read', async () => {
    const wrapper = montar({ canais: [], atuais: [], estadoCanais: 'erro' });
    expect(no('[data-sem-canal]')).toBeNull();
    await clicar('[data-erro-canais] button');
    expect(wrapper.emitted('reler')).toHaveLength(1);
    wrapper.unmount();
  });

  it('warns that busy inboxes are hidden when L2 could not be read', async () => {
    const wrapper = montar({ semLeitura: true, canais: CANAIS.slice(0, 2) });
    expect(document.body.textContent).toContain('ONDE_QUANDO.SEM_LEITURA');
    wrapper.unmount();
  });
});
