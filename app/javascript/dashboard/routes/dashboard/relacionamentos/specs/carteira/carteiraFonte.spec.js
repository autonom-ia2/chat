import {
  ABA_SEGUROS,
  FILTROS_DE_SEGUROS_VAZIOS,
  ORDENS_DE_SEGUROS,
  carteiraFonte,
  contarFiltrosDeSeguros,
} from '../../fonte/carteiraFonte';
import { carteiraFonteReal } from '../../fonte/carteiraFonteReal';
import { GRUPOS_DE_SEGUROS } from '../../fonte/gruposDeSeguros';
import { POR_PAGINA } from '../../fonte/listaFonte';
import {
  SELOS,
  diasParaTerminar,
  estaValendo,
  seloDoSeguro,
} from '../../fonte/selosDoSeguro';
import { RECUSADO } from '../../carteira/recusas';
import { esquecerEscritasDaCarteira } from '../../demo/carteira';
import { NAO_ACHEI } from '../../ficha/falhas';

// A fonte da carteira em demonstração (#2897): responde com a carteira fictícia
// e guarda as escritas só na memória. A fonte real (servidor) está em
// carteiraFonteReal.spec.js.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));

const fonte = (demo = 'cheio', peca = null) =>
  carteiraFonte({ demo, peca, atraso: 0 });

const PESSOA_DAS_JORNADAS = 23;
const SEGURO_COM_PDF = 1;
const SEGURO_SEM_PDF = 2;
const SEGURO_SEM_COMECO = 3;
const SEGURO_QUE_NAO_EXISTE = 999999;

const todasAsPaginas = async pedido => {
  const primeira = await fonte().listar({ ...pedido, pagina: 1 });
  const paginas = Math.ceil(primeira.total / POR_PAGINA);
  const resto = await Promise.all(
    Array.from({ length: Math.max(paginas - 1, 0) }, (_, i) =>
      fonte().listar({ ...pedido, pagina: i + 2 })
    )
  );
  return [primeira, ...resto].flatMap(resposta => resposta.itens);
};
const total = async pedido =>
  (await fonte().listar({ ...pedido, pagina: 1 })).total;
const ids = lista => lista.map(seguro => seguro.id);
// Bem mais que o atraso da demonstração: quem ia responder já teria respondido.
const BEM_DEPOIS_MS = 10000;

afterEach(() => {
  vi.useRealTimers();
  esquecerEscritasDaCarteira();
});

describe('escolha da fonte', () => {
  it('com `?demo=` e o módulo de demonstração, é a demonstração', () => {
    expect(fonte().usaDemo).toBe(true);
  });

  it('a demonstração responde pelos mesmos nomes da fonte real', () => {
    expect(Object.keys(fonte()).sort()).toEqual(
      Object.keys(carteiraFonteReal()).sort()
    );
  });

  it('a aba Seguros tem nome e os filtros nascem vazios', () => {
    expect(ABA_SEGUROS).toBe('seguros');
    expect(FILTROS_DE_SEGUROS_VAZIOS).toEqual({ tipo: '', seguradora: '' });
  });

  it('conta os filtros preenchidos', () => {
    expect(contarFiltrosDeSeguros()).toBe(0);
    expect(contarFiltrosDeSeguros(FILTROS_DE_SEGUROS_VAZIOS)).toBe(0);
    expect(contarFiltrosDeSeguros({ tipo: 'auto', seguradora: '' })).toBe(1);
    expect(
      contarFiltrosDeSeguros({ tipo: 'auto', seguradora: 'Horizonte Seguros' })
    ).toBe(2);
  });
});

