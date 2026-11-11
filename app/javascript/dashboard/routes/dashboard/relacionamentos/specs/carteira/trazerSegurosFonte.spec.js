import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import {
  NAO_ENTRA_NA_DEMO,
  esquecerTrazerSeguros,
  trazerSegurosFonte,
} from '../../fonte/trazerSegurosFonte';
import { quantosEntram } from '../../carteira/ajustesDaRenovacao';
import { totalDeSeguros } from '../../carteira/contagemDeSeguros';
import { DESTINOS_DE_SEGURO } from '../../carteira/destinosDeSeguro';
import {
  FUNIS_DA_DEMO,
  esquecerAjustesDaDemo,
} from '../../demo/carteiraAjustes';

// A fonte falsa de "trazer seguros" (#2897, telas 8, 9, 16 e 17): os números da
// especificação, o que cada caso da demonstração devolve e o histórico junto
// com as listas do bloco A. O relógio é do teste.
const AGORA = Date.UTC(2026, 10, 11, 15);
let relogio = AGORA;
const passar = ms => {
  relogio += ms;
};

const fonte = (demo = 'sem-seguros', opcoes = {}) =>
  trazerSegurosFonte({
    demo,
    atraso: 0,
    agora: () => relogio,
    listas: trazerFonte({
      demo,
      carregarDemo: () => import('../../demo/trazer.js'),
      atraso: 0,
      atrasoDaLeitura: 0,
      agora: () => relogio,
    }),
    ...opcoes,
  });
const nome = erro => erro.name;

vi.setConfig({ testTimeout: 30000 });

beforeAll(async () => {
  await import('../../demo/trazerSeguros.js');
}, 60000);

beforeEach(() => {
  relogio = AGORA;
  esquecerMemoriaDaDemo();
  esquecerTrazerSeguros();
  esquecerAjustesDaDemo();
});

describe('o começo: a conta já está ligada ao Agger?', () => {
  it('na conta cheia sim; em sem-seguros ainda não', async () => {
    expect((await fonte('cheio').comeco()).aggerLigado).toBe(true);
    expect((await fonte('sem-seguros').comeco()).aggerLigado).toBe(false);
  });

  it('diz se a conta já escolheu onde ficam as renovações, e os funis dela', async () => {
    expect((await fonte('cheio').comeco()).renovacoes).toEqual({
      escolhido: true,
      funis: FUNIS_DA_DEMO,
      semPermissao: false,
    });
    expect((await fonte('sem-seguros').comeco()).renovacoes.escolhido).toBe(
      false
    );
    expect(
      (await fonte('sem-seguros', { caso: 'sem_permissao_de_funil' }).comeco())
        .renovacoes.semPermissao
    ).toBe(true);
  });

  it('`demo-carteira=erro` falha; sem demonstração, a fonte real está pendente', async () => {
    await expect(fonte('cheio', { peca: 'erro' }).comeco()).rejects.toThrow();
    await expect(
      trazerSegurosFonte({ demo: null }).comeco().catch(nome)
    ).resolves.toBe('FONTE_REAL_PENDENTE');
  });
});

describe('onde ficam as renovações (a primeira vez que a conta traz seguros)', () => {
  it('guarda a escolha, refaz a linha do que entra amanhã cedo e não pergunta de novo', async () => {
    const f = fonte();
    const leitura = await f.lerPlanilha(null);

    const escolhida = await f.escolherRenovacoes(leitura.id, {
      onde: 'usar',
      funil: 'Vendas',
      etapa: 'Novo contato',
      dias: 30,
    });

    expect(escolhida.efeito).toMatchObject({ dias: 30, seguros: 17 });
    expect((await f.comeco()).renovacoes.escolhido).toBe(true);
  });

  it('seguir sem escolher: os seguros entram, mas nenhuma renovação começa ainda', async () => {
    const f = fonte('sem-seguros', { caso: 'sem_permissao_de_funil' });
    const leitura = await f.lerPlanilha(null);

    const seguiu = await f.escolherRenovacoes(leitura.id, null);

    expect(seguiu.efeito.seguros).toBe(0);
    expect(seguiu.prontos).toBe(164);
    expect((await f.comeco()).renovacoes.escolhido).toBe(false);
  });
});

