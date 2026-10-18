import { mount, flushPromises } from '@vue/test-utils';
import GavetaOndeQuando from '../../components/pagina/GavetaOndeQuandoFase2.vue';
import { recebeEmOutrasCaixas } from '../../utils/ondeTrabalha';

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

// #1433 (decisão do Rodrigo de 15/10, "a, para todos os agentes") — na gaveta "Onde e quando", logo abaixo
// de "Onde atende": "Também recebe quando alguém passar em:", as outras caixas em que o agente fica como
// agente da equipe. Selecionáveis: principal atendendo e só de pessoas; bloqueadas com o motivo: outro robô
// e principal parado.
// #1720 — "{nome} atende primeiro as conversas novas?" (Sim, no canal / Não, só quando alguém passar a
// conversa) e "Recebe quando alguém passar em:". Um "Salvar" só: PUT onde_atende com tudo junto. "Não" sem
// nenhuma caixa marcada pede a confirmação em linha antes de gravar.

const no = seletor => document.querySelector(seletor);
const opcao = valor => no(`[data-tambem-recebe] [data-opcao="${valor}"]`);
const clicar = async elemento => {
  elemento.click();
  await flushPromises();
};

const AGENTE = {
  id: 7,
  name: 'Bia',
  status: 'active',
  enabled: true,
  actuation: 'external',
  config: { response_window: 'always' },
};
const principal = (id, nome, operating = true) => ({
  kind: 'agent',
  agent_id: id,
  agent_name: nome,
  operating,
});
// 1: a caixa principal dela; 3: Duda atende (e Bia já está na equipe); 5: só de pessoas; 4: outro robô;
// 6: Leo parado; 2: livre na leitura antiga (sem so_de_pessoas).
const CANAIS = [
  { inbox_id: 1, name: 'WhatsApp do Centro', occupied_by: principal(7, 'Bia') },
  { inbox_id: 2, name: 'Instagram', occupied_by: null },
  {
    inbox_id: 3,
    name: 'WhatsApp dos Jardins',
    occupied_by: principal(9, 'Duda'),
    areas: [{ agent_id: 7, agent_name: 'Bia', operating: true }],
  },
  {
    inbox_id: 4,
    name: 'WhatsApp Parceiro',
    occupied_by: { kind: 'external' },
    so_de_pessoas: false,
  },
  {
    inbox_id: 5,
    name: 'WhatsApp Recepção',
    occupied_by: null,
    so_de_pessoas: true,
  },
  { inbox_id: 6, name: 'Site', occupied_by: principal(8, 'Leo', false) },
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
      horarios: { 1: null },
      recebeEmOutras: true,
      equipeAtual: [3],
      ...props,
    },
  });