describe('resumo e contagens', () => {
  it('o resumo conta todos e quem vence em até 7 dias', async () => {
    const resumo = await fonte().resumo();

    expect(resumo).toEqual({
      total: await total({ grupo: 'todos' }),
      vence7: await total({ grupo: 'vence_7_dias' }),
    });
    expect(resumo.vence7).toBeGreaterThan(0);
  });

  it('as contagens trazem um número por grupo, igual ao total do grupo', async () => {
    const contagens = await fonte().contagens(ABA_SEGUROS);

    expect(Object.keys(contagens)).toEqual(GRUPOS_DE_SEGUROS.map(g => g.id));
    const totais = await Promise.all(
      GRUPOS_DE_SEGUROS.map(({ id }) => total({ grupo: id }))
    );
    expect(Object.values(contagens)).toEqual(totais);
  });

  it('os grupos de vencimento acumulam', async () => {
    const contagens = await fonte().contagens(ABA_SEGUROS);

    expect(contagens.vence_7_dias).toBeLessThanOrEqual(contagens.vence_30_dias);
    expect(contagens.vence_30_dias).toBeLessThanOrEqual(
      contagens.vence_90_dias
    );
    expect(contagens.vence_90_dias).toBeLessThan(contagens.todos);
    expect(contagens.vencido).toBeGreaterThan(0);
  });

  it('as contagens respeitam a busca e os filtros', async () => {
    const contagens = await fonte().contagens(ABA_SEGUROS, {
      busca: 'AT-000451',
      filtros: { tipo: 'auto' },
    });

    expect(contagens.todos).toBe(1);
    expect(contagens.vence_30_dias).toBe(1);
    expect(contagens.vence_7_dias).toBe(0);
    expect(contagens.vencido).toBe(0);
  });
});

describe('grupos', () => {
  it.each(['vence_7_dias', 'vence_30_dias', 'vence_90_dias'])(
    '%s só tem seguro que ainda vale e vence no prazo',
    async grupo => {
      const dias = Number(grupo.split('_')[1]);
      const seguros = await todasAsPaginas({ grupo });

      expect(seguros.length).toBeGreaterThan(0);
      expect(seguros.every(seguro => estaValendo(seguro))).toBe(true);
      expect(seguros.every(seguro => diasParaTerminar(seguro) <= dias)).toBe(
        true
      );
    }
  );

  it('"vencido" só tem seguro vencido, nunca o cancelado', async () => {
    const seguros = await todasAsPaginas({ grupo: 'vencido' });

    expect(seguros.length).toBeGreaterThan(0);
    expect(seguros.every(s => seloDoSeguro(s) === SELOS.VENCIDO)).toBe(true);
  });

  it('"sem telefone" só tem seguro de pessoa sem telefone', async () => {
    const seguros = await todasAsPaginas({ grupo: 'sem_telefone' });

    expect(seguros.every(seguro => !seguro.pessoa.phone_number)).toBe(true);
  });

  it('a carteira tem seguro cancelado, com PDF e no nome de empresa', async () => {
    const seguros = await todasAsPaginas({ grupo: 'todos' });

    expect(seguros.some(s => seloDoSeguro(s) === SELOS.CANCELADO)).toBe(true);
    expect(seguros.some(seguro => seguro.temPdf)).toBe(true);
    expect(seguros.some(seguro => !seguro.temPdf)).toBe(true);
    expect(seguros.some(seguro => seguro.segurado.tipo === 'empresa')).toBe(
      true
    );
  });
});

describe('paginação', () => {
  it('devolve uma página por vez e diz se tem mais', async () => {
    const primeira = await fonte().listar({ grupo: 'todos', pagina: 1 });

    expect(primeira.itens).toHaveLength(POR_PAGINA);
    expect(primeira.total).toBeGreaterThan(POR_PAGINA);
    expect(primeira.temMais).toBe(true);
  });

  it('as páginas somadas dão o total, sem repetir seguro', async () => {
    const seguros = await todasAsPaginas({ grupo: 'todos' });

    expect(seguros).toHaveLength(await total({ grupo: 'todos' }));
    expect(new Set(ids(seguros)).size).toBe(seguros.length);
  });

  it('a última página diz que não tem mais', async () => {
    const quantos = await total({ grupo: 'todos' });
    const ultima = await fonte().listar({
      grupo: 'todos',
      pagina: Math.ceil(quantos / POR_PAGINA),
    });

    expect(ultima.temMais).toBe(false);
  });
});

