import { ref } from 'vue';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import { carteiraFonte } from '../../fonte/carteiraFonte';
import {
  ABAS,
  GRUPOS_DE_EMPRESAS,
  GRUPOS_DE_PESSOAS,
  GRUPO_SO_UM_SEGURO,
  gruposDaAba,
} from '../../fonte/grupos';
import { listaFonte } from '../../fonte/listaFonte';
import { estaValendo } from '../../fonte/selosDoSeguro';
import { segurosDaCarteira } from '../../demo/carteira';
import { NAO_ACHEI, SEM_ACESSO } from '../../ficha/falhas';
import { erroHttp } from './apoio';

// A carteira de seguros na lista de pessoas (#2897), fora da tela: o grupo
// "Só tem um seguro", o resumo dos seguros por pessoa nas duas fontes (servidor
// e demonstração) e o que a demonstração da lista faz no lugar do servidor (o
// grupo e a busca pelo número da apólice e pelo bem). O contrato do servidor
// está em spec/requests/api/v1/accounts/relacionamentos_carteira_na_lista_spec.rb.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { resumoPorPessoa: vi.fn() },
}));

// A pessoa das jornadas da demonstração tem três seguros valendo; o que termina
// antes é o Auto, em 18 dias (demo/carteira.js).
const PESSOA_COM_TRES = 23;
const APOLICE_DELA = 'AT-000451';
const BEM_DELA = 'hatch prata';
const NINGUEM = 999999;
// Meio-dia: longe da virada do dia, o "termina em N dias" não muda no teste.
const AGORA = new Date(2026, 10, 12, 12).getTime();

const ids = lista => lista.map(({ id }) => id);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(AGORA);
});
afterEach(() => {
  vi.useRealTimers();
});

describe('os grupos da lista de pessoas', () => {
  it('a conta com a carteira ganha "Só tem um seguro" logo depois de "Clientes"', () => {
    expect(ids(gruposDaAba(ABAS.PESSOAS, { comSeguros: true }))).toEqual([
      'todos',
      'clientes',
      GRUPO_SO_UM_SEGURO,
      'falou_ha_pouco',
      'sumiu_1_a_3_meses',
      'sumiu_mais_de_3_meses',
      'nunca_conversou',
      'nao_quer_mensagens',
    ]);
  });

  it('o nome e a explicação do grupo vêm do catálogo da carteira', () => {
    const grupo = gruposDaAba(ABAS.PESSOAS, { comSeguros: true }).find(
      ({ id }) => id === GRUPO_SO_UM_SEGURO
    );

    expect(grupo).toEqual({
      id: 'so_um_seguro',
      nome: 'RELACIONAMENTOS_CARTEIRA.PESSOAS.SO_UM_SEGURO.NOME',
      explicacao: 'RELACIONAMENTOS_CARTEIRA.PESSOAS.SO_UM_SEGURO.EXPLICACAO',
    });
  });

  it('sem a carteira os grupos são os de sempre, e Empresas não muda', () => {
    expect(gruposDaAba(ABAS.PESSOAS)).toBe(GRUPOS_DE_PESSOAS);
    expect(gruposDaAba(ABAS.PESSOAS, { comSeguros: false })).toBe(
      GRUPOS_DE_PESSOAS
    );
    expect(gruposDaAba(ABAS.EMPRESAS, { comSeguros: true })).toBe(
      GRUPOS_DE_EMPRESAS
    );
  });
});

describe('o resumo por pessoa lido do servidor', () => {
  const real = () => carteiraFonte({ demo: null });
  const DO_SERVIDOR = {
    7: { quantos: 2, selo: 'vencido', tipo: 'auto', dias: -3 },
  };

  it('manda os ids da página e entrega o que o servidor respondeu', async () => {
    SegurosAPI.resumoPorPessoa.mockResolvedValue({ data: DO_SERVIDOR });

    expect(await real().resumoPorPessoa([7, 8])).toEqual(DO_SERVIDOR);
    expect(SegurosAPI.resumoPorPessoa).toHaveBeenCalledWith([7, 8]);
  });

  it.each([
    [404, NAO_ACHEI],
    [401, SEM_ACESSO],
  ])('a recusa %i ganha o nome %s', async (status, nome) => {
    SegurosAPI.resumoPorPessoa.mockRejectedValue(erroHttp(status));

    await expect(real().resumoPorPessoa([7])).rejects.toMatchObject({
      name: nome,
    });
  });
});

