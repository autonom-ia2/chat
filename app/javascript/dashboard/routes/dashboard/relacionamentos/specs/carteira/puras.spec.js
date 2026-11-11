import pt from 'dashboard/i18n/locale/pt_BR/relacionamentosCarteira.json';
import en from 'dashboard/i18n/locale/en/relacionamentosCarteira.json';
import ptLista from 'dashboard/i18n/locale/pt_BR/relacionamentos.json';
import ptFicha from 'dashboard/i18n/locale/pt_BR/relacionamentosFicha.json';
import ptTrazer from 'dashboard/i18n/locale/pt_BR/relacionamentosTrazer.json';
import { DIA_EM_MS } from '../../fonte/grupos';
import { seguroPertenceAoGrupo } from '../../fonte/gruposDeSeguros';
import {
  SELOS,
  maisUrgente,
  porUrgencia,
  seloDoSeguro,
} from '../../fonte/selosDoSeguro';
import { fraseDoHeroiDeSeguros } from '../../carteira/fraseDoHeroiDeSeguros';
import {
  doCampoDeData,
  formatarDataInteira,
  formatarValor,
  paraCampoDeData,
  valorDigitado,
  valorParaCampo,
} from '../../carteira/formatosDoSeguro';
import {
  OUTRA_SEGURADORA,
  cardNasceAmanha,
  dadosParaCorrigir,
  faltasDoFormulario,
  formularioDoSeguro,
  primeiroCampoQueFalta,
} from '../../carteira/formularioDoSeguro';
import { quandoDoSeguro } from '../../carteira/quandoDoSeguro';
import {
  ACOES_DO_SEGURO,
  situacaoDoSeguro,
  variacaoDaProposta,
} from '../../carteira/situacaoDoSeguro';

// As regras puras da carteira (#2897): selo pela data de hoje, grupos, frase do
// herói, situação da gaveta, formatos e o formulário de correção.
const AGORA = Date.UTC(2026, 10, 11, 15, 0, 0);
const em = dias => Math.floor((AGORA + dias * DIA_EM_MS) / 1000);
const seguro = (extras = {}) => ({
  id: 1,
  tipo: 'auto',
  seguradora: 'Seguradora Atlântica',
  numero: 'AT-000451',
  valor: 2760,
  bem: 'Carro hatch prata, placa FIC-0A23',
  comeca: em(-347),
  termina: em(18),
  temPdf: true,
  renovacao: null,
  canceladoEm: null,
  renovadoEm: null,
  parcelaAbertaEm: null,
  pessoa: { name: 'Fábio Kalinoski', phone_number: '+5511910000023' },
  ...extras,
});
const card = { etapa: 'Opções enviadas', cuida: 'Bia Lunardelli' };

describe('seloDoSeguro', () => {
  it.each([
    [
      'ativo quando termina daqui a mais de 60 dias',
      { termina: em(61) },
      SELOS.ATIVO,
    ],
    [
      'em renovação com card e até 60 dias',
      { termina: em(60), renovacao: card },
      SELOS.EM_RENOVACAO,
    ],
    ['ativo sem card, mesmo perto do fim', { termina: em(10) }, SELOS.ATIVO],
    ['vencido quando já terminou', { termina: em(-1) }, SELOS.VENCIDO],
    ['ainda vale no dia em que termina', { termina: em(0) }, SELOS.ATIVO],
    [
      'renovado enquanto falta a apólice nova',
      { termina: em(4), renovadoEm: em(-3) },
      SELOS.RENOVADO,
    ],
    [
      'cancelado ganha de tudo',
      { termina: em(-5), canceladoEm: em(-40) },
      SELOS.CANCELADO,
    ],
    ['em outra corretora', { deFora: true }, SELOS.EM_OUTRA_CORRETORA],
  ])('%s', (_, extras, esperado) => {
    expect(seloDoSeguro(seguro(extras), AGORA)).toBe(esperado);
  });
});