describe('ordem', () => {
  it('por padrão vem quem ainda vale, do que vence antes ao que vence depois', async () => {
    const seguros = await todasAsPaginas({ grupo: 'todos' });
    const valendo = seguros.filter(seguro => estaValendo(seguro));
    const resto = seguros.filter(seguro => !estaValendo(seguro));

    expect(ids(seguros)).toEqual(ids([...valendo, ...resto]));
    expect(valendo.map(s => s.termina)).toEqual(
      valendo.map(s => s.termina).sort((a, b) => a - b)
    );
    expect(resto.map(s => s.termina)).toEqual(
      resto.map(s => s.termina).sort((a, b) => b - a)
    );
  });

  it('por nome segue o nome do segurado', async () => {
    const nomes = (
      await todasAsPaginas({ grupo: 'todos', ordem: ORDENS_DE_SEGUROS.NOME })
    ).map(seguro => seguro.segurado.nome);

    expect(nomes).toEqual(
      [...nomes].sort((a, b) => a.localeCompare(b, 'pt-BR'))
    );
  });

  it('"mais novos" vem do que começou há menos tempo; sem início, por último', async () => {
    const seguros = await todasAsPaginas({
      grupo: 'todos',
      ordem: ORDENS_DE_SEGUROS.MAIS_NOVOS,
    });
    const comInicio = seguros.filter(seguro => seguro.comeca !== null);

    expect(seguros[seguros.length - 1].id).toBe(SEGURO_SEM_COMECO);
    expect(ids(seguros.slice(0, comInicio.length))).toEqual(ids(comInicio));
    expect(comInicio.map(s => s.comeca)).toEqual(
      comInicio.map(s => s.comeca).sort((a, b) => b - a)
    );
  });
});

describe('busca e filtros', () => {
  it('acha pelo número da apólice, com letras ou só com os números', async () => {
    const comLetras = await todasAsPaginas({ busca: 'at-000451' });
    const soNumeros = await todasAsPaginas({ busca: '000451' });

    expect(ids(comLetras)).toEqual([SEGURO_COM_PDF]);
    expect(ids(soNumeros)).toContain(SEGURO_COM_PDF);
  });

  it('acha pelo nome da pessoa e pelo bem', async () => {
    const { pessoa } = await fonte().seguro(SEGURO_COM_PDF);
    const peloNome = await todasAsPaginas({ busca: pessoa.name });
    const peloBem = await todasAsPaginas({ busca: 'hatch prata' });

    expect(ids(peloNome)).toEqual(
      expect.arrayContaining([
        SEGURO_COM_PDF,
        SEGURO_SEM_PDF,
        SEGURO_SEM_COMECO,
      ])
    );
    expect(ids(peloBem)).toEqual([SEGURO_COM_PDF]);
  });

  it('busca que não acha nada devolve lista vazia', async () => {
    expect(await fonte().listar({ busca: 'zzzz nada disso' })).toEqual({
      itens: [],
      total: 0,
      temMais: false,
    });
  });

  it('filtra por tipo e por seguradora', async () => {
    const vida = await todasAsPaginas({ filtros: { tipo: 'vida' } });
    const horizonte = await todasAsPaginas({
      filtros: { tipo: 'residencial', seguradora: 'Horizonte Seguros' },
    });

    expect(vida.length).toBeGreaterThan(0);
    expect(vida.every(seguro => seguro.tipo === 'vida')).toBe(true);
    expect(ids(horizonte)).toContain(SEGURO_SEM_PDF);
    expect(
      horizonte.every(
        seguro =>
          seguro.tipo === 'residencial' &&
          seguro.seguradora === 'Horizonte Seguros'
      )
    ).toBe(true);
  });

  it('as opções de filtro são os tipos e as seguradoras da carteira, em ordem', async () => {
    const opcoes = await fonte().opcoesDeFiltro();

    expect(opcoes.tipos).toEqual([
      'auto',
      'empresarial',
      'outro',
      'residencial',
      'vida',
    ]);
    expect(opcoes.seguradoras).toEqual([
      'Horizonte Seguros',
      'Seguradora Atlântica',
      'Seguradora Aurora',
      'Serra Azul Seguros',
    ]);
  });
});