describe('planilha com seguros', () => {
  it('acha 168 seguros de 120 pessoas: 164 prontos e 4 que precisam de você', async () => {
    const leitura = await fonte().lerPlanilha(null);

    expect(leitura.origem).toBe('planilha');
    expect(leitura.arquivo).toBe('Carteira 2026.xlsx');
    expect(leitura.achei).toEqual({ seguros: 168, pessoas: 120 });
    expect(leitura.prontos).toBe(164);
    expect(leitura.jaEstavam).toBe(120);
    expect(leitura.efeito).toMatchObject({ dias: 60, seguros: 22 });
    // A linha do efeito muda com os dias: com 30, entram 17.
    expect(quantosEntram(leitura.efeito.vencimentos, 30)).toBe(17);
    expect(leitura.problemas.map(p => [p.tipo, p.nome, p.estado])).toEqual([
      ['falta_termina', 'Hugo Orsolini', 'aberto'],
      ['seguradora', 'Karina Tavolari', 'aberto'],
      ['duplicado', 'Paula Aguiardo', 'aberto'],
      ['telefone', 'Inês Imbirussu', 'aberto'],
    ]);
    expect(totalDeSeguros(leitura)).toBe(164);
  });

  it('as fichas de exemplo vêm da carteira: uma pessoa com três seguros e uma sem telefone', async () => {
    const { exemplos } = await fonte().lerPlanilha(null);

    expect(exemplos.map(e => [e.nome, e.seguros.length])).toEqual([
      ['Fábio Kalinoski', 3],
      ['Nádia Hortêncio', 1],
      ['Tiago Bragantino', 2],
    ]);
    expect(exemplos[0].telefone).toMatch('+5511');
    expect(exemplos[0].email).toMatch('@exemplo.com.br');
    expect(exemplos[2].telefone).toBe('');
  });

  it('as colunas de seguro têm destino próprio e a leitura das pessoas vem junto', async () => {
    const leitura = await fonte().lerPlanilha(null);
    const destinos = leitura.colunas.map(c => c.destino);

    Object.values(DESTINOS_DE_SEGURO).forEach(destino =>
      expect(destinos).toContain(destino)
    );
    expect(leitura.pessoas.arquivo).toBe('Carteira 2026.xlsx');
    expect(leitura.pessoas.perguntas.length).toBeGreaterThan(0);
  });

  it('resolver soma um seguro; deixar de fora não; voltar atrás reabre', async () => {
    const f = fonte();
    const { id, problemas } = await f.lerPlanilha(null);
    const [primeiro, segundo] = problemas.map(p => p.linha);

    const consertada = await f.consertar(id, primeiro, 1_800_000_000);
    expect(totalDeSeguros(consertada)).toBe(165);
    expect(consertada.problemas[0].corrigido).toBe(1_800_000_000);

    const deixada = await f.deixarDeFora(id, segundo);
    expect(totalDeSeguros(deixada)).toBe(165);

    const reaberta = await f.reabrir(id, primeiro);
    expect(totalDeSeguros(reaberta)).toBe(164);
    expect(reaberta.problemas[0].estado).toBe('aberto');
  });

  it('planilha que não serve dá o mesmo erro do bloco A', async () => {
    const vazia = fonte('sem-seguros', {
      listas: trazerFonte({
        demo: 'sem-seguros',
        planilha: 'vazia',
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      }),
    });
    await expect(vazia.lerPlanilha(null).catch(nome)).resolves.toBe(
      'PLANILHA_VAZIA'
    );
  });
});

