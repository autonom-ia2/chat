import { mount, flushPromises } from '@vue/test-utils';
import GavetaOndeQuando from '../../components/pagina/GavetaOndeQuando.vue';
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
const canaisApi = vi.hoisted(() => ({ connect: vi.fn(), disconnect: vi.fn() }));
vi.mock('dashboard/api/autonomia/channels', () => ({ default: canaisApi }));

// #1433 (decisão do Rodrigo de 15/10, "a, para todos os agentes") — na gaveta "Onde e quando", logo abaixo
// de "Onde atende": "Também recebe quando alguém passar em:", as outras caixas em que o agente fica como
// agente da equipe. Selecionáveis: principal atendendo e só de pessoas; bloqueadas com o motivo: outro robô
// e principal parado. Salvar entra (POST channels papel area) e sai (DELETE) dessas caixas.

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

describe('GavetaOndeQuando · Também recebe quando alguém passar', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    store.dispatch.mockResolvedValue({});
    canaisApi.connect.mockReset();
    canaisApi.connect.mockResolvedValue({});
    canaisApi.disconnect.mockReset();
    canaisApi.disconnect.mockResolvedValue({});
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
      'AGENTS.JORNADA.ONDE_QUANDO.ONDE',
      'AGENTS.JORNADA.ONDE_QUANDO.TAMBEM',
      'AGENTS.JORNADA.ONDE_QUANDO.QUANDO',
    ]);
    expect(opcao(1)).toBeNull();
    expect(opcao(3).getAttribute('aria-checked')).toBe('true');
    expect(opcao(3).textContent).toContain('AGENTS.JORNADA.EQUIPE.PRINCIPAL');
    expect(opcao(5).getAttribute('aria-disabled')).toBeNull();
    expect(opcao(5).textContent).toContain('AGENTS.JORNADA.EQUIPE.SO_PESSOAS');
    // #1648 (opção B): o canal com agente de outro sistema aceita o agente da equipe.
    expect(opcao(4).getAttribute('aria-disabled')).toBeNull();
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

  it('saves entering and leaving: POST with papel area, then DELETE, and closes', async () => {
    const wrapper = montar();
    await clicar(opcao(5));
    await clicar(opcao(3));
    await clicar(opcao(6)); // bloqueada (principal parado): não marca
    await clicar(no('[data-confirmar]'));

    expect(canaisApi.connect).toHaveBeenCalledTimes(1);
    expect(canaisApi.connect).toHaveBeenCalledWith(7, 5, { papel: 'area' });
    expect(canaisApi.disconnect).toHaveBeenCalledTimes(1);
    expect(canaisApi.disconnect).toHaveBeenCalledWith(7, 3);
    expect(canaisApi.connect.mock.invocationCallOrder[0]).toBeLessThan(
      canaisApi.disconnect.mock.invocationCallOrder[0]
    );
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(alerta).toHaveBeenCalledWith('AGENTS.JORNADA.PAGINA.ONDE.PRONTO');
    expect(wrapper.emitted('fechar')).toBeTruthy();
  });

  it('nothing changed in the other inboxes: no channel call', async () => {
    montar();
    await clicar(no('[data-confirmar]'));
    expect(canaisApi.connect).not.toHaveBeenCalled();
    expect(canaisApi.disconnect).not.toHaveBeenCalled();
  });

  it('shows the server refusal and keeps the drawer open', async () => {
    canaisApi.connect.mockRejectedValue({
      response: { data: { error: 'Outro robô atende em WhatsApp Recepção.' } },
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

  it('the inbox chosen in "Onde atende" leaves the list', async () => {
    montar();
    const jardins = [...document.querySelectorAll('[role="radio"]')].find(
      item => item.textContent.includes('ONDE_QUANDO.OCUPADO')
    );
    await clicar(jardins);
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