describe('os seguros da ficha', () => {
  it('os da pessoa vêm em ordem de urgência', async () => {
    const dela = await fonte().daPessoa(PESSOA_DAS_JORNADAS);

    expect(ids(dela)).toEqual([
      SEGURO_COM_PDF,
      SEGURO_SEM_PDF,
      SEGURO_SEM_COMECO,
    ]);
  });

  it('os da pessoa incluem o seguro em que o segurado é a empresa dela', async () => {
    const todos = await todasAsPaginas({ grupo: 'todos' });
    const daFirma = todos.find(seguro => seguro.segurado.tipo === 'empresa');

    expect(ids(await fonte().daPessoa(daFirma.pessoaId))).toContain(daFirma.id);
  });

  it('os da empresa são só os seguros em que ela é o segurado', async () => {
    const todos = await todasAsPaginas({ grupo: 'todos' });
    const daFirma = todos.find(seguro => seguro.segurado.tipo === 'empresa');

    const dela = await fonte().daEmpresa(daFirma.segurado.id);

    expect(ids(dela)).toContain(daFirma.id);
    expect(
      dela.every(
        seguro =>
          seguro.segurado.tipo === 'empresa' &&
          seguro.segurado.id === daFirma.segurado.id
      )
    ).toBe(true);
  });

  it('quem não tem seguro recebe lista vazia', async () => {
    expect(await fonte().daPessoa(SEGURO_QUE_NAO_EXISTE)).toEqual([]);
    expect(await fonte().daEmpresa(SEGURO_QUE_NAO_EXISTE)).toEqual([]);
  });
});

describe('um seguro e a história', () => {
  it('traz o seguro com as datas em segundos e o documento sem valor', async () => {
    const seguro = await fonte().seguro(SEGURO_COM_PDF);

    expect(seguro).toMatchObject({
      id: SEGURO_COM_PDF,
      pessoaId: PESSOA_DAS_JORNADAS,
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      numero: 'AT-000451',
      valor: 2760,
      temPdf: true,
      canceladoEm: null,
    });
    expect(seguro.segurado.documento).toBeNull();
    expect(diasParaTerminar(seguro)).toBe(18);
    expect(seguro.comeca).toBeLessThan(seguro.termina);
  });

  it('a história vem do mais novo ao mais velho, com o que mudou na planilha', async () => {
    const historia = await fonte().historia(SEGURO_SEM_PDF);

    expect(historia.map(passo => passo.tipo)).toEqual([
      'chegou_de_novo',
      'chegou_planilha',
    ]);
    expect(historia[0].mudancas).toEqual([
      { campo: 'valor', antes: 610, depois: 640 },
    ]);
    expect(historia[0].quando).toBeGreaterThan(historia[1].quando);
    expect(historia[1].quem).toBeNull();
  });

  it.each(['seguro', 'historia', 'pdf', 'cancelar', 'tirarPdf'])(
    '%s de um seguro que não existe falha como o servidor',
    async metodo => {
      await expect(
        fonte()[metodo](SEGURO_QUE_NAO_EXISTE)
      ).rejects.toMatchObject({ name: NAO_ACHEI });
    }
  );

  it('o "PDF" da demonstração é uma página em branco', async () => {
    expect(await fonte().pdf(SEGURO_COM_PDF)).toBe('about:blank');
  });
});

