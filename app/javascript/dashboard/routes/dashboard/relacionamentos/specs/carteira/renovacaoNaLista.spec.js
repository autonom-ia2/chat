import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRoute, useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import GavetaDeFiltrosDeSeguros from '../../components/carteira/GavetaDeFiltrosDeSeguros.vue';
import ListaDeSeguros from '../../components/carteira/ListaDeSeguros.vue';
import { FUNIL_PAROU, funilParou } from '../../carteira/funilDasRenovacoes';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import {
  assentar,
  carregarDemonstracao,
  daCarteira,
  semRolagem,
  textoDe,
} from './apoio';

// A renovação na aba Seguros (#2898), com o texto de verdade em pt_BR: o grupo
// "Em renovação", o grupo temporário que a tela de resultados pede pelo
// endereço, os atalhos "Resultados" e "Ajustar renovações", o convite para
// escolher o funil e o caminho até o card no CRM. Na demonstração lê a carteira
// fictícia; sem ela, o servidor (o cliente de API é de mentira).
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./apoio')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./apoio')).TeleportFalso,
}));
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    lista: vi.fn(),
    contagens: vi.fn(),
    resumo: vi.fn(),
    opcoesDeFiltro: vi.fn(),
    seguro: vi.fn(),
    historia: vi.fn(),
    renovacoes: vi.fn(),
  },
}));
const permissoes = vi.hoisted(() => ({ ajusta: true }));
vi.mock('../../ficha/usePermissoesDaFicha', () => ({
  usePermissoesDaFicha: () => ({
    podeEditar: { value: true },
    podeExportar: { value: false },
    podeAjustarRenovacoes: {
      get value() {
        return permissoes.ajusta;
      },
    },
  }),
}));
// O sinal de que o funil escolhido parou de servir tem um leitor só
// (carteira/funilDasRenovacoes.js): cada estado é testado trocando o que ele lê.
vi.mock('../../carteira/funilDasRenovacoes', async importOriginal => ({
  ...(await importOriginal()),
  funilParou: vi.fn(() => ''),
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, name: 'relationships_home' });
  const roteador = {
    push: vi.fn(destino => {
      if (destino.query) rota.query = destino.query;
    }),
  };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const rota = useRoute();
const roteador = useRouter();

// Na carteira fictícia (demo/carteira.js): um seguro com a renovação aberta.
const ABERTA_NA_DEMO = 104;

// Um seguro em renovação, como o servidor manda.
const DO_SERVIDOR = {
  id: 7,
  pessoaId: 23,
  pessoa: { id: 23, name: 'Ana Albuquerino', phone_number: null },
  segurado: {
    tipo: 'pessoa',
    id: 23,
    nome: 'Ana Albuquerino',
    documento: null,
  },
  tipo: 'auto',
  ramoOriginal: null,
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  valor: 2760,
  bem: '',
  comeca: '2025-11-29',
  termina: '2026-11-29',
  selo: 'em_renovacao',
  dias: 17,
  origem: { tipo: 'planilha', arquivo: null, em: 1790000000 },
  temPdf: true,
  canceladoEm: null,
  corrigidoAMao: [],
  renovacao: {
    cardId: 88,
    funil: 'Renovação',
    etapa: 'A vencer',
    desfecho: null,
    cuida: 'Bruna Teixeirão',
  },
  renovadoEm: null,
  motivo: null,
  motivoEscrito: '',
  apoliceNova: false,
};
const AJUSTES = { funilId: 3, etapaId: 31, dias: 30, mensagens: 'mandar' };
const servidorResponde = ({ ajustes = AJUSTES, semPermissao = false } = {}) => {
  SegurosAPI.resumo.mockResolvedValue({ data: { total: 1, vence7: 0 } });
  SegurosAPI.contagens.mockResolvedValue({
    data: { todos: 1, em_renovacao: 1 },
  });
  SegurosAPI.lista.mockResolvedValue({
    data: { itens: [DO_SERVIDOR], total: 1, temMais: false },
  });
  SegurosAPI.seguro.mockResolvedValue({ data: DO_SERVIDOR });
  SegurosAPI.historia.mockResolvedValue({ data: [] });
  SegurosAPI.renovacoes.mockResolvedValue({
    data: { ajustes, funis: [], vencimentos: [], semPermissao },
  });
};

let aberta;
const abrir = async ({ demo = 'cheio', query = {}, ...props } = {}) => {
  rota.query = query;
  aberta = mount(ListaDeSeguros, {
    attachTo: document.body,
    props: { demo, comEmpresas: true, ...props },
    global: { stubs: { transition: true } },
  });
  await assentar();
  // O convite lê os ajustes à parte, depois da lista.
  await assentar();
  return aberta;
};
const abrirNoServidor = (query = {}) => abrir({ demo: null, query });

const linhas = w => w.findAll(daCarteira('linha'));
const selosDasLinhas = w =>
  linhas(w).map(linha =>
    linha.get(daCarteira('selo')).attributes('data-selo-da-carteira')
  );
const pilula = (w, grupo) => w.find(`[data-grupo="${grupo}"]`);
const escolhida = (w, grupo) => pilula(w, grupo).attributes('aria-pressed');
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};