describe('grupos de seguros', () => {
  it('os grupos de vencimento acumulam e só contam quem ainda vale', () => {
    const em5 = seguro({ termina: em(5), renovacao: card });
    expect(seguroPertenceAoGrupo(em5, 'vence_7_dias', AGORA)).toBe(true);
    expect(seguroPertenceAoGrupo(em5, 'vence_30_dias', AGORA)).toBe(true);
    expect(seguroPertenceAoGrupo(em5, 'vence_90_dias', AGORA)).toBe(true);
    const cancelado = seguro({ termina: em(5), canceladoEm: em(-1) });
    expect(seguroPertenceAoGrupo(cancelado, 'vence_7_dias', AGORA)).toBe(false);
    const vencido = seguro({ termina: em(-2) });
    expect(seguroPertenceAoGrupo(vencido, 'vence_7_dias', AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(vencido, 'vencido', AGORA)).toBe(true);
  });

  it('sem telefone olha a pessoa; grupo que não existe não tem ninguém', () => {
    const semTelefone = seguro({
      pessoa: { name: 'Tiago', phone_number: null },
    });
    expect(seguroPertenceAoGrupo(semTelefone, 'sem_telefone', AGORA)).toBe(
      true
    );
    expect(seguroPertenceAoGrupo(seguro(), 'sem_telefone', AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(seguro(), 'inventado', AGORA)).toBe(false);
  });
});

describe('o mais urgente de uma pessoa', () => {
  it('vencido > parcela atrasada > em renovação > renovado', () => {
    const vencido = seguro({ id: 2, termina: em(-3) });
    const parcela = seguro({
      id: 3,
      termina: em(200),
      parcelaAbertaEm: em(-10),
    });
    const renovando = seguro({ id: 4, renovacao: card });
    const renovado = seguro({ id: 5, renovadoEm: em(-1) });
    expect(
      maisUrgente([renovado, renovando, parcela, vencido], AGORA).selo
    ).toBe('vencido');
    expect(maisUrgente([renovado, renovando, parcela], AGORA).selo).toBe(
      'parcela_atrasada'
    );
    expect(maisUrgente([renovado, renovando], AGORA).selo).toBe('em_renovacao');
    expect(maisUrgente([renovado], AGORA).selo).toBe('renovado');
  });

  it('ativo e cancelado não pedem atenção', () => {
    const ativo = seguro({ termina: em(200) });
    const cancelado = seguro({ canceladoEm: em(-2) });
    expect(maisUrgente([ativo, cancelado], AGORA)).toBeNull();
  });

  it('na ficha, o cancelado vai para o fim', () => {
    const ordem = porUrgencia(
      [
        seguro({ id: 9, canceladoEm: em(-2) }),
        seguro({ id: 8, termina: em(300) }),
        seguro({ id: 7, renovacao: card }),
        seguro({ id: 6, termina: em(-4) }),
      ],
      AGORA
    ).map(s => s.id);
    expect(ordem).toEqual([6, 7, 8, 9]);
  });
});

describe('fraseDoHeroiDeSeguros', () => {
  it('sem seguro, o convite é trazer', () => {
    const frase = fraseDoHeroiDeSeguros({ total: 0 });
    expect(frase.id).toBe('sem_seguro');
    expect(frase.principal.acao).toBe('trazer');
    expect(frase.mostraTrazerDiscreto).toBe(false);
  });

  it('com seguro vencendo em 7 dias, leva ao grupo e diz se todos já estão em renovação', () => {
    const todos = fraseDoHeroiDeSeguros({
      total: 168,
      vence7: 5,
      vence7EmRenovacao: 5,
      emRenovacao: 22,
    });
    expect(todos.frase.count).toBe(5);
    expect(todos.principal.grupo).toBe('vence_7_dias');
    expect(todos.apoio).not.toBeNull();
    const nemTodos = fraseDoHeroiDeSeguros({
      total: 168,
      vence7: 5,
      vence7EmRenovacao: 4,
    });
    expect(nemTodos.apoio).toBeNull();
  });

  it('depois, quem está em renovação; por fim, o resumo', () => {
    expect(
      fraseDoHeroiDeSeguros({ total: 10, emRenovacao: 3 }).principal.grupo
    ).toBe('em_renovacao');
    const resumo = fraseDoHeroiDeSeguros({ total: 10 });
    expect(resumo.id).toBe('resumo');
    expect(resumo.principal.grupo).toBe('todos');
  });
});

describe('quandoDoSeguro', () => {
  it.each([
    [{ termina: em(18) }, { id: 'VENCE_EM', count: 18, data: em(18) }],
    [{ termina: em(90) }, { id: 'VENCE_EM', count: 90, data: em(90) }],
    // Acima de 90 dias ninguém conta em dias: só a data.
    [{ termina: em(91) }, { id: 'VENCE_NA_DATA', data: em(91) }],
    [{ termina: em(214) }, { id: 'VENCE_NA_DATA', data: em(214) }],
    [{ termina: em(1) }, { id: 'VENCE_AMANHA', data: em(1) }],
    [{ termina: em(0) }, { id: 'VENCE_HOJE' }],
    [{ termina: em(-1) }, { id: 'VENCEU_ONTEM' }],
    [{ termina: em(-12) }, { id: 'VENCEU_HA', count: 12 }],
    [{ canceladoEm: em(-40) }, { id: 'CANCELADO_EM', data: em(-40) }],
    [{ renovadoEm: em(-3) }, { id: 'RENOVOU_EM', data: em(-3) }],
    [{ deFora: true }, { id: 'EM_OUTRA_CORRETORA' }],
  ])('%o', (extras, esperado) => {
    expect(quandoDoSeguro(seguro(extras), AGORA)).toEqual(esperado);
  });
});

describe('situacaoDoSeguro: um próximo passo por vez', () => {
  it.each([
    [
      'em renovação abre a renovação',
      { renovacao: card },
      ACOES_DO_SEGURO.ABRIR_RENOVACAO,
    ],
    [
      'ativo com PDF mostra o PDF',
      { termina: em(200) },
      ACOES_DO_SEGURO.VER_PDF,
    ],
    [
      'ativo sem PDF pede o PDF',
      { termina: em(200), temPdf: false },
      ACOES_DO_SEGURO.ANEXAR_PDF,
    ],
    [
      'parcela atrasada avisa a pessoa',
      { termina: em(200), parcelaAbertaEm: em(-10) },
      ACOES_DO_SEGURO.AVISAR,
    ],
    [
      'renovado pede a apólice nova',
      { renovadoEm: em(-3) },
      ACOES_DO_SEGURO.ANEXAR_APOLICE_NOVA,
    ],
    [
      'vencido chama para conversar',
      { termina: em(-12) },
      ACOES_DO_SEGURO.CONVERSAR_COM,
    ],
    [
      'cancelado mostra o PDF',
      { canceladoEm: em(-40) },
      ACOES_DO_SEGURO.VER_PDF,
    ],
  ])('%s', (_, extras, acao) => {
    expect(situacaoDoSeguro(seguro(extras), AGORA).acao).toBe(acao);
  });

  it('diz se a proposta subiu, baixou ou ficou igual', () => {
    expect(variacaoDaProposta({ variacao: 8 })).toEqual({
      id: 'SUBIU',
      count: 8,
    });
    expect(variacaoDaProposta({ variacao: -3 })).toEqual({
      id: 'BAIXOU',
      count: 3,
    });
    expect(variacaoDaProposta({ variacao: 0 })).toEqual({ id: 'IGUAL' });
    expect(variacaoDaProposta(null)).toBeNull();
  });
});

describe('formatos', () => {
  it('valor com centavos e data inteira, no idioma do painel', () => {
    // O Intl separa "R$" do número com um espaço que não quebra a linha.
    expect(formatarValor(2760, 'pt-BR').split('\u00a0').join(' ')).toBe(
      'R$ 2.760,00'
    );
    expect(formatarDataInteira(em(18), 'pt-BR')).toBe('29/11/2026');
  });

  it('o campo de data vai e volta sem trocar o dia', () => {
    const texto = paraCampoDeData(em(18));
    expect(texto).toBe('2026-11-29');
    expect(paraCampoDeData(doCampoDeData(texto))).toBe(texto);
    expect(doCampoDeData('')).toBeNull();
    expect(doCampoDeData('2026-02-31')).toBeNull();
  });

  it.each([
    ['2.760,50', 2760.5],
    ['2760,5', 2760.5],
    ['R$ 640', 640],
    ['2760.5', 2760.5],
    ['2.760', 2760],
    ['1.234.567', 1234567],
    ['', null],
    ['abc', null],
    ['1,2,3', null],
  ])('entende o valor digitado %s', (texto, numero) => {
    expect(valorDigitado(texto)).toBe(numero);
  });

  it('escreve o valor do jeito de digitar', () => {
    expect(valorParaCampo(2760.5)).toBe('2760,50');
    expect(valorParaCampo(null)).toBe('');
  });
});

describe('formulário de correção', () => {
  const SEGURADORAS = ['Seguradora Atlântica', 'Horizonte Seguros'];
  const inicial = formularioDoSeguro(seguro(), SEGURADORAS);

  it('abre com o que o seguro tem hoje', () => {
    expect(inicial).toEqual({
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      outraSeguradora: '',
      numero: 'AT-000451',
      comeca: '2025-11-29',
      termina: '2026-11-29',
      valor: '2760,00',
      bem: 'Carro hatch prata, placa FIC-0A23',
    });
  });

  it('seguradora que a conta não conhece abre em "Outra", com o nome escrito', () => {
    const outro = formularioDoSeguro(
      seguro({ seguradora: 'Vale Verde' }),
      SEGURADORAS
    );
    expect(outro.seguradora).toBe(OUTRA_SEGURADORA);
    expect(outro.outraSeguradora).toBe('Vale Verde');
  });

  it('sem mudança não há o que salvar', () => {
    expect(dadosParaCorrigir(inicial, inicial)).toEqual({});
  });

  it('só manda o que mudou, já no formato do seguro', () => {
    const atual = {
      ...inicial,
      valor: '2.980,80',
      termina: '2026-12-10',
      bem: ' Carro sedã ',
    };
    expect(dadosParaCorrigir(inicial, atual)).toEqual({
      valor: 2980.8,
      termina: doCampoDeData('2026-12-10'),
      bem: 'Carro sedã',
    });
  });

  it('"Outra" com nome vira a seguradora nova', () => {
    const atual = {
      ...inicial,
      seguradora: OUTRA_SEGURADORA,
      outraSeguradora: 'Vale Verde',
    };
    expect(dadosParaCorrigir(inicial, atual)).toEqual({
      seguradora: 'Vale Verde',
    });
  });

  it('diz o que falta, campo por campo, e qual vem primeiro na tela', () => {
    const faltas = faltasDoFormulario({
      ...inicial,
      seguradora: OUTRA_SEGURADORA,
      numero: ' ',
      termina: '',
      valor: 'abc',
    });
    expect(faltas).toEqual({
      outraSeguradora: 'OUTRA_SEGURADORA',
      numero: 'NUMERO',
      termina: 'TERMINA',
      valor: 'VALOR',
    });
    expect(primeiroCampoQueFalta(faltas)).toBe('outraSeguradora');
    expect(primeiroCampoQueFalta({})).toBeNull();
  });

  it('termina antes de começar pede para conferir as datas', () => {
    expect(faltasDoFormulario({ ...inicial, termina: '2025-01-01' })).toEqual({
      termina: 'TERMINA_ANTES',
    });
  });

  it('data nova dentro dos 60 dias, sem card: o card nasce amanhã', () => {
    expect(cardNasceAmanha(seguro({ termina: em(30) }), AGORA)).toBe(true);
    expect(
      cardNasceAmanha(seguro({ termina: em(30), renovacao: card }), AGORA)
    ).toBe(false);
    expect(cardNasceAmanha(seguro({ termina: em(90) }), AGORA)).toBe(false);
    expect(cardNasceAmanha(seguro({ termina: em(-2) }), AGORA)).toBe(false);
  });
});

describe('o catálogo da carteira', () => {
  const folhas = no =>
    Object.values(no).flatMap(valor =>
      typeof valor === 'string' ? [valor] : folhas(valor)
    );
  const ehLetra = char => char.toLowerCase() !== char.toUpperCase();
  const palavras = texto =>
    [...texto.toLowerCase()]
      .map(char => (ehLetra(char) ? char : ' '))
      .join('')
      .split(' ')
      .filter(Boolean);

  it('não usa as palavras que o corretor não usa', () => {
    const PROIBIDAS = [
      'vigência',
      'ramo',
      'prêmio',
      'sincronizar',
      'importar',
      'campo',
      'coluna',
      'api',
      'ia',
      'status',
      'registro',
    ];
    const usadas = new Set(folhas(pt).flatMap(palavras));
    expect(PROIBIDAS.filter(palavra => usadas.has(palavra))).toEqual([]);
  });

  it('não supõe o gênero de quem é cliente', () => {
    const texto = JSON.stringify(pt).toLowerCase();
    [
      'suas clientes',
      'seus clientes',
      'a cliente ',
      'o cliente ',
      'obrigado',
      'bem-vindo',
    ].forEach(trecho => expect(texto).not.toContain(trecho));
  });

  it('pt_BR e en têm as mesmas chaves', () => {
    const chaves = (no, prefixo = '') =>
      Object.entries(no).flatMap(([chave, valor]) =>
        typeof valor === 'string'
          ? [`${prefixo}${chave}`]
          : chaves(valor, `${prefixo}${chave}.`)
      );
    expect(chaves(en)).toEqual(chaves(pt));
  });

  it('os catálogos do bloco A continuam sem palavra de seguro', () => {
    const doBlocoA = [ptLista, ptFicha, ptTrazer]
      .flatMap(folhas)
      .flatMap(palavras);
    const DE_SEGURO = [
      'seguro',
      'seguros',
      'apólice',
      'apólices',
      'seguradora',
      'corretora',
    ];
    expect(doBlocoA.filter(palavra => DE_SEGURO.includes(palavra))).toEqual([]);
  });
});
