import en from 'dashboard/i18n/locale/en/relacionamentosCarteira.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/relacionamentosCarteira.json';
import { abrirPdf } from '../../carteira/abrirPdf';
import {
  doCampoDeData,
  formatarDataInteira,
  formatarHora,
  formatarValor,
  paraCampoDeData,
  valorDigitado,
  valorParaCampo,
} from '../../carteira/formatosDoSeguro';
import { fraseDoHeroiDeSeguros } from '../../carteira/fraseDoHeroiDeSeguros';
import {
  CONTA_EM_DIAS_ATE,
  quandoDoSeguro,
} from '../../carteira/quandoDoSeguro';
import {
  CODIGOS_DE_RECUSA,
  RECUSADO,
  chaveDaRecusa,
  codigoDaRecusa,
  seguroJaMudou,
} from '../../carteira/recusas';
import {
  DESTRUTIVOS,
  DO_RODAPE,
  rodapeDoSeguro,
} from '../../carteira/rodapeDoSeguro';
import { segurosDeExemplo } from '../../carteira/segurosDeExemplo';
import {
  TIPOS_DE_SEGURO,
  chaveDoTipo,
  iconeDoTipo,
} from '../../carteira/tiposDeSeguro';
import {
  VENCE_LOGO_EM_DIAS,
  chaveDoSelo,
  tomDoSelo,
} from '../../carteira/tomDoSelo';
import {
  GRUPOS_DE_SEGUROS,
  GRUPO_VENCIDO,
  seguroPertenceAoGrupo,
} from '../../fonte/gruposDeSeguros';
import {
  SELOS,
  diasParaTerminar,
  estaValendo,
  porUrgencia,
  seloDoSeguro,
} from '../../fonte/selosDoSeguro';
import { aoMeioDia } from './apoio';

// As funções puras da carteira de seguros (#2897). O relógio é fixo:
// 12/11/2026, às 10h de quem roda o teste.
const AGORA = new Date(2026, 10, 12, 10).getTime();
// Um seguro que termina a `dias` de hoje (negativo = já terminou).
const terminaEm = (dias, resto = {}) => ({
  id: 1,
  termina: aoMeioDia(2026, 11, 12 + dias),
  canceladoEm: null,
  pessoa: { id: 5, phone_number: '+5511900000001' },
  ...resto,
});
const semEspacoDuro = texto => texto.replaceAll(' ', ' ');

// A frase do catálogo de um idioma, pelo caminho com pontos.
const doCatalogo = (catalogo, chave) =>
  chave.split('.').reduce((no, parte) => no?.[parte], catalogo);

describe('selo do seguro', () => {
  it('conta os dias pela data quando o servidor não mandou', () => {
    expect(diasParaTerminar(terminaEm(18), AGORA)).toBe(18);
    expect(diasParaTerminar(terminaEm(0), AGORA)).toBe(0);
    expect(diasParaTerminar(terminaEm(-4), AGORA)).toBe(-4);
  });

  it('usa os dias e o selo do servidor, sem olhar o relógio', () => {
    const doServidor = terminaEm(40, { selo: SELOS.VENCIDO, dias: -2 });

    expect(diasParaTerminar(doServidor, AGORA)).toBe(-2);
    expect(seloDoSeguro(doServidor, AGORA)).toBe(SELOS.VENCIDO);
    expect(estaValendo(doServidor, AGORA)).toBe(false);
  });

  it('pela data: ativo até o dia em que termina, vencido depois', () => {
    expect(seloDoSeguro(terminaEm(0), AGORA)).toBe(SELOS.ATIVO);
    expect(seloDoSeguro(terminaEm(-1), AGORA)).toBe(SELOS.VENCIDO);
    expect(estaValendo(terminaEm(30), AGORA)).toBe(true);
  });

  it('cancelado ganha de vencido e de ativo', () => {
    expect(seloDoSeguro(terminaEm(30, { canceladoEm: 1 }), AGORA)).toBe(
      SELOS.CANCELADO
    );
    expect(seloDoSeguro(terminaEm(-30, { canceladoEm: 1 }), AGORA)).toBe(
      SELOS.CANCELADO
    );
  });

  it('a ordem de urgência: vencido, ativo (quem termina antes) e cancelado', () => {
    const seguros = [
      terminaEm(5, { id: 1, canceladoEm: 9 }),
      terminaEm(200, { id: 2 }),
      terminaEm(-3, { id: 3 }),
      terminaEm(18, { id: 4 }),
      terminaEm(18, { id: 5 }),
    ];

    expect(porUrgencia(seguros, AGORA).map(s => s.id)).toEqual([3, 4, 5, 2, 1]);
    expect(seguros.map(s => s.id)).toEqual([1, 2, 3, 4, 5]);
    expect(porUrgencia()).toEqual([]);
  });

  it('cada selo tem cor e nome no catálogo', () => {
    expect(tomDoSelo(SELOS.ATIVO)).toBe('verde');
    expect(tomDoSelo(SELOS.VENCIDO)).toBe('vermelho');
    expect(tomDoSelo(SELOS.CANCELADO)).toBe('neutro');
    expect(tomDoSelo('inventado')).toBe('neutro');
    Object.values(SELOS).forEach(selo => {
      expect(doCatalogo(ptBR, chaveDoSelo(selo))).toBeTruthy();
      expect(doCatalogo(en, chaveDoSelo(selo))).toBeTruthy();
    });
  });

  it('o ativo que vence logo fica em âmbar, e só ele', () => {
    expect(tomDoSelo(SELOS.ATIVO, VENCE_LOGO_EM_DIAS)).toBe('ambar');
    expect(tomDoSelo(SELOS.ATIVO, 0)).toBe('ambar');
    expect(tomDoSelo(SELOS.ATIVO, VENCE_LOGO_EM_DIAS + 1)).toBe('verde');
    expect(tomDoSelo(SELOS.VENCIDO, -3)).toBe('vermelho');
    expect(tomDoSelo(SELOS.CANCELADO, 5)).toBe('neutro');
  });
});