describe('escritas (só na memória)', () => {
  it('cancelar e voltar a ativo mudam o selo e contam a história', async () => {
    const cancelado = await fonte().cancelar(SEGURO_COM_PDF);
    expect(seloDoSeguro(cancelado)).toBe(SELOS.CANCELADO);
    expect(seloDoSeguro(await fonte().seguro(SEGURO_COM_PDF))).toBe(
      SELOS.CANCELADO
    );

    const ativo = await fonte().voltarAAtivo(SEGURO_COM_PDF);
    expect(seloDoSeguro(ativo)).toBe(SELOS.ATIVO);

    const historia = await fonte().historia(SEGURO_COM_PDF);
    expect(historia.map(passo => passo.tipo)).toEqual([
      'voltou_a_ativo',
      'cancelado',
      'chegou_planilha',
    ]);
    expect(historia[0].quem).toEqual({ id: 1, nome: 'Bia Lunardelli' });
  });

  it('corrigir guarda o que mudou, marca os campos e conta o antes e o depois', async () => {
    const antes = await fonte().seguro(SEGURO_SEM_PDF);

    const depois = await fonte().corrigir(SEGURO_SEM_PDF, {
      valor: 700,
      bem: 'Casa em Campinas',
    });

    expect(depois).toMatchObject({ valor: 700, bem: 'Casa em Campinas' });
    expect(depois.corrigidoAMao).toEqual(['valor', 'bem']);
    expect(antes.valor).toBe(640);
    const [passo] = await fonte().historia(SEGURO_SEM_PDF);
    expect(passo.tipo).toBe('corrigido');
    expect(passo.mudancas).toEqual([
      { campo: 'valor', antes: 640, depois: 700 },
      {
        campo: 'bem',
        antes: 'Apartamento em São Paulo',
        depois: 'Casa em Campinas',
      },
    ]);
  });

  it('guardar e tirar o PDF mudam o seguro', async () => {
    const pdf = new File(['%PDF-1.4'], 'apolice.pdf', {
      type: 'application/pdf',
    });

    expect((await fonte().guardarPdf(SEGURO_SEM_PDF, pdf)).temPdf).toBe(true);
    expect((await fonte().tirarPdf(SEGURO_SEM_PDF)).temPdf).toBe(false);
    const historia = await fonte().historia(SEGURO_SEM_PDF);
    expect(historia.slice(0, 2).map(passo => passo.tipo)).toEqual([
      'pdf_tirado',
      'pdf_anexado',
    ]);
  });

  it('o que não é PDF volta recusado, com o código do servidor', async () => {
    const foto = new File(['x'], 'foto.png', { type: 'image/png' });

    await expect(
      fonte().guardarPdf(SEGURO_SEM_PDF, foto)
    ).rejects.toMatchObject({ name: RECUSADO, codigo: 'tipo' });
    expect((await fonte().seguro(SEGURO_SEM_PDF)).temPdf).toBe(false);
  });

  it('a escrita aparece na lista e some ao esquecer', async () => {
    await fonte().cancelar(SEGURO_COM_PDF);
    const antes = await fonte().contagens(ABA_SEGUROS, { busca: 'AT-000451' });
    expect(antes.vence_30_dias).toBe(0);

    esquecerEscritasDaCarteira();

    const depois = await fonte().contagens(ABA_SEGUROS, {
      busca: 'AT-000451',
    });
    expect(depois.vence_30_dias).toBe(1);
  });
});

describe('estados da demonstração', () => {
  it.each(['vazio', 'sem-seguros', 'fora-do-segmento'])(
    '%s não tem seguro nenhum',
    async estado => {
      expect(await fonte(estado).resumo()).toEqual({ total: 0, vence7: 0 });
      expect(await fonte(estado).listar({ grupo: 'todos' })).toEqual({
        itens: [],
        total: 0,
        temMais: false,
      });
      expect(await fonte(estado).daPessoa(PESSOA_DAS_JORNADAS)).toEqual([]);
      expect(await fonte(estado).opcoesDeFiltro()).toEqual({
        tipos: [],
        seguradoras: [],
      });
      await expect(fonte(estado).seguro(SEGURO_COM_PDF)).rejects.toMatchObject({
        name: NAO_ACHEI,
      });
    }
  );

  it('`?demo-carteira=vazio` esvazia só a carteira', async () => {
    expect(await fonte('cheio', 'vazio').daPessoa(PESSOA_DAS_JORNADAS)).toEqual(
      []
    );
    expect((await fonte('cheio', 'vazio').resumo()).total).toBe(0);
  });

  it('`?demo-carteira=erro` falha toda leitura', async () => {
    await expect(fonte('cheio', 'erro').resumo()).rejects.toMatchObject({
      name: 'ERRO_DA_DEMO',
    });
    await expect(
      fonte('cheio', 'erro').daPessoa(PESSOA_DAS_JORNADAS)
    ).rejects.toThrow();
  });

  it.each([
    ['carregando', null],
    ['cheio', 'carregando'],
  ])('em carregando (%s, %s) a fonte nunca responde', async (estado, peca) => {
    vi.useFakeTimers();
    const resposta = vi.fn();

    fonte(estado, peca).resumo().then(resposta, resposta);
    await vi.advanceTimersByTimeAsync(BEM_DEPOIS_MS);

    expect(resposta).not.toHaveBeenCalled();
  });
});