describe('o resumo por pessoa na demonstração', () => {
  const demo = estado => carteiraFonte({ demo: estado, atraso: 0 });

  it('diz quantos seguros a pessoa tem e mostra o que mais pede atenção', async () => {
    expect(await demo('cheio').resumoPorPessoa([PESSOA_COM_TRES])).toEqual({
      [PESSOA_COM_TRES]: { quantos: 3, selo: 'ativo', tipo: 'auto', dias: 18 },
    });
  });

  it('tem as mesmas chaves do servidor, e quem não tem seguro não vem', async () => {
    const resumo = await demo('cheio').resumoPorPessoa([
      PESSOA_COM_TRES,
      NINGUEM,
    ]);

    expect(Object.keys(resumo)).toEqual([String(PESSOA_COM_TRES)]);
    expect(Object.keys(resumo[PESSOA_COM_TRES]).sort()).toEqual([
      'dias',
      'quantos',
      'selo',
      'tipo',
    ]);
  });

  it('só responde pelas pessoas pedidas', async () => {
    const [outro] = segurosDaCarteira(AGORA).filter(
      seguro => seguro.pessoaId !== PESSOA_COM_TRES
    );

    const resumo = await demo('cheio').resumoPorPessoa([outro.pessoaId]);

    expect(Object.keys(resumo)).toEqual([String(outro.pessoaId)]);
  });

  it('na conta de seguros que ainda não tem seguro, ninguém vem', async () => {
    expect(
      await demo('sem-seguros').resumoPorPessoa([PESSOA_COM_TRES])
    ).toEqual({});
  });
});

describe('a lista de pessoas da demonstração, na conta com a carteira', () => {
  const comCarteira = (estado = 'cheio') =>
    listaFonte({ demo: estado, comSeguros: true, atraso: 0 });
  const semCarteira = () => listaFonte({ demo: 'cheio', atraso: 0 });
  const todasDoGrupo = async grupo =>
    (await comCarteira().listarTodos({ aba: ABAS.PESSOAS, grupo })).itens;
  const achadas = async (fonte, busca) =>
    ids((await fonte.listarTodos({ aba: ABAS.PESSOAS, busca })).itens);

  // Quem tem exatamente um seguro valendo, contado direto na carteira fictícia.
  const comUmValendo = () => {
    const valendo = segurosDaCarteira(AGORA).filter(seguro =>
      estaValendo(seguro, AGORA)
    );
    const donos = valendo.map(seguro => seguro.pessoaId);
    return donos.filter(
      dono => donos.indexOf(dono) === donos.lastIndexOf(dono)
    );
  };

  it('"Só tem um seguro" traz quem tem exatamente um seguro valendo', async () => {
    const noGrupo = ids(await todasDoGrupo(GRUPO_SO_UM_SEGURO));

    expect(noGrupo.length).toBeGreaterThan(0);
    expect([...noGrupo].sort()).toEqual(comUmValendo().sort());
    expect(noGrupo).not.toContain(PESSOA_COM_TRES);
  });

  it('o número do grupo é o total da lista dele, na ordem das pílulas', async () => {
    const contagens = await comCarteira().contagens(ABAS.PESSOAS);

    expect(Object.keys(contagens)).toEqual(
      ids(gruposDaAba(ABAS.PESSOAS, { comSeguros: true }))
    );
    expect(contagens[GRUPO_SO_UM_SEGURO]).toBe(comUmValendo().length);
  });

  it('a busca acha a pessoa pelo número da apólice e pelo bem segurado', async () => {
    expect(await achadas(comCarteira(), APOLICE_DELA)).toEqual([
      PESSOA_COM_TRES,
    ]);
    expect(await achadas(comCarteira(), BEM_DELA)).toEqual([PESSOA_COM_TRES]);
    expect(await achadas(comCarteira(), '000451')).toContain(PESSOA_COM_TRES);
  });

  it('as contagens acompanham a busca pelos seguros', async () => {
    const contagens = await comCarteira().contagens(ABAS.PESSOAS, {
      busca: APOLICE_DELA,
    });

    expect(contagens).toMatchObject({ todos: 1, [GRUPO_SO_UM_SEGURO]: 0 });
  });

  it('sem a carteira a lista não tem o grupo nem procura nos seguros', async () => {
    const contagens = await semCarteira().contagens(ABAS.PESSOAS);

    expect(Object.keys(contagens)).toEqual(ids(GRUPOS_DE_PESSOAS));
    expect(await achadas(semCarteira(), APOLICE_DELA)).toEqual([]);
  });

  it('a conta que chega depois de a fonte ser criada já vale na leitura seguinte', async () => {
    const naConta = ref(false);
    const fonte = listaFonte({ demo: 'cheio', comSeguros: naConta, atraso: 0 });

    expect(await achadas(fonte, APOLICE_DELA)).toEqual([]);
    naConta.value = true;

    expect(await achadas(fonte, APOLICE_DELA)).toEqual([PESSOA_COM_TRES]);
    expect(Object.keys(await fonte.contagens(ABAS.PESSOAS))).toContain(
      GRUPO_SO_UM_SEGURO
    );
  });

  it('na conta de seguros que ainda não tem seguro, o grupo existe e está vazio', async () => {
    const fonte = comCarteira('sem-seguros');

    expect((await fonte.contagens(ABAS.PESSOAS))[GRUPO_SO_UM_SEGURO]).toBe(0);
    expect(await achadas(fonte, APOLICE_DELA)).toEqual([]);
  });

  it('a aba Empresas não muda com a carteira', async () => {
    const pedido = { aba: ABAS.EMPRESAS };

    expect(await comCarteira().contagens(ABAS.EMPRESAS)).toEqual(
      await semCarteira().contagens(ABAS.EMPRESAS)
    );
    expect(ids((await comCarteira().listarTodos(pedido)).itens)).toEqual(
      ids((await semCarteira().listarTodos(pedido)).itens)
    );
  });
});