describe('grupos da aba Seguros', () => {
  it.each([
    ['vence_7_dias', 7, 8],
    ['vence_30_dias', 30, 31],
    ['vence_90_dias', 90, 91],
  ])('%s inclui até %i dias e deixa %i de fora', (grupo, dentro, fora) => {
    expect(seguroPertenceAoGrupo(terminaEm(dentro), grupo, AGORA)).toBe(true);
    expect(seguroPertenceAoGrupo(terminaEm(0), grupo, AGORA)).toBe(true);
    expect(seguroPertenceAoGrupo(terminaEm(fora), grupo, AGORA)).toBe(false);
  });

  it('os grupos de vencimento não contam vencido nem cancelado', () => {
    const cancelado = terminaEm(3, { canceladoEm: 1 });

    expect(seguroPertenceAoGrupo(terminaEm(-1), 'vence_7_dias', AGORA)).toBe(
      false
    );
    expect(seguroPertenceAoGrupo(cancelado, 'vence_7_dias', AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(cancelado, 'vencido', AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(cancelado, 'todos', AGORA)).toBe(true);
  });

  it('"vencido" é quem já terminou', () => {
    expect(seguroPertenceAoGrupo(terminaEm(-1), 'vencido', AGORA)).toBe(true);
    expect(seguroPertenceAoGrupo(terminaEm(0), 'vencido', AGORA)).toBe(false);
  });

  it('"sem telefone" olha a pessoa do seguro', () => {
    const semTelefone = terminaEm(3, { pessoa: { id: 5, phone_number: null } });

    expect(seguroPertenceAoGrupo(semTelefone, 'sem_telefone', AGORA)).toBe(
      true
    );
    expect(seguroPertenceAoGrupo(terminaEm(3), 'sem_telefone', AGORA)).toBe(
      false
    );
  });

  it('grupo que não existe não tem ninguém', () => {
    expect(seguroPertenceAoGrupo(terminaEm(3), 'inventado', AGORA)).toBe(false);
  });

  it('todo grupo tem nome nos dois idiomas, e explicação menos o "Todos"', () => {
    GRUPOS_DE_SEGUROS.forEach(({ id, nome, explicacao }) => {
      expect(doCatalogo(ptBR, nome)).toBeTruthy();
      expect(doCatalogo(en, nome)).toBeTruthy();
      expect(Boolean(explicacao)).toBe(id !== 'todos');
      if (!explicacao) return;
      expect(doCatalogo(ptBR, explicacao)).toBeTruthy();
      expect(doCatalogo(en, explicacao)).toBeTruthy();
    });
  });
});

describe('a frase de tempo do seguro', () => {
  it.each([
    [18, { id: 'VENCE_EM', count: 18 }],
    [CONTA_EM_DIAS_ATE, { id: 'VENCE_EM', count: CONTA_EM_DIAS_ATE }],
    [CONTA_EM_DIAS_ATE + 1, { id: 'VENCE_NA_DATA' }],
    [1, { id: 'VENCE_AMANHA' }],
    [0, { id: 'VENCE_HOJE' }],
    [-1, { id: 'VENCEU_ONTEM' }],
    [-12, { id: 'VENCEU_HA', count: 12 }],
  ])('a %i dias de terminar diz %o', (dias, esperado) => {
    expect(quandoDoSeguro(terminaEm(dias), AGORA)).toMatchObject(esperado);
  });

  it('leva a data de quem ainda vai vencer', () => {
    const seguro = terminaEm(18);

    expect(quandoDoSeguro(seguro, AGORA).data).toBe(seguro.termina);
    expect(quandoDoSeguro(terminaEm(200), AGORA).data).toBe(
      terminaEm(200).termina
    );
  });

  it('o cancelado diz quando foi cancelado', () => {
    expect(
      quandoDoSeguro(terminaEm(40, { canceladoEm: 1700000000 }), AGORA)
    ).toEqual({ id: 'CANCELADO_EM', data: 1700000000 });
  });

  it('segue o selo e os dias do servidor', () => {
    const doServidor = terminaEm(40, { selo: SELOS.VENCIDO, dias: -3 });

    expect(quandoDoSeguro(doServidor, AGORA)).toEqual({
      id: 'VENCEU_HA',
      count: 3,
    });
  });

  it('toda frase existe na lista, na ficha e na gaveta, nos dois idiomas', () => {
    const frases = [
      'VENCE_EM',
      'VENCE_AMANHA',
      'VENCE_HOJE',
      'VENCE_NA_DATA',
      'VENCEU_HA',
      'VENCEU_ONTEM',
      'CANCELADO_EM',
    ];
    [ptBR, en].forEach(catalogo => {
      const { QUANDO, GAVETA } = catalogo.RELACIONAMENTOS_CARTEIRA;
      frases.forEach(frase => {
        expect(QUANDO.LISTA[frase]).toBeTruthy();
        expect(QUANDO.FICHA[frase]).toBeTruthy();
        expect(GAVETA.FRASE[frase]).toBeTruthy();
      });
    });
  });
});

describe('formatos', () => {
  it('escreve o valor em reais, com centavos', () => {
    expect(semEspacoDuro(formatarValor(2760, 'pt-BR'))).toBe('R$ 2.760,00');
    expect(semEspacoDuro(formatarValor(640.5, 'pt-BR'))).toBe('R$ 640,50');
    expect(semEspacoDuro(formatarValor(0, 'pt-BR'))).toBe('R$ 0,00');
  });

  it('escreve a data inteira e a hora no idioma do painel', () => {
    const dia = aoMeioDia(2026, 11, 29);
    const hora = new Date(2026, 10, 12, 14, 20).getTime() / 1000;

    expect(formatarDataInteira(dia, 'pt-BR')).toBe('29/11/2026');
    expect(formatarDataInteira(dia, 'en')).toBe('11/29/2026');
    expect(formatarHora(hora, 'pt-BR')).toBe('14:20');
  });

  it('do campo de data para segundos e de volta dá o mesmo dia', () => {
    expect(doCampoDeData('2026-11-29')).toBe(aoMeioDia(2026, 11, 29));
    expect(paraCampoDeData(aoMeioDia(2026, 11, 29))).toBe('2026-11-29');
    expect(paraCampoDeData(aoMeioDia(2026, 1, 5))).toBe('2026-01-05');
    ['2024-02-29', '2026-12-31', '2027-01-01'].forEach(dia => {
      expect(paraCampoDeData(doCampoDeData(dia))).toBe(dia);
    });
  });

  it('sem data, o campo fica vazio e o valor é null', () => {
    expect(paraCampoDeData(null)).toBe('');
    expect(paraCampoDeData(undefined)).toBe('');
    expect(doCampoDeData('')).toBeNull();
    expect(doCampoDeData(null)).toBeNull();
    expect(doCampoDeData(undefined)).toBeNull();
  });

  it.each(['2026-11-31', '2026-02-30', '2026-13-01', '26-11-29', 'amanhã'])(
    'a data %s não existe',
    texto => {
      expect(doCampoDeData(texto)).toBeNull();
    }
  );

  it.each([
    ['2.760,50', 2760.5],
    ['2760.5', 2760.5],
    ['12.50', 12.5],
    ['R$ 640', 640],
    ['640,5', 640.5],
    ['10,', 10],
    ['1.234', 1234],
    ['1.000.000', 1000000],
    ['0', 0],
  ])('lê o valor digitado %s como %d', (texto, valor) => {
    expect(valorDigitado(texto)).toBe(valor);
  });

  it.each(['', '   ', 'abc', ',', '1,2,3', '12,345', null, undefined])(
    'não entende %s como valor',
    texto => {
      expect(valorDigitado(texto)).toBeNull();
    }
  );

  it('põe o valor no campo do jeito de digitar em reais', () => {
    expect(valorParaCampo(2760.5)).toBe('2760,50');
    expect(valorParaCampo(0)).toBe('0,00');
    expect(valorParaCampo(null)).toBe('');
    expect(valorParaCampo(undefined)).toBe('');
    expect(valorDigitado(valorParaCampo(1150))).toBe(1150);
  });
});

describe('tipos de seguro', () => {
  it('cada tipo tem ícone e nome nos dois idiomas', () => {
    TIPOS_DE_SEGURO.forEach(tipo => {
      expect(iconeDoTipo(tipo)).toContain('i-lucide-');
      expect(doCatalogo(ptBR, chaveDoTipo(tipo))).toBeTruthy();
      expect(doCatalogo(en, chaveDoTipo(tipo))).toBeTruthy();
    });
  });

  it('tipo desconhecido cai em "Outro"', () => {
    expect(chaveDoTipo('pet')).toBe(chaveDoTipo('outro'));
    expect(iconeDoTipo(undefined)).toBe(iconeDoTipo('outro'));
  });
});

describe('o rodapé da gaveta', () => {
  const comPdf = terminaEm(18, { temPdf: true });
  const semPdf = terminaEm(18, { temPdf: false });
  const rodape = (seguro, opcoes) =>
    rodapeDoSeguro(seguro, { agora: AGORA, ...opcoes });

  it('com PDF, o azul é "Ver PDF" e o "⋯" troca, apaga e cancela', () => {
    expect(rodape(comPdf)).toEqual({
      azul: DO_RODAPE.VER_PDF,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [
        DO_RODAPE.GUARDAR_OUTRO_PDF,
        DO_RODAPE.APAGAR_PDF,
        DO_RODAPE.MARCAR_CANCELADO,
      ],
    });
  });

  it('valendo e sem PDF, o azul é "Guardar o PDF" e o "⋯" só cancela', () => {
    expect(rodape(semPdf)).toEqual({
      azul: DO_RODAPE.GUARDAR_PDF,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [DO_RODAPE.MARCAR_CANCELADO],
    });
  });

  it('vencido sem PDF não tem azul: guardar o PDF vai para o "⋯"', () => {
    expect(rodape(terminaEm(-4, { temPdf: false }))).toEqual({
      azul: null,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [DO_RODAPE.GUARDAR_PDF, DO_RODAPE.MARCAR_CANCELADO],
    });
  });

  it('cancelado sem PDF não tem azul e troca o cancelar por desfazer', () => {
    const cancelado = terminaEm(40, { temPdf: false, canceladoEm: 1700000000 });

    expect(rodape(cancelado)).toEqual({
      azul: null,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [DO_RODAPE.GUARDAR_PDF, DO_RODAPE.DESFAZER_CANCELAMENTO],
    });
  });

  it('vencido ou cancelado com PDF continua com "Ver PDF" em azul', () => {
    const vencido = terminaEm(-4, { temPdf: true });
    const cancelado = terminaEm(40, { temPdf: true, canceladoEm: 1700000000 });

    expect(rodape(vencido).azul).toBe(DO_RODAPE.VER_PDF);
    expect(rodape(cancelado)).toMatchObject({
      azul: DO_RODAPE.VER_PDF,
      menu: [
        DO_RODAPE.GUARDAR_OUTRO_PDF,
        DO_RODAPE.APAGAR_PDF,
        DO_RODAPE.DESFAZER_CANCELAMENTO,
      ],
    });
  });

  it('segue o selo do servidor, não o relógio', () => {
    const vencidoNoServidor = terminaEm(40, {
      temPdf: false,
      selo: SELOS.VENCIDO,
    });

    expect(rodape(vencidoNoServidor).azul).toBeNull();
  });

  it('o que não tem volta fácil é apagar o PDF e marcar como cancelado', () => {
    expect(DESTRUTIVOS).toEqual([
      DO_RODAPE.APAGAR_PDF,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
  });

  it('quem só pode ver fica só com "Ver PDF", e só quando há PDF', () => {
    expect(rodape(comPdf, { podeEditar: false })).toEqual({
      azul: DO_RODAPE.VER_PDF,
      secundario: null,
      menu: [],
    });
    expect(rodape(semPdf, { podeEditar: false })).toEqual({
      azul: null,
      secundario: null,
      menu: [],
    });
  });

  it('todo nome do rodapé tem frase nos dois idiomas', () => {
    Object.values(DO_RODAPE).forEach(nome => {
      expect(ptBR.RELACIONAMENTOS_CARTEIRA.GAVETA.RODAPE[nome]).toBeTruthy();
      expect(en.RELACIONAMENTOS_CARTEIRA.GAVETA.RODAPE[nome]).toBeTruthy();
    });
  });
});

describe('a frase do herói da aba', () => {
  it('sem seguro, diz que ainda não há e não tem botão', () => {
    expect(fraseDoHeroiDeSeguros({ total: 0, vence7: 0 })).toEqual({
      id: 'sem_seguro',
      frase: { chave: 'RELACIONAMENTOS_CARTEIRA.HEROI.SEM_SEGURO' },
      apoio: { chave: 'RELACIONAMENTOS_CARTEIRA.HEROI.SEM_SEGURO_APOIO' },
      principal: null,
    });
    expect(fraseDoHeroiDeSeguros().id).toBe('sem_seguro');
    // Carteira vazia não tem vencido: a contagem não muda a frase.
    expect(fraseDoHeroiDeSeguros({ total: 0 }, 4).id).toBe('sem_seguro');
  });

  it('com seguro vencendo em 7 dias, diz quantos e leva ao grupo', () => {
    expect(fraseDoHeroiDeSeguros({ total: 40, vence7: 3 })).toMatchObject({
      id: 'vence_7',
      frase: { count: 3 },
      principal: {
        rotulo: 'RELACIONAMENTOS_CARTEIRA.HEROI.VER_QUAIS',
        grupo: 'vence_7_dias',
      },
    });
  });

  it('sem nada vencendo na semana e com vencidos, fala dos vencidos', () => {
    expect(fraseDoHeroiDeSeguros({ total: 40, vence7: 0 }, 5)).toMatchObject({
      id: 'vencidos',
      frase: { chave: 'RELACIONAMENTOS_CARTEIRA.HEROI.VENCIDOS', count: 5 },
      principal: {
        rotulo: 'RELACIONAMENTOS_CARTEIRA.HEROI.VER_VENCIDOS',
        grupo: GRUPO_VENCIDO,
      },
    });
  });

  it('com os dois, vale a frase de quem vence em 7 dias', () => {
    expect(fraseDoHeroiDeSeguros({ total: 40, vence7: 3 }, 5).id).toBe(
      'vence_7'
    );
  });

  it('sem ninguém vencendo nem vencido, resume a carteira e leva a todos', () => {
    expect(fraseDoHeroiDeSeguros({ total: 40, vence7: 0 })).toMatchObject({
      id: 'resumo',
      frase: { count: 40 },
      principal: { grupo: 'todos' },
    });
  });

  it('ignora o que o servidor manda a mais no resumo', () => {
    const resumo = {
      total: 2,
      vence7: 0,
      vence7EmRenovacao: 0,
      emRenovacao: 0,
      aggerLigado: false,
    };

    expect(fraseDoHeroiDeSeguros(resumo).id).toBe('resumo');
  });

  it.each([
    ['sem_seguro', {}, 0],
    ['vence_7', { total: 9, vence7: 2 }, 0],
    ['vencidos', { total: 9 }, 3],
    ['resumo', { total: 9 }, 0],
  ])(
    'a frase e o botão de %s existem nos dois idiomas',
    (id, resumo, vencidos) => {
      const heroi = fraseDoHeroiDeSeguros(resumo, vencidos);

      expect(heroi.id).toBe(id);
      [heroi.frase.chave, heroi.apoio?.chave, heroi.principal?.rotulo]
        .filter(Boolean)
        .forEach(chave => {
          expect(doCatalogo(ptBR, chave)).toBeTruthy();
          expect(doCatalogo(en, chave)).toBeTruthy();
        });
    }
  );
});

describe('recusas', () => {
  const recusa = codigo =>
    Object.assign(new Error('x'), { name: RECUSADO, codigo });

  it('lê o código só da falha RECUSADO e só se for conhecido', () => {
    expect(codigoDaRecusa(recusa('termina_antes'))).toBe('termina_antes');
    expect(codigoDaRecusa(recusa('inventado'))).toBe('');
    expect(codigoDaRecusa(recusa(''))).toBe('');
    expect(codigoDaRecusa(new Error('rede'))).toBe('');
    expect(codigoDaRecusa(null)).toBe('');
  });

  it('sabe quando o seguro mudou por outro caminho', () => {
    expect(seguroJaMudou('ja_cancelado')).toBe(true);
    expect(seguroJaMudou('nao_cancelado')).toBe(true);
    expect(seguroJaMudou('sem_pdf')).toBe(true);
    expect(seguroJaMudou('valor_invalido')).toBe(false);
    expect(seguroJaMudou('')).toBe(false);
  });

  it('escolhe a frase pelo código; sem código conhecido, a frase de sempre', () => {
    expect(chaveDaRecusa('sem_pdf', 'PADRAO')).toBe(
      'RELACIONAMENTOS_CARTEIRA.RECUSAS.SEM_PDF'
    );
    expect(chaveDaRecusa('', 'PADRAO')).toBe('PADRAO');
    expect(chaveDaRecusa('inventado', 'PADRAO')).toBe('PADRAO');
  });

  it.each(CODIGOS_DE_RECUSA)(
    'o código %s tem frase nos dois idiomas, sem lugar para o valor digitado',
    codigo => {
      const chave = chaveDaRecusa(codigo, '');

      expect(doCatalogo(ptBR, chave)).toBeTruthy();
      expect(doCatalogo(en, chave)).toBeTruthy();
      expect(doCatalogo(ptBR, chave)).not.toContain('{');
      expect(doCatalogo(en, chave)).not.toContain('{');
    }
  );
});

describe('os seguros de exemplo', () => {
  it('são cinco, de pessoas inventadas, todos ainda valendo', () => {
    const exemplos = segurosDeExemplo(AGORA);

    expect(exemplos).toHaveLength(5);
    expect(exemplos.every(seguro => estaValendo(seguro, AGORA))).toBe(true);
    expect(exemplos.every(seguro => seguro.segurado.nome)).toBe(true);
    expect(new Set(exemplos.map(seguro => seguro.id)).size).toBe(5);
  });
});

describe('ver o PDF', () => {
  const janelaCom = aba => ({
    open: vi.fn(() => aba),
    location: { assign: vi.fn() },
  });
  const abaNova = () => ({
    opener: {},
    location: { replace: vi.fn() },
    close: vi.fn(),
  });

  it('abre a aba em branco no clique e só depois leva ao PDF', async () => {
    const aba = abaNova();
    const janela = janelaCom(aba);
    let soltar;
    const pedirLink = vi.fn(
      () =>
        new Promise(resolve => {
          soltar = resolve;
        })
    );

    const abrindo = abrirPdf(pedirLink, janela);

    expect(janela.open).toHaveBeenCalledWith('', '_blank');
    expect(aba.opener).toBeNull();
    expect(aba.location.replace).not.toHaveBeenCalled();

    soltar('https://arquivos.example/apolice');

    expect(await abrindo).toBeNull();
    expect(aba.location.replace).toHaveBeenCalledWith(
      'https://arquivos.example/apolice'
    );
    expect(janela.location.assign).not.toHaveBeenCalled();
  });

  it('se o navegador bloqueou a aba nova, o PDF abre nesta', async () => {
    const janela = janelaCom(null);

    const falha = await abrirPdf(
      () => Promise.resolve('https://arquivos.example/apolice'),
      janela
    );

    expect(falha).toBeNull();
    expect(janela.location.assign).toHaveBeenCalledWith(
      'https://arquivos.example/apolice'
    );
  });

  it('quando o link não vem, fecha a aba em branco e devolve a falha', async () => {
    const aba = abaNova();
    const semPdf = Object.assign(new Error('x'), {
      name: RECUSADO,
      codigo: 'sem_pdf',
    });

    const falha = await abrirPdf(() => Promise.reject(semPdf), janelaCom(aba));

    expect(falha).toBe(semPdf);
    expect(aba.close).toHaveBeenCalled();
    expect(aba.location.replace).not.toHaveBeenCalled();
  });

  it('quando o link não vem e não há aba, só devolve a falha', async () => {
    const janela = janelaCom(null);
    const rede = new Error('rede');

    expect(await abrirPdf(() => Promise.reject(rede), janela)).toBe(rede);
    expect(janela.location.assign).not.toHaveBeenCalled();
  });
});