beforeAll(carregarDemonstracao, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  semRolagem();
  permissoes.ajusta = true;
  funilParou.mockReset();
  funilParou.mockReturnValue('');
  roteador.push.mockClear();
  Object.values(SegurosAPI).forEach(rotaDoServidor =>
    rotaDoServidor.mockReset()
  );
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerEscritasDaCarteira();
});

describe('o grupo "Em renovação"', () => {
  it('está na barra, depois dos de vencimento, e mostra só quem está em renovação', async () => {
    const w = await abrir();
    const grupos = w
      .findAll('[data-grupo]')
      .map(botao => botao.attributes('data-grupo'));

    expect(grupos).toEqual([
      'todos',
      'vence_7_dias',
      'vence_30_dias',
      'vence_90_dias',
      'em_renovacao',
      'vencido',
      'sem_telefone',
    ]);
    expect(pilula(w, 'em_renovacao').text()).toContain('Em renovação');

    await clicar(w, '[data-grupo="em_renovacao"]');

    expect(escolhida(w, 'em_renovacao')).toBe('true');
    expect(textoDe(w, daCarteira('explicacao-do-grupo'))).toBe(
      'Seguros com a renovação em andamento: já estão no funil e ainda falta dizer se renovaram.'
    );
    expect(linhas(w).length).toBeGreaterThan(0);
    expect(new Set(selosDasLinhas(w))).toEqual(new Set(['em_renovacao']));
    expect(textoDe(linhas(w)[0], daCarteira('selo'))).toBe('Em renovação');
  });
});

// O aviso do sino leva a `?aba=seguros&grupo=em_renovacao`.
describe('o grupo "Em renovação" pedido pelo endereço', () => {
  const DO_AVISO = { aba: 'seguros', grupo: 'em_renovacao' };

  it('a aba Seguros já abre no grupo', async () => {
    const w = await abrir({ query: DO_AVISO });

    expect(escolhida(w, 'em_renovacao')).toBe('true');
    expect(escolhida(w, 'todos')).toBe('false');
    expect(linhas(w).length).toBeGreaterThan(0);
    expect(new Set(selosDasLinhas(w))).toEqual(new Set(['em_renovacao']));
  });

  it('no servidor, a primeira lista já pede o grupo', async () => {
    servidorResponde();

    const w = await abrirNoServidor(DO_AVISO);

    expect(SegurosAPI.lista).toHaveBeenCalledWith({
      grupo: 'em_renovacao',
      ordem: 'vence_primeiro',
      pagina: 1,
    });
    expect(SegurosAPI.lista).not.toHaveBeenCalledWith(
      expect.objectContaining({ grupo: 'todos' })
    );
    expect(escolhida(w, 'em_renovacao')).toBe('true');
  });

  it('com a aba já aberta em outro grupo, o aviso troca para "Em renovação"', async () => {
    const w = await abrir({ query: { aba: 'seguros' } });
    expect(escolhida(w, 'todos')).toBe('true');

    rota.query = DO_AVISO;
    await assentar();

    expect(escolhida(w, 'em_renovacao')).toBe('true');
    expect(new Set(selosDasLinhas(w))).toEqual(new Set(['em_renovacao']));
  });

  it('abrir e fechar um seguro não mexe no grupo que a pessoa escolheu depois', async () => {
    const w = await abrir({ query: DO_AVISO });
    await clicar(w, '[data-grupo="todos"]');

    rota.query = { ...DO_AVISO, apolice: '1' };
    await assentar();
    rota.query = DO_AVISO;
    await assentar();

    expect(escolhida(w, 'todos')).toBe('true');
  });
});

