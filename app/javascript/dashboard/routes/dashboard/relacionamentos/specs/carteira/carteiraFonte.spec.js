import { carteiraFonte } from '../../fonte/carteiraFonte';
import { gruposDeSeguros } from '../../fonte/gruposDeSeguros';
import {
  SELOS,
  diasParaTerminar,
  seloDoSeguro,
} from '../../fonte/selosDoSeguro';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';

// A fonte falsa da carteira (#2897): cada número das tabelas da especificação
// (BLOCO-B, "Dados da demonstração") e o que cada estado da demonstração devolve.
const fonte = (demo = 'cheio', peca = null) =>
  carteiraFonte({ demo, peca, atraso: 0 });
const todos = async () => (await fonte().listarTodos({})).itens;
const contar = (lista, selo) =>
  lista.filter(seguro => seloDoSeguro(seguro) === selo).length;
const porCampo = (lista, campo) =>
  lista.reduce(
    (conta, item) => ({
      ...conta,
      [item[campo]]: (conta[item[campo]] ?? 0) + 1,
    }),
    {}
  );

vi.setConfig({ testTimeout: 30000 });

beforeAll(async () => {
  await import('../../demo/carteira.js');
}, 60000);

afterEach(() => esquecerEscritasDaCarteira());

describe('a carteira cheia', () => {
  it('tem 168 seguros de 120 pessoas: 84 com um, 24 com dois, 12 com três', async () => {
    const lista = await todos();
    const porPessoa = Object.values(porCampo(lista, 'pessoaId'));
    expect(lista).toHaveLength(168);
    expect(porPessoa).toHaveLength(120);
    expect(porPessoa.filter(n => n === 1)).toHaveLength(84);
    expect(porPessoa.filter(n => n === 2)).toHaveLength(24);
    expect(porPessoa.filter(n => n === 3)).toHaveLength(12);
  });

  it('todo dono de seguro é cliente da base do bloco A', async () => {
    const lista = await todos();
    expect(lista.every(s => s.pessoa.contact_type === 'customer')).toBe(true);
  });

  it('os selos batem: 98 ativos, 22 em renovação, 4 renovados, 41 vencidos, 3 cancelados', async () => {
    const lista = await todos();
    expect(contar(lista, SELOS.ATIVO)).toBe(98);
    expect(contar(lista, SELOS.EM_RENOVACAO)).toBe(22);
    expect(contar(lista, SELOS.RENOVADO)).toBe(4);
    expect(contar(lista, SELOS.VENCIDO)).toBe(41);
    expect(contar(lista, SELOS.CANCELADO)).toBe(3);
  });

  it('os grupos batem com a tabela', async () => {
    expect(await fonte().contagens()).toEqual({
      todos: 168,
      vence_7_dias: 5,
      vence_30_dias: 17,
      vence_90_dias: 31,
      em_renovacao: 22,
      vencido: 41,
      sem_telefone: 4,
      parcela_atrasada: 3,
    });
  });

  it('tipos e seguradoras batem com a tabela', async () => {
    const lista = await todos();
    expect(porCampo(lista, 'tipo')).toEqual({
      auto: 75,
      residencial: 46,
      vida: 29,
      empresarial: 18,
    });
    expect(porCampo(lista, 'seguradora')).toEqual({
      'Seguradora Atlântica': 64,
      'Horizonte Seguros': 52,
      'Serra Azul Seguros': 40,
      'Seguradora Aurora': 12,
    });
  });

  it('a Seguradora Aurora veio da planilha (sem PDF); as outras, do Agger', async () => {
    const lista = await todos();
    lista.forEach(seguro => {
      const daAurora = seguro.seguradora === 'Seguradora Aurora';
      expect(seguro.origem.tipo).toBe(daAurora ? 'planilha' : 'agger');
      expect(seguro.temPdf).toBe(!daAurora);
    });
  });

  it('sem telefone são 4 seguros de 3 pessoas, uma delas com dois', async () => {
    const { itens } = await fonte().listarTodos({ grupo: 'sem_telefone' });
    const porPessoa = Object.values(porCampo(itens, 'pessoaId')).sort();
    expect(porPessoa).toEqual([1, 1, 2]);
  });

  it('o resumo do herói: 5 vencem em 7 dias, todos em renovação', async () => {
    expect(await fonte().resumo()).toEqual({
      total: 168,
      vence7: 5,
      vence7EmRenovacao: 5,
      emRenovacao: 22,
      aggerLigado: true,
    });
  });
});

