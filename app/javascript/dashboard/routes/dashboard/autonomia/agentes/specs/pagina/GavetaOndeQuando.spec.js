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
const canaisApi = vi.hoisted(() => ({ connect: vi.fn(), disconnect: vi.fn() }));
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
    alerta.mockReset();
    permissoes.conectar = true;
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('saves only the response window when only "when" changed', async () => {
    const wrapper = montar();
    radio('AGENTS.JORNADA.ONDE_QUANDO.DENTRO').click();
    await nextTick();
    await clicar('[data-confirmar]');

    expect(store.dispatch.mock.calls).toEqual([
      [
        'autonomiaAgents/update',
        { id: 7, config: { response_window: 'business_hours' } },
      ],
    ]);
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.ONDE.PRONTO');
    expect(wrapper.emitted('pronto')).toHaveLength(1);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('moves to a free inbox with the start-answering sequence, then leaves the old one', async () => {
    const wrapper = montar();
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    expect(store.dispatch).toHaveBeenCalledWith('autonomiaAgents/update', {
      id: 7,
      enabled: true,
      status: 'active',
    });
    expect(canaisApi.connect).toHaveBeenCalledWith(7, 2);
    expect(canaisApi.disconnect).toHaveBeenCalledWith(7, 1);
    expect(canaisApi.disconnect).not.toHaveBeenCalledWith(9, expect.anything());
    naoMandouCamposDoPainelAntigo();
    wrapper.unmount();
  });

  it('swaps a busy inbox: takes the other agent out first', async () => {
    const wrapper = montar();
    expect(radio('ONDE_QUANDO.OCUPADO').className).toContain('bg-n-amber-2');
    expect(radio('Instagram').className).not.toContain('bg-n-amber-2');
    radio('ONDE_QUANDO.OCUPADO').click();
    await nextTick();
    expect(no('[data-troca]').textContent).toContain('ONDE_QUANDO.TROCA');
    expect(no('[data-troca]').className).toContain('ring-n-amber-6');
    expect(no('[data-troca] .i-lucide-triangle-alert')).not.toBeNull();
    await clicar('[data-confirmar]');

    expect(canaisApi.disconnect.mock.calls[0]).toEqual([9, 3]);
    expect(canaisApi.connect).toHaveBeenCalledWith(7, 3);
    expect(canaisApi.disconnect).toHaveBeenCalledWith(7, 1);
    wrapper.unmount();
  });

  it('shows the channel error with "Choose another one" when the inbox refuses', async () => {
    canaisApi.connect.mockRejectedValueOnce(
      Object.assign(new Error('422'), { response: { status: 422 } })
    );
    const wrapper = montar();
    radio('Instagram').click();
    await nextTick();
    await clicar('[data-confirmar]');

    const erro = no('[data-erro]');
    expect(erro.textContent).toContain('AGENTS.JORNADA.ERRO.CANAL');
    expect(erro.textContent).toContain('AGENTS.JORNADA.ERRO.CANAL_ACAO');
    expect(canaisApi.disconnect).not.toHaveBeenCalled();
    expect(wrapper.emitted('fechar')).toBeUndefined();

    erro.querySelector('button').click();
    await nextTick();
    expect(no('[data-erro]')).toBeNull();
    expect(radio('WhatsApp do Centro').getAttribute('aria-checked')).toBe(
      'true'
    );
    wrapper.unmount();
  });

  it('says the standard save error when saving the window fails', async () => {
    store.dispatch.mockRejectedValueOnce(new Error('500'));
    const wrapper = montar();
    radio('AGENTS.JORNADA.ONDE_QUANDO.FORA').click();
    await nextTick();
    await clicar('[data-confirmar]');
    expect(no('[data-erro]').textContent).toContain(
      'PAGINA.ONDE.ERRO_GARANTIA'
    );
    wrapper.unmount();
  });

  it('stops answering anywhere after confirming', async () => {
    const wrapper = montar();
    await clicar('[data-nao-atender]');
    await clicar('dialog [data-botoes] [data-confirmar]');
    expect(canaisApi.disconnect).toHaveBeenCalledWith(7, 1);
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(wrapper.emitted('pronto')).toHaveLength(1);
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
    expect(store.dispatch).toHaveBeenLastCalledWith('autonomiaAgents/update', {
      id: 7,
      enabled: true,
      status: 'paused',
    });
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