describe('trazer, o andamento e o histórico', () => {
  const trazerTudo = async f => {
    const { id, problemas } = await f.lerPlanilha(null);
    await problemas.reduce(
      (antes, p) => antes.then(() => f.consertar(id, p.linha, 'ok')),
      Promise.resolve()
    );
    return f.trazer(id);
  };

  it('o andamento sobe com o relógio e termina com os seguros e as pessoas', async () => {
    const f = fonte();
    const { trazidaId } = await trazerTudo(f);

    passar(3000);
    expect(await f.andamento(trazidaId)).toMatchObject({
      porcentagem: 50,
      situacao: 'trazendo',
    });
    passar(3000);
    expect(await f.andamento(trazidaId)).toEqual({
      porcentagem: 100,
      situacao: 'pronto',
      seguros: 168,
      pessoas: 120,
    });
  });

  it('o que acabou de chegar fica no topo do histórico, antes das listas do bloco A', async () => {
    const f = fonte();
    await trazerTudo(f);
    passar(6000);

    const [nova, ...resto] = await f.historico();
    expect(nova).toMatchObject({
      tipo: 'planilha',
      arquivo: 'Carteira 2026.xlsx',
      seguros: 168,
      situacao: 'pronto',
    });
    expect(resto.map(l => l.arquivo)).toContain('Clientes de setembro.xlsx');
    expect(resto.every(l => l.tipo === undefined)).toBe(true);
  });

  it('desfazer mostra antes o que sai; lista do bloco A segue como era', async () => {
    const f = fonte();
    const { trazidaId } = await trazerTudo(f);
    passar(6000);

    expect(await f.previaDoDesfazer(trazidaId)).toEqual({
      origem: 'planilha',
      seguros: 168,
      pessoas: 120,
      cards: 0,
      propostas: 0,
    });
    expect(await f.previaDoDesfazer('trazida-antiga-1')).toEqual({
      tira: 104,
      ficam: 16,
      devolve: 12,
    });

    await f.desfazer(trazidaId);
    const [desfeita] = await f.historico();
    expect(desfeita.situacao).toBe('desfeito');
  });

  it('na conta cheia o histórico já tem o Agger e a planilha, com os números da carteira', async () => {
    const f = fonte('cheio');
    const [agger, planilha] = await f.historico();

    expect(agger).toMatchObject({
      tipo: 'agger',
      seguros: 156,
      buscaTodoDia: true,
      novos: 2,
    });
    expect(agger.ultimaBusca).toBeLessThanOrEqual(AGORA);
    expect(planilha).toMatchObject({
      tipo: 'planilha',
      arquivo: 'Carteira 2026.xlsx',
      seguros: 12,
    });

    const previa = await f.previaDoDesfazer(agger.id);
    expect(previa.seguros).toBe(156);
    expect(previa.cards).toBeGreaterThan(0);

    const parada = await f.buscarTodoDia(agger.id, false);
    expect(parada.buscaTodoDia).toBe(false);
    expect((await f.historico())[0].buscaTodoDia).toBe(false);
    await f.buscarTodoDia(agger.id, true);
    expect((await f.historico())[0].buscaTodoDia).toBe(true);
  });

  it('caso `trazer_falhou`: falha uma vez e, tentando de novo, traz', async () => {
    const f = fonte('sem-seguros', { caso: 'trazer_falhou' });
    const { id } = await f.lerPlanilha(null);

    await expect(f.trazer(id)).rejects.toThrow();
    await expect(f.trazer(id)).resolves.toHaveProperty('trazidaId');
  });
});

describe('PDFs das apólices', () => {
  it('40 PDFs de exemplo, com um boleto no meio', async () => {
    const pdfs = await fonte().pdfsDeExemplo();
    expect(pdfs).toHaveLength(40);
    expect(pdfs.map(p => p.name)).toContain('boleto-marco.pdf');
  });

  it('lê aos poucos e acha 39 seguros de 31 pessoas: 37 prontos, 2 precisam, 1 não é apólice', async () => {
    const f = fonte();
    const { leituraId } = await f.lerPdfs(await f.pdfsDeExemplo());

    passar(1800);
    expect(await f.andamentoDosPdfs(leituraId)).toEqual({
      lidos: 12,
      total: 40,
      leitura: null,
    });

    passar(4200);
    const { lidos, leitura } = await f.andamentoDosPdfs(leituraId);
    expect(lidos).toBe(40);
    expect(leitura.achei).toEqual({ pdfs: 40, seguros: 39, pessoas: 31 });
    expect(leitura.prontos).toBe(37);
    expect(leitura.naoEApolice).toEqual(['boleto-marco.pdf']);
    expect(leitura.efeito).toMatchObject({ dias: 60, seguros: 6 });
    expect(leitura.problemas.map(p => [p.tipo, p.nome])).toEqual([
      ['falta_termina', 'Marina Tavolari'],
      ['telefone', 'Bruno Zambelli'],
    ]);
    expect(leitura.problemas[1].podeSeguirSem).toBe(true);
    expect(leitura.exemplos).toHaveLength(3);
  });

  it('caso `foto_escura`: a foto que não deu para ler entra nos problemas', async () => {
    const f = fonte('sem-seguros', { caso: 'foto_escura' });
    const { leituraId } = await f.lerPdfs(await f.pdfsDeExemplo());
    passar(6000);

    const { leitura } = await f.andamentoDosPdfs(leituraId);
    expect(leitura.problemas[1]).toMatchObject({
      tipo: 'foto_escura',
      arquivo: 'apolice-ana.jpg',
    });
  });

  it('caso `pdfs_nao_leu`: a leitura falha uma vez', async () => {
    const f = fonte('sem-seguros', { caso: 'pdfs_nao_leu' });
    const { leituraId } = await f.lerPdfs(await f.pdfsDeExemplo());

    await expect(f.andamentoDosPdfs(leituraId).catch(nome)).resolves.toBe(
      'NAO_LEU'
    );
    await expect(f.andamentoDosPdfs(leituraId)).resolves.toHaveProperty(
      'lidos'
    );
  });
});