describe('GavetaOndeQuandoFase2 · Recebe quando alguém passar', () => {
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
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('comes right below "Onde atende", without the main inbox, and blocked inboxes say why', () => {
    montar();
    const secoes = [...document.querySelectorAll('section h3')].map(h =>
      h.textContent.trim()
    );
    expect(secoes.slice(0, 3)).toEqual([
      'AGENTS.JORNADA.ONDE_QUANDO.PRIMEIRO_PERGUNTA',
      'AGENTS.JORNADA.ONDE_QUANDO.TAMBEM',
      'AGENTS.JORNADA.ONDE_QUANDO.QUANDO',
    ]);
    expect(opcao(1)).toBeNull();
    expect(opcao(3).getAttribute('aria-checked')).toBe('true');
    expect(opcao(3).textContent).toContain('AGENTS.JORNADA.EQUIPE.PRINCIPAL');
    expect(opcao(5).getAttribute('aria-disabled')).toBeNull();
    expect(opcao(5).textContent).toContain('AGENTS.JORNADA.EQUIPE.SO_PESSOAS');
    expect(opcao(4).getAttribute('aria-disabled')).toBe('true');
    expect(opcao(4).textContent).toContain('AGENTS.JORNADA.EQUIPE.OUTRO_ROBO');
    expect(opcao(6).getAttribute('aria-disabled')).toBe('true');
    expect(opcao(6).textContent).toContain(
      'AGENTS.JORNADA.EQUIPE.PRINCIPAL_PARADO'
    );
    expect(opcao(2).getAttribute('aria-disabled')).toBe('true');
    expect(no('select')).toBeNull();
    // Mesmo cartão compacto de "Onde atende" (decisão do Rodrigo de 15/10).
    const radio = no('[role="radio"]');
    ['px-4', 'py-3', 'rounded-xl', 'min-h-11'].forEach(classe => {
      expect(radio.className).toContain(classe);
      expect(opcao(5).className).toContain(classe);
    });
    expect(opcao(5).querySelector('.size-12')).toBeNull();
  });

  const radio = texto =>
    [...document.querySelectorAll('[role="radio"]')].find(item =>
      item.textContent.includes(texto)
    );
  const pedido = () => canaisApi.ondeAtende.mock.calls[0];

  it('(b) "Sim": answers first in the inbox and saves the checked inboxes in one request', async () => {
    const wrapper = montar();
    expect(radio('PRIMEIRO_SIM').getAttribute('aria-checked')).toBe('true');
    expect(no('[data-canais-primeiro]')).not.toBeNull();
    await clicar(opcao(5));
    await clicar(opcao(3));
    await clicar(opcao(4)); // bloqueada: não marca
    await clicar(no('[data-confirmar]'));

    expect(pedido()).toEqual([
      7,
      {
        primeiroInboxId: 1,
        manterPrimeiro: true,
        areaInboxIds: [5],
        responseWindow: 'always',
        parar: false,
      },
    ]);
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(canaisApi.disconnect).not.toHaveBeenCalled();
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.ONDE.PRONTO');
    expect(wrapper.emitted('fechar')).toBeTruthy();
  });

  it('(a) "Não": hides the inbox list, explains the hours and saves only the checked inboxes', async () => {
    montar();
    await clicar(radio('PRIMEIRO_NAO'));
    expect(no('[data-canais-primeiro]')).toBeNull();
    expect(no('[data-horario-de-cada]').textContent).toContain(
      'ONDE_QUANDO.HORARIO_DE_CADA'
    );
    await clicar(no('[data-confirmar]'));

    expect(pedido()[1]).toEqual({
      primeiroInboxId: null,
      manterPrimeiro: false,
      areaInboxIds: [3],
      responseWindow: 'always',
      parar: false,
    });
    expect(no('[data-aviso-parado]')).toBeNull();
  });

  it('(c) "Não" with nothing checked: warns in the drawer before saving, "Voltar" keeps it as it was', async () => {
    const wrapper = montar();
    await clicar(radio('PRIMEIRO_NAO'));
    await clicar(opcao(3));
    expect(no('[data-horario-de-cada]')).toBeNull();
    await clicar(no('[data-confirmar]'));

    expect(canaisApi.ondeAtende).not.toHaveBeenCalled();
    const aviso = no('[data-aviso-parado]');
    expect(aviso.textContent).toContain('PAGINA.ONDE.PARADO_AVISO');
    expect(no('dialog')).toBeNull();
    await clicar(no('[data-voltar-aviso]'));
    expect(no('[data-aviso-parado]')).toBeNull();
    expect(wrapper.emitted('fechar')).toBeFalsy();

    await clicar(no('[data-confirmar]'));
    await clicar(no('[data-deixar-parado]'));
    expect(pedido()[1]).toEqual({
      primeiroInboxId: null,
      manterPrimeiro: false,
      areaInboxIds: [],
      responseWindow: 'always',
      parar: true,
    });
    expect(wrapper.emitted('fechar')).toBeTruthy();
  });

  // Regra G (#1788): a equipe numa caixa fora do alcance fica no servidor, então ela não para.
  it('(c) "Não" with only a team inbox out of reach: saves without the stop warning', async () => {
    montar({
      canais: CANAIS.map(canal =>
        canal.inbox_id === 3 ? { ...canal, alcanca: false } : canal
      ),
    });
    await clicar(radio('PRIMEIRO_NAO'));
    await clicar(no('[data-confirmar]'));

    expect(no('[data-aviso-parado]')).toBeNull();
    expect(pedido()[1]).toMatchObject({ areaInboxIds: [], parar: false });
  });

  it('(c) a re-read of the inboxes with the same choice keeps the warning open', async () => {
    const wrapper = montar();
    await clicar(radio('PRIMEIRO_NAO'));
    await clicar(opcao(3));
    await clicar(no('[data-confirmar]'));
    await wrapper.setProps({ canais: CANAIS.map(canal => ({ ...canal })) });
    await flushPromises();
    expect(no('[data-aviso-parado]')).not.toBeNull();
  });

  it('(c) changing the choice closes the warning', async () => {
    montar();
    await clicar(radio('PRIMEIRO_NAO'));
    await clicar(opcao(3));
    await clicar(no('[data-confirmar]'));
    await clicar(opcao(5));
    expect(no('[data-aviso-parado]')).toBeNull();
  });

  it('shows the same warning when the server asks for the confirmation', async () => {
    canaisApi.ondeAtende.mockRejectedValueOnce({
      response: { status: 422, data: { code: 'confirmar_parado', error: 'x' } },
    });
    montar();
    await clicar(no('[data-confirmar]'));
    expect(no('[data-aviso-parado]')).not.toBeNull();
    expect(no('[data-erro]')).toBeNull();
  });

  it('shows the server refusal and keeps the drawer open', async () => {
    canaisApi.ondeAtende.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Outro robô atende em WhatsApp Recepção.' },
      },
    });
    const wrapper = montar();
    await clicar(opcao(5));
    await clicar(no('[data-confirmar]'));

    expect(no('[data-erro]').textContent).toContain(
      'Outro robô atende em WhatsApp Recepção.'
    );
    expect(wrapper.emitted('fechar')).toBeFalsy();
    expect(wrapper.emitted('pronto')).toBeTruthy();
  });

  it('without the section, keeps the old channel choice and leaves the team inboxes alone', async () => {
    montar({ recebeEmOutras: false });
    expect(radio('PRIMEIRO_SIM')).toBeUndefined();
    await clicar(no('[data-confirmar]'));
    expect(pedido()[1]).toMatchObject({
      primeiroInboxId: 1,
      manterPrimeiro: true,
      areaInboxIds: null,
    });
  });

  it('the inbox chosen in "Onde atende" leaves the list', async () => {
    montar();
    await clicar(radio('ONDE_QUANDO.OCUPADO'));
    expect(opcao(3)).toBeNull();
  });

  it('is not there without the mark, for a stopped agent, in "voltar" or without the L2 reading', () => {
    [
      { recebeEmOutras: false },
      { atendendo: false },
      { modo: 'voltar' },
      { semLeitura: true },
    ].forEach(props => {
      const wrapper = montar(props);
      expect(no('[data-tambem-recebe]')).toBeNull();
      wrapper.unmount();
      document.body.innerHTML = '';
    });
  });

  it('only agents that talk to customers get the section (the quote agent too)', () => {
    expect(recebeEmOutrasCaixas(AGENTE)).toBe(true);
    expect(
      recebeEmOutrasCaixas({ ...AGENTE, agent_type: 'insurance_quote' })
    ).toBe(true);
    expect(recebeEmOutrasCaixas({ ...AGENTE, actuation: 'internal' })).toBe(
      false
    );
    expect(recebeEmOutrasCaixas({ ...AGENTE, ajudante: true })).toBe(false);
    expect(recebeEmOutrasCaixas(null)).toBe(false);
  });
});