describe('o grupo que a tela de resultados pede pelo endereço', () => {
  it('`?grupo=nao_renovaram_30` soma a pílula no fim e já abre nela', async () => {
    const w = await abrir({ query: { grupo: 'nao_renovaram_30' } });
    const grupos = w
      .findAll('[data-grupo]')
      .map(botao => botao.attributes('data-grupo'));

    expect(grupos.at(-1)).toBe('nao_renovaram_30');
    expect(escolhida(w, 'nao_renovaram_30')).toBe('true');
    expect(pilula(w, 'nao_renovaram_30').text()).toContain(
      'Não renovaram (últimos 30 dias)'
    );
    expect(textoDe(w, daCarteira('explicacao-do-grupo'))).toBe(
      'Seguros que terminaram nos últimos 30 dias e não renovaram.'
    );
    expect(linhas(w).length).toBeGreaterThan(0);
  });

  it('sem o pedido, a pílula temporária não existe', async () => {
    const w = await abrir();

    expect(pilula(w, 'nao_renovaram_30').exists()).toBe(false);
    expect(pilula(w, 'nao_renovaram_90').exists()).toBe(false);
    expect(pilula(w, 'nao_renovaram_365').exists()).toBe(false);
    expect(escolhida(w, 'todos')).toBe('true');
  });

  it('o que não é grupo é ignorado: abre em Todos', async () => {
    const w = await abrir({ query: { grupo: 'qualquer_coisa' } });

    expect(w.find('[data-grupo="qualquer_coisa"]').exists()).toBe(false);
    expect(escolhida(w, 'todos')).toBe('true');
  });

  it('no servidor, a lista pede o grupo temporário', async () => {
    servidorResponde();

    const w = await abrirNoServidor({ grupo: 'nao_renovaram_90' });

    expect(SegurosAPI.lista).toHaveBeenCalledWith({
      grupo: 'nao_renovaram_90',
      ordem: 'vence_primeiro',
      pagina: 1,
    });
    expect(escolhida(w, 'nao_renovaram_90')).toBe('true');
  });
});

// "Quem cuida" filtra pelo dono da renovação. Só existe quando o servidor
// manda de quem escolher: a lista vem vazia na conta sem renovação e para quem
// não enxerga os cards no quadro.
describe('o filtro "Quem cuida" em "Mais filtros"', () => {
  const OPCOES = { tipos: ['auto'], seguradoras: ['Seguradora Atlântica'] };
  const filtros = w => w.findComponent(GavetaDeFiltrosDeSeguros);
  const campos = w =>
    w.findAll('[data-filtro]').map(campo => campo.attributes('data-filtro'));
  const abrirFiltros = async cuida => {
    servidorResponde();
    SegurosAPI.opcoesDeFiltro.mockResolvedValue({
      data: cuida === undefined ? OPCOES : { ...OPCOES, cuida },
    });
    const w = await abrirNoServidor();
    await clicar(w, daCarteira('mais-filtros'));
    return w;
  };

  it('com quem escolher, aparece depois da seguradora, com o nome de cada pessoa', async () => {
    const w = await abrirFiltros([
      { id: 9, nome: 'Bruna Teixeirão' },
      { id: 12, nome: 'Caio Montenegro' },
    ]);

    expect(campos(w)).toEqual(['tipo', 'seguradora', 'cuida']);
    const campo = w.get('[data-filtro="cuida"]');
    expect(campo.get('label').text()).toBe('Quem cuida da renovação');
    expect(campo.findComponent(ChoiceSelect).props('options')).toEqual([
      { value: '', label: 'Qualquer pessoa' },
      { value: 9, label: 'Bruna Teixeirão' },
      { value: 12, label: 'Caio Montenegro' },
    ]);
    expect(w.findAll('select')).toHaveLength(0);
  });

  it.each([
    ['vazia', []],
    ['ausente', undefined],
  ])(
    'com a lista %s, o filtro some: nem rótulo, nem campo desligado',
    async (_, cuida) => {
      const w = await abrirFiltros(cuida);

      expect(campos(w)).toEqual(['tipo', 'seguradora']);
      const gaveta = w.get(daCarteira('filtros'));
      expect(gaveta.text()).not.toContain('Quem cuida');
      expect(gaveta.findAll('[disabled]')).toHaveLength(0);
    }
  );

  it('aplicar manda o id de quem cuida ao servidor e conta um filtro ligado', async () => {
    const w = await abrirFiltros([{ id: 9, nome: 'Bruna Teixeirão' }]);

    filtros(w).vm.$emit('aplicar', { tipo: '', seguradora: '', cuida: 9 });
    await assentar();

    expect(SegurosAPI.lista).toHaveBeenLastCalledWith({
      grupo: 'todos',
      ordem: 'vence_primeiro',
      pagina: 1,
      'filtros[cuida]': 9,
    });
    expect(textoDe(w, daCarteira('mais-filtros'))).toBe('Mais filtros · 1');
  });

  it('na demonstração, filtra pelos seguros de quem cuida', async () => {
    const w = await abrir();
    await clicar(w, daCarteira('mais-filtros'));
    const [, alguem] = w
      .get('[data-filtro="cuida"]')
      .findComponent(ChoiceSelect)
      .props('options');
    const antes = linhas(w).length;

    filtros(w).vm.$emit('aplicar', {
      tipo: '',
      seguradora: '',
      cuida: alguem.value,
    });
    await assentar();

    expect(linhas(w).length).toBeGreaterThan(0);
    expect(linhas(w).length).toBeLessThan(antes);
  });
});