describe('Agger', () => {
  const login = { usuario: 'corretora.demo', senha: 'senha-de-demo' };

  it('senha que não confere não entra e a conta continua sem ligar', async () => {
    const f = fonte();
    await expect(
      f.entrarNoAgger({ ...login, senha: NAO_ENTRA_NA_DEMO }).catch(nome)
    ).resolves.toBe('LOGIN_NAO_CONFERE');
    expect((await f.comeco()).aggerLigado).toBe(false);
  });

  it('entra, busca seguradora por seguradora e acha os 156 seguros que a carteira tem do Agger', async () => {
    const f = fonte();
    const { buscaId } = await f.entrarNoAgger(login);
    expect((await f.comeco()).aggerLigado).toBe(true);

    passar(3000);
    const noMeio = await f.andamentoDaBusca(buscaId);
    expect(noMeio.seguradoras).toEqual([
      { nome: 'Seguradora Atlântica', seguros: 64, situacao: 'pronta' },
      { nome: 'Horizonte Seguros', seguros: 52, situacao: 'pronta' },
      { nome: 'Serra Azul Seguros', seguros: 40, situacao: 'buscando' },
      { nome: 'Seguradora Aurora', seguros: 0, situacao: 'falta_senha' },
    ]);
    expect(noMeio.leitura).toBeNull();

    passar(1500);
    const { leitura } = await f.andamentoDaBusca(buscaId);
    expect(leitura.origem).toBe('agger');
    expect(leitura.achei).toEqual({ seguros: 156, pessoas: 116 });
    expect(leitura.prontos).toBe(152);
    expect(leitura.semTelefone).toBe(4);
    expect(leitura.jaEstavam).toBe(116);
    expect(leitura.efeito).toMatchObject({ dias: 60, seguros: 21 });
    expect(totalDeSeguros(leitura)).toBe(156);
  });

  it('"Buscar de novo agora" busca a seguradora sem senha outra vez', async () => {
    const f = fonte();
    const { buscaId } = await f.entrarNoAgger(login);
    passar(4500);

    const denovo = await f.buscarDeNovo(buscaId);
    expect(denovo.seguradoras[3].situacao).toBe('buscando');
    expect(denovo.leitura).toBeNull();
    passar(1500);
    expect((await f.andamentoDaBusca(buscaId)).seguradoras[3].situacao).toBe(
      'falta_senha'
    );
  });

  it('com a conta já ligada, busca sem pedir login', async () => {
    await expect(fonte('cheio').buscarNoAgger()).resolves.toHaveProperty(
      'buscaId'
    );
    await expect(fonte().buscarNoAgger().catch(nome)).resolves.toBe(
      'AGGER_NAO_LIGADO'
    );
  });

  it('casos: o Agger sem a parte de apólices e o Agger que não respondeu', async () => {
    await expect(
      fonte('sem-seguros', { caso: 'agger_sem_apolices' })
        .entrarNoAgger(login)
        .catch(nome)
    ).resolves.toBe('AGGER_SEM_APOLICES');

    const f = fonte('sem-seguros', { caso: 'agger_nao_respondeu' });
    const { buscaId } = await f.entrarNoAgger(login);
    passar(1500);
    await expect(f.andamentoDaBusca(buscaId).catch(nome)).resolves.toBe(
      'AGGER_NAO_RESPONDEU'
    );
    await expect(f.andamentoDaBusca(buscaId)).resolves.toHaveProperty(
      'seguradoras'
    );
  });
});