describe('os seguros com nome', () => {
  const NOMEADOS = [
    [1, 23, 'auto', 'AT-000451', 2760, SELOS.EM_RENOVACAO, 18],
    [2, 23, 'residencial', 'HZ-002318', 640, SELOS.ATIVO, 214],
    [3, 23, 'vida', 'SA-118802', 1150, SELOS.ATIVO, 331],
    [107, 4, 'auto', 'HZ-004410', 1980, SELOS.EM_RENOVACAO, 3],
    [110, 117, 'auto', 'SA-120077', 1890, SELOS.EM_RENOVACAO, 2],
    [111, 29, 'residencial', 'AT-000903', 520, SELOS.EM_RENOVACAO, 5],
    [112, 24, 'auto', 'AT-001288', 3410, SELOS.EM_RENOVACAO, 6],
    [113, 105, 'auto', 'HZ-005160', 2150, SELOS.EM_RENOVACAO, 7],
    [104, 59, 'residencial', 'SA-119340', 700, SELOS.EM_RENOVACAO, 25],
    [105, 203, 'auto', 'AT-001502', 2300, SELOS.EM_RENOVACAO, 40],
    [103, 41, 'auto', 'HZ-003975', 1760, SELOS.VENCIDO, -12],
    [106, null, 'empresarial', 'AT-002044', 6900, SELOS.ATIVO, 150],
  ];

  it.each(NOMEADOS)(
    'o seguro %i é como a especificação diz',
    async (id, pessoaId, tipo, numero, valor, selo, dias) => {
      const seguro = await fonte().seguro(id);
      if (pessoaId) expect(seguro.pessoaId).toBe(pessoaId);
      expect(seguro).toMatchObject({ tipo, numero, valor });
      expect(seloDoSeguro(seguro)).toBe(selo);
      expect(diasParaTerminar(seguro)).toBe(dias);
    }
  );

  it('o seguro 1 tem a placa, o card em "Opções enviadas" e a proposta 8% mais cara', async () => {
    const seguro = await fonte().seguro(1);
    expect(seguro.bem).toBe('Carro hatch prata, placa FIC-0A23');
    expect(seguro.renovacao).toMatchObject({
      funil: 'Renovação',
      etapa: 'Opções enviadas',
      cuida: 'Bia Lunardelli',
      proposta: { valor: 2980.8, variacao: 8 },
    });
  });

  it('renovado (102), cancelado (101), parcela atrasada (108) e sem telefone (104)', async () => {
    const [renovado, cancelado, parcela, semTelefone] = await Promise.all(
      [102, 101, 108, 104].map(id => fonte().seguro(id))
    );
    expect(seloDoSeguro(renovado)).toBe(SELOS.RENOVADO);
    expect(renovado.temPdf).toBe(false);
    expect(seloDoSeguro(cancelado)).toBe(SELOS.CANCELADO);
    expect(parcela.parcelaAbertaEm).toBeTruthy();
    expect(semTelefone.pessoa.phone_number).toBeNull();
  });

  it('o 106 tem a empresa 23 como segurado e aparece na ficha dela', async () => {
    const seguro = await fonte().seguro(106);
    expect(seguro.segurado).toMatchObject({ tipo: 'empresa', id: 23 });
    const daEmpresa = await fonte().daEmpresa(23);
    expect(daEmpresa.map(s => s.id)).toEqual([106]);
  });

  it('a pessoa 23 tem três seguros; a 20 (não é cliente) só o de outra corretora', async () => {
    expect((await fonte().daPessoa(23)).map(s => s.id)).toEqual([1, 2, 3]);
    const deFora = await fonte().daPessoa(20);
    expect(deFora).toHaveLength(1);
    expect(seloDoSeguro(deFora[0])).toBe(SELOS.EM_OUTRA_CORRETORA);
    expect(diasParaTerminar(deFora[0])).toBe(101);
  });

  it('o seguro de outra corretora não conta nos 168', async () => {
    expect((await todos()).some(seguro => seguro.deFora)).toBe(false);
  });

  it('a pessoa 27 não tem seguro nenhum', async () => {
    expect(await fonte().daPessoa(27)).toEqual([]);
  });
});