describe('os atalhos da carteira', () => {
  it('"Resultados" e "Ajustar renovações" levam cada um à sua tela', async () => {
    const w = await abrir();

    expect(textoDe(w, daCarteira('resultados'))).toBe('Resultados');
    expect(textoDe(w, daCarteira('ajustar'))).toBe('Ajustar renovações');

    await clicar(w, daCarteira('resultados'));
    await clicar(w, daCarteira('ajustar'));

    expect(roteador.push.mock.calls).toEqual([
      [{ name: 'relacionamentos_resultados' }],
      [{ name: 'relacionamentos_renovacoes' }],
    ]);
  });

  it('quem não pode mudar os ajustes só vê "Resultados", e os ajustes nem são lidos', async () => {
    permissoes.ajusta = false;
    servidorResponde({ ajustes: { ...AJUSTES, funilId: null, etapaId: null } });

    const w = await abrirNoServidor();

    expect(w.find(daCarteira('resultados')).exists()).toBe(true);
    expect(w.find(daCarteira('ajustar')).exists()).toBe(false);
    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
    expect(SegurosAPI.renovacoes).not.toHaveBeenCalled();
  });
});

describe('o convite para escolher o funil', () => {
  it('aparece enquanto a conta não escolheu, e o botão leva aos ajustes', async () => {
    servidorResponde({ ajustes: { ...AJUSTES, funilId: null, etapaId: null } });

    const w = await abrirNoServidor();

    expect(textoDe(w, daCarteira('convite-das-renovacoes'))).toContain(
      'Escolha em que funil as renovações aparecem.'
    );
    expect(textoDe(w, daCarteira('escolher-funil-das-renovacoes'))).toBe(
      'Escolher o funil'
    );

    await clicar(w, daCarteira('escolher-funil-das-renovacoes'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relacionamentos_renovacoes',
    });
  });

  it.each([
    [FUNIL_PAROU.ARQUIVADO, 'O funil das renovações foi arquivado.'],
    [FUNIL_PAROU.APAGADO, 'O funil ou a etapa das renovações não existe mais.'],
  ])(
    'volta quando o funil escolhido parou (%s), e o botão leva aos ajustes',
    async (estado, frase) => {
      funilParou.mockReturnValue(estado);
      servidorResponde();

      const w = await abrirNoServidor();

      expect(textoDe(w, daCarteira('convite-das-renovacoes'))).toContain(frase);
      expect(textoDe(w, daCarteira('escolher-funil-das-renovacoes'))).toBe(
        'Escolher outro funil'
      );

      await clicar(w, daCarteira('escolher-funil-das-renovacoes'));

      expect(roteador.push).toHaveBeenCalledWith({
        name: 'relacionamentos_renovacoes',
      });
    }
  );

  it('o funil parou, mas quem olha não pode ajustar: sem convite', async () => {
    permissoes.ajusta = false;
    funilParou.mockReturnValue(FUNIL_PAROU.ARQUIVADO);
    servidorResponde();

    const w = await abrirNoServidor();

    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
  });

  it('some para a conta que já escolheu', async () => {
    servidorResponde();

    const w = await abrirNoServidor();

    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(1);
    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
  });

  it('não aparece para quem o servidor diz que não pode mudar', async () => {
    servidorResponde({
      ajustes: { ...AJUSTES, funilId: null, etapaId: null },
      semPermissao: true,
    });

    const w = await abrirNoServidor();

    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
  });

  it('se os ajustes não chegam, a lista continua na tela sem o convite', async () => {
    servidorResponde();
    SegurosAPI.renovacoes.mockRejectedValue(new Error('Network Error'));

    const w = await abrirNoServidor();

    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
    expect(linhas(w)).toHaveLength(1);
  });

  it('na demonstração, a conta já escolheu: sem convite', async () => {
    const w = await abrir();

    expect(w.find(daCarteira('convite-das-renovacoes')).exists()).toBe(false);
  });
});

describe('"Abrir no CRM", na gaveta do seguro em renovação', () => {
  it('no servidor, abre o quadro do CRM com o card', async () => {
    servidorResponde();
    const w = await abrirNoServidor({ apolice: '7' });

    expect(selosDasLinhas(w)).toEqual(['em_renovacao']);

    await clicar(w, daCarteira('abrir-no-crm'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      query: { card_id: '88' },
    });
  });

  it('na demonstração, abre só o quadro: o card é de mentira', async () => {
    const w = await abrir({ query: { apolice: String(ABERTA_NA_DEMO) } });

    await clicar(w, daCarteira('abrir-no-crm'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'crm_kanban_index',
      query: undefined,
    });
  });
});