describe('listar', () => {
  it('pagina de 25 em 25 e diz se tem mais', async () => {
    const pagina = await fonte().listar({});
    expect(pagina.itens).toHaveLength(25);
    expect(pagina.total).toBe(168);
    expect(pagina.temMais).toBe(true);
  });

  it('"Vence primeiro" começa por quem termina antes', async () => {
    const { itens } = await fonte().listar({ grupo: 'vence_7_dias' });
    expect(itens.map(s => s.id)).toEqual([110, 107, 111, 112, 113]);
  });

  it('acha pela placa, pelo número da apólice, pelo nome e pelo documento', async () => {
    const achar = async busca =>
      (await fonte().listarTodos({ busca })).itens.map(s => s.id);
    expect(await achar('FIC-0A23')).toEqual([1]);
    expect(await achar('at-000451')).toEqual([1]);
    expect(await achar('000451')).toEqual([1]);
    const doFabio = (await fonte().seguro(1)).pessoa.name;
    expect((await achar(doFabio)).sort()).toEqual([1, 2, 3]);
  });

  it('as contagens seguem a busca', async () => {
    const contagens = await fonte().contagens({ busca: 'FIC-0A23' });
    expect(contagens.todos).toBe(1);
    expect(contagens.vencido).toBe(0);
  });

  it('filtra por tipo, seguradora e quem cuida', async () => {
    const { itens } = await fonte().listarTodos({
      filtros: { tipo: 'auto', seguradora: 'Seguradora Aurora' },
    });
    expect(itens.length).toBeGreaterThan(0);
    expect(
      itens.every(
        s => s.tipo === 'auto' && s.seguradora === 'Seguradora Aurora'
      )
    ).toBe(true);
    const daBia = await fonte().listarTodos({
      filtros: { cuida: 'Bia Lunardelli' },
    });
    expect(daBia.itens.some(s => s.id === 1)).toBe(true);
    expect(
      daBia.itens.every(s => s.renovacao?.cuida === 'Bia Lunardelli')
    ).toBe(true);
  });
});

describe('os estados da demonstração', () => {
  it.each(['sem-seguros', 'vazio', 'fora-do-segmento'])(
    'em %s não há seguro nenhum',
    async estado => {
      expect((await fonte(estado).resumo()).total).toBe(0);
      expect((await fonte(estado).listar({})).itens).toEqual([]);
      expect(await fonte(estado).daPessoa(23)).toEqual([]);
    }
  );

  it('sem Agger não há o grupo "Parcela atrasada"', async () => {
    expect((await fonte('sem-seguros').resumo()).aggerLigado).toBe(false);
    expect(
      gruposDeSeguros({ aggerLigado: false }).map(g => g.id)
    ).not.toContain('parcela_atrasada');
    expect(gruposDeSeguros().map(g => g.id)).toContain('parcela_atrasada');
  });

  it('`demo-carteira=erro` falha; `vazio` não devolve nada', async () => {
    await expect(fonte('cheio', 'erro').daPessoa(23)).rejects.toThrow();
    expect(await fonte('cheio', 'vazio').daPessoa(23)).toEqual([]);
  });

  it('em carregando a fonte nunca responde', async () => {
    const corrida = await Promise.race([
      fonte('carregando').resumo(),
      fonte('cheio', 'carregando').daPessoa(23),
      new Promise(resolve => {
        setTimeout(() => resolve('nada chegou'), 30);
      }),
    ]);
    expect(corrida).toBe('nada chegou');
  });

  it('sem demonstração, a fonte real ainda não existe', async () => {
    const real = carteiraFonte({});
    expect(real.usaDemo).toBe(false);
    await expect(real.resumo()).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
  });
});

describe('o que a lista de pessoas usa', () => {
  it('diz, por pessoa, quantos seguros tem e qual pede atenção', async () => {
    const porPessoa = await fonte().resumoPorPessoa();
    expect(porPessoa[23]).toMatchObject({
      quantos: 3,
      selo: SELOS.EM_RENOVACAO,
      tipo: 'auto',
      dias: 18,
    });
    expect(porPessoa[41].selo).toBe(SELOS.VENCIDO);
    expect(porPessoa[13].selo).toBe('parcela_atrasada');
    expect(porPessoa[38].selo).toBe(SELOS.RENOVADO);
    expect(Object.values(porPessoa).filter(p => p.quantos === 1)).toHaveLength(
      84
    );
  });

  it('diz o que buscar por pessoa: placas e números de apólice', async () => {
    const porPessoa = await fonte().resumoPorPessoa();
    expect(porPessoa[23].busca).toEqual(
      expect.arrayContaining(['FIC-0A23', 'AT-000451', 'HZ-002318'])
    );
  });

  it('diz o selo da empresa pelos seguros em nome dela', async () => {
    const porEmpresa = await fonte().resumoPorEmpresa();
    expect(porEmpresa[23]).toMatchObject({ quantos: 1, selo: null });
  });
});

describe('escritas (ficam só na memória)', () => {
  it('marcar como cancelado muda o selo e fecha o card; voltar a ativo desfaz', async () => {
    const cancelado = await fonte().cancelar(1);
    expect(seloDoSeguro(cancelado)).toBe(SELOS.CANCELADO);
    expect(cancelado.renovacao).toBeNull();
    const deVolta = await fonte().voltarAAtivo(1);
    expect(seloDoSeguro(deVolta)).toBe(SELOS.EM_RENOVACAO);
    expect(deVolta.renovacao.etapa).toBe('Opções enviadas');
  });

  it('corrigir guarda o que mudou e marca como corrigido à mão', async () => {
    const corrigido = await fonte().corrigir(2, { valor: 700 });
    expect(corrigido.valor).toBe(700);
    expect(corrigido.corrigidoAMao).toEqual(['valor']);
    expect((await fonte().seguro(2)).valor).toBe(700);
  });

  it('o PDF de um seguro sem correção confere; com correção, mostra a diferença', async () => {
    expect((await fonte().lerPdf(2, { name: 'apolice.pdf' })).mudancas).toEqual(
      []
    );
    await fonte().corrigir(2, { valor: 700 });
    const { mudancas } = await fonte().lerPdf(2, { name: 'apolice.pdf' });
    expect(mudancas).toEqual([
      { campo: 'valor', antes: 700, noPdf: 640, corrigidoAMao: true },
    ]);
  });

  it('arquivo que não é PDF é recusado; PDF ilegível falha', async () => {
    await expect(fonte().lerPdf(2, { name: 'foto.png' })).rejects.toMatchObject(
      { name: 'NAO_E_APOLICE' }
    );
    await expect(
      fonte().lerPdf(2, { name: 'ilegivel.pdf' })
    ).rejects.toMatchObject({ name: 'NAO_LEU' });
  });

  it('a apólice nova do renovado entra como ativo; desfazer volta ao renovado', async () => {
    const { mudancas } = await fonte().lerPdf(102, { name: 'nova.pdf' });
    expect(mudancas.map(m => m.campo)).toEqual([
      'numero',
      'comeca',
      'termina',
      'valor',
    ]);
    const novo = await fonte().guardarPdf(102, {
      usar: ['numero', 'comeca', 'termina', 'valor'],
    });
    expect(seloDoSeguro(novo)).toBe(SELOS.ATIVO);
    expect(novo.temPdf).toBe(true);
    const antes = await fonte().desfazerPdf(102);
    expect(seloDoSeguro(antes)).toBe(SELOS.RENOVADO);
  });

  it('a história conta o que foi feito, do mais novo para o mais velho', async () => {
    await fonte().cancelar(2);
    const historia = await fonte().historia(2);
    expect(historia[0].tipo).toBe('cancelado');
    const quando = historia.map(item => item.quando);
    expect(quando).toEqual([...quando].sort((a, b) => b - a));
  });

  it('a história do seguro 1 tem os seis passos da especificação', async () => {
    const historia = await fonte().historia(1);
    expect(historia.map(item => item.tipo)).toEqual([
      'cliente_respondeu',
      'proposta_enviada',
      'proposta_pronta',
      'respondeu_algo_mudou',
      'card_nasceu',
      'chegou_agger',
    ]);
  });
});

describe('seguro de outra corretora (Tela 20)', () => {
  const comCaso = caso =>
    carteiraFonte({
      demo: 'cheio',
      caso,
      atraso: 0,
      carregarDemo: () => import('../../demo/carteira.js'),
    });
  const PESSOA = 27;

  it('diz de quem é a conversa e os arquivos que vieram nela', async () => {
    const conversa = await fonte().arquivosDaConversa(PESSOA);

    expect(conversa.pessoa.id).toBe(PESSOA);
    expect(conversa.arquivos.map(arquivo => arquivo.nome)).toEqual([
      'apolice-auto.pdf',
      'foto-da-apolice.jpg',
      'foto-do-carro.jpg',
      'apolice-sem-data.pdf',
    ]);
  });

  it('lê o arquivo; foto escura e o que não é seguro dizem por quê; sem data, a data vem vazia', async () => {
    const f = fonte();
    const nome = erro => erro.name;

    const lido = await f.lerDeFora({ nome: 'apolice-auto.pdf' });
    expect(lido.tipo).toBe('auto');
    expect(lido.seguradora).toBe('Seguradora Aurora');
    expect(lido.termina).toBeGreaterThan(Date.now() / 1000);
    expect(
      (await f.lerDeFora({ nome: 'apolice-sem-data.pdf' })).termina
    ).toBeNull();
    await expect(
      f.lerDeFora({ nome: 'foto-da-apolice.jpg' }).catch(nome)
    ).resolves.toBe('FOTO_ESCURA');
    await expect(
      f.lerDeFora({ nome: 'foto-do-carro.jpg' }).catch(nome)
    ).resolves.toBe('NAO_PARECE_SEGURO');
  });

  it('guardar põe o seguro na ficha, fora da carteira e sem virar cliente; desfazer tira', async () => {
    const f = fonte();
    const termina = Math.floor(Date.UTC(2027, 1, 20, 12) / 1000);
    const antes = (await f.resumo()).total;

    const guardado = await f.guardarDeFora(PESSOA, {
      tipo: 'auto',
      seguradora: 'Seguradora Aurora',
      termina,
    });

    expect(guardado.deFora).toBe(true);
    expect(guardado.termina).toBe(termina);
    // O lembrete é 60 dias antes de terminar.
    expect(guardado.lembreteEm).toBe(termina - 60 * 24 * 60 * 60);
    expect((await f.daPessoa(PESSOA)).map(s => s.id)).toEqual([guardado.id]);
    expect((await f.resumo()).total).toBe(antes);
    expect((await f.resumoPorPessoa())[PESSOA]).toBeUndefined();

    await f.desfazerDeFora(guardado.id);
    expect(await f.daPessoa(PESSOA)).toEqual([]);
  });

  it('os casos da demonstração: sem arquivos, erro e carregando', async () => {
    expect(
      (await comCaso('de_fora_sem_arquivos').arquivosDaConversa(PESSOA))
        .arquivos
    ).toEqual([]);
    await expect(
      comCaso('de_fora_erro').arquivosDaConversa(PESSOA)
    ).rejects.toThrow();

    const nuncaResponde =
      comCaso('de_fora_carregando').arquivosDaConversa(PESSOA);
    const corrida = await Promise.race([
      nuncaResponde,
      new Promise(resolve => {
        setTimeout(() => resolve('ainda esperando'), 50);
      }),
    ]);
    expect(corrida).toBe('ainda esperando');
  });

  it('sem demonstração, a fonte real está pendente', async () => {
    await expect(
      carteiraFonte()
        .arquivosDaConversa(PESSOA)
        .catch(erro => erro.name)
    ).resolves.toBe('FONTE_REAL_PENDENTE');
  });
});
