import en from 'dashboard/i18n/locale/en/relacionamentosCarteira.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/relacionamentosCarteira.json';
import {
  AJUSTES_PADRAO,
  FALTAS,
  MENSAGENS,
  ajustesMudaram,
  comOFunil,
  diasDigitados,
  etapasDoFunil,
  faltaNosAjustes,
  ondeFicam,
  quantosEntram,
  umDiaAMais,
  umDiaAMenos,
} from '../../carteira/ajustesDaRenovacao';
import {
  dadosDaApoliceNova,
  faltasDaApoliceNova,
  formularioDaApoliceNova,
} from '../../carteira/apoliceNova';
import { destinoDoCard } from '../../carteira/cardNoCrm';
import {
  baixarArquivo,
  csvDoHistorico,
  nomeDoArquivoDoHistorico,
} from '../../carteira/exportarHistoria';
import { DETALHES, fraseDoPasso } from '../../carteira/passoDoHistorico';
import { quandoDoSeguro } from '../../carteira/quandoDoSeguro';
import { CODIGOS_DE_RECUSA, chaveDaRecusa } from '../../carteira/recusas';
import {
  PERIODOS,
  RECORTES,
  grupoDosQueNaoRenovaram,
  linhasDoRecorte,
  motivosCitados,
  periodoEscolhido,
  porcentagem,
  recortesComLinhas,
  semMotivo,
} from '../../carteira/resultados';
import {
  DESTRUTIVOS,
  DO_RODAPE,
  rodapeDoSeguro,
} from '../../carteira/rodapeDoSeguro';
import {
  MOTIVOS,
  MOTIVO_ESCRITO,
  SITUACOES,
  faltaApoliceNova,
  faltaMotivo,
  situacaoDaRenovacao,
  terminou,
} from '../../carteira/situacaoDaRenovacao';
import { chaveDoSelo, tomDoSelo } from '../../carteira/tomDoSelo';
import {
  GRUPOS_DE_SEGUROS,
  GRUPO_EM_RENOVACAO,
  grupoConhecido,
  grupoTemporario,
  gruposDaBarra,
  seguroPertenceAoGrupo,
} from '../../fonte/gruposDeSeguros';
import {
  SELOS,
  estaValendo,
  porUrgencia,
  seloDoSeguro,
} from '../../fonte/selosDoSeguro';
import { aoMeioDia } from './apoio';

// As funções puras da renovação no funil (#2898): os ajustes, a situação da
// renovação e os selos, os grupos, o rodapé da gaveta, os números dos
// resultados, o arquivo do histórico e a apólice nova. O relógio é fixo:
// 12/11/2026, às 10h de quem roda o teste. Todos os dados são inventados.
const AGORA = new Date(2026, 10, 12, 10).getTime();
const terminaEm = (dias, resto = {}) => ({
  id: 1,
  termina: aoMeioDia(2026, 11, 12 + dias),
  canceladoEm: null,
  temPdf: false,
  pessoa: { id: 5, phone_number: '+5511900000001' },
  ...resto,
});
const ABERTA = {
  cardId: 88,
  funil: 'Renovação',
  etapa: 'A vencer',
  desfecho: null,
  cuida: 'Bruna Teixeirão',
};
const RENOVOU = { ...ABERTA, desfecho: 'renovou' };
const NAO_RENOVOU = { ...ABERTA, desfecho: 'nao_renovou' };
const emRenovacao = (dias = 20, resto = {}) =>
  terminaEm(dias, { renovacao: ABERTA, ...resto });
const renovado = (resto = {}) =>
  terminaEm(20, { renovacao: RENOVOU, renovadoEm: 1790000000, ...resto });
const perdido = (dias = -10, resto = {}) =>
  terminaEm(dias, { renovacao: NAO_RENOVOU, ...resto });

const FUNIS = [
  {
    id: 1,
    nome: 'Renovação',
    etapas: [
      { id: 11, nome: 'A vencer' },
      { id: 12, nome: 'Em conversa' },
    ],
  },
  { id: 2, nome: 'Vendas', etapas: [{ id: 21, nome: 'Novo contato' }] },
];

// A frase do catálogo de um idioma, pelo caminho com pontos.
const doCatalogo = (catalogo, chave) =>
  chave.split('.').reduce((no, parte) => no?.[parte], catalogo);
const nosDoisIdiomas = chave => {
  expect(doCatalogo(ptBR, chave)).toBeTruthy();
  expect(doCatalogo(en, chave)).toBeTruthy();
};
const daCarteira = chave => `RELACIONAMENTOS_CARTEIRA.${chave}`;

describe('ajustar renovações: os dias', () => {
  it.each([
    ['60', 60],
    [' 7 ', 7],
    ['1', 1],
    [45, 45],
  ])('%j vale como número de dias', (escrito, dias) => {
    expect(diasDigitados(escrito)).toBe(dias);
  });

  it.each(['0', '', '   ', '1e2', '12,5', '1.5', '-3', 'dez', null, undefined])(
    '%j não é um número de dias',
    escrito => {
      expect(diasDigitados(escrito)).toBeNull();
    }
  );

  it('os botões de menos e mais andam de um em um e não passam de 1', () => {
    expect(umDiaAMenos(60)).toBe(59);
    expect(umDiaAMenos(1)).toBe(1);
    expect(umDiaAMenos(null)).toBe(1);
    expect(umDiaAMais(60)).toBe(61);
    expect(umDiaAMais(null)).toBe(1);
  });

  it('conta quantos seguros entram com o número de dias escrito', () => {
    const vencimentos = [3, 20, 60, 61, 200];

    expect(quantosEntram(vencimentos, 60)).toBe(3);
    expect(quantosEntram(vencimentos, 1)).toBe(0);
    expect(quantosEntram(vencimentos, 365)).toBe(5);
  });

  it('sem número de dias, ou sem seguro, ninguém entra', () => {
    expect(quantosEntram([3, 20], null)).toBe(0);
    expect(quantosEntram([], 60)).toBe(0);
    expect(quantosEntram()).toBe(0);
  });
});

describe('ajustar renovações: o funil e a etapa', () => {
  it('a conta nasce sem funil, com 60 dias e mandando as mensagens', () => {
    expect(AJUSTES_PADRAO).toEqual({
      funilId: null,
      etapaId: null,
      dias: 60,
      mensagens: MENSAGENS.MANDAR,
    });
  });

  it('as etapas são as do funil escolhido', () => {
    expect(etapasDoFunil(FUNIS, 1).map(etapa => etapa.id)).toEqual([11, 12]);
    expect(etapasDoFunil(FUNIS, 99)).toEqual([]);
    expect(etapasDoFunil(FUNIS, null)).toEqual([]);
    expect(etapasDoFunil()).toEqual([]);
  });

  it('escolher o funil já escolhe a primeira etapa dele, sem mexer no que chegou', () => {
    const antes = { ...AJUSTES_PADRAO, funilId: 1, etapaId: 12 };
    const depois = comOFunil(antes, FUNIS, 2);

    expect(depois).toEqual({ ...antes, funilId: 2, etapaId: 21 });
    expect(antes).toEqual({ ...AJUSTES_PADRAO, funilId: 1, etapaId: 12 });
    expect(comOFunil(antes, FUNIS, 99).etapaId).toBeNull();
  });

  it('diz a escolha de hoje com os nomes que a corretora deu', () => {
    expect(ondeFicam(FUNIS, { funilId: 1, etapaId: 12 })).toEqual({
      funil: 'Renovação',
      etapa: 'Em conversa',
    });
  });

  it('sem escolha, ou com funil ou etapa que não existe mais, não há o que dizer', () => {
    expect(ondeFicam(FUNIS, AJUSTES_PADRAO)).toBeNull();
    expect(ondeFicam(FUNIS, { funilId: 99, etapaId: 11 })).toBeNull();
    expect(ondeFicam(FUNIS, { funilId: 1, etapaId: 21 })).toBeNull();
    expect(ondeFicam()).toBeNull();
  });

  it('o que falta para salvar, na ordem da tela', () => {
    const completos = { funilId: 1, etapaId: 11, dias: 60 };

    expect(faltaNosAjustes()).toBe(FALTAS.FUNIL);
    expect(faltaNosAjustes({ ...completos, funilId: null })).toBe(FALTAS.FUNIL);
    expect(faltaNosAjustes({ ...completos, etapaId: null })).toBe(FALTAS.ETAPA);
    expect(faltaNosAjustes({ ...completos, dias: null })).toBe(FALTAS.DIAS);
    expect(faltaNosAjustes(completos)).toBe('');
  });

  it('cada falta tem a frase dela nos dois idiomas', () => {
    Object.values(FALTAS).forEach(falta => {
      nosDoisIdiomas(daCarteira(`AJUSTES.FALTA.${falta}`));
    });
  });

  it('só as quatro escolhas contam como mudança', () => {
    const salvos = { funilId: 1, etapaId: 11, dias: 60, mensagens: 'mandar' };

    expect(ajustesMudaram(salvos, { ...salvos })).toBe(false);
    expect(ajustesMudaram(salvos, { ...salvos, outra: 'coisa' })).toBe(false);
    expect(ajustesMudaram(salvos, { ...salvos, dias: 45 })).toBe(true);
    expect(ajustesMudaram(salvos, { ...salvos, etapaId: 12 })).toBe(true);
    expect(
      ajustesMudaram(salvos, { ...salvos, mensagens: MENSAGENS.NAO_MANDAR })
    ).toBe(true);
  });

  it('as recusas dos ajustes têm frase nos dois idiomas', () => {
    ['funil_desconhecido', 'etapa_de_outro_funil', 'dias_invalidos'].forEach(
      codigo => {
        expect(CODIGOS_DE_RECUSA).toContain(codigo);
        nosDoisIdiomas(chaveDaRecusa(codigo, 'PADRAO'));
      }
    );
  });
});

describe('em que pé está a renovação', () => {
  it('seguro sem renovação não tem situação', () => {
    expect(situacaoDaRenovacao(terminaEm(20))).toBeNull();
    expect(situacaoDaRenovacao(null)).toBeNull();
  });

  it('aberta: diz o funil e a etapa, com os nomes da corretora', () => {
    expect(situacaoDaRenovacao(emRenovacao())).toEqual({
      id: SITUACOES.EM_ETAPA,
      funil: 'Renovação',
      etapa: 'A vencer',
    });
  });

  it('renovou: falta a apólice nova até ela ser guardada', () => {
    expect(situacaoDaRenovacao(renovado())).toEqual({
      id: SITUACOES.RENOVOU_FALTA,
    });
    expect(situacaoDaRenovacao(renovado({ apoliceNova: true }))).toEqual({
      id: SITUACOES.RENOVOU,
    });
    expect(faltaApoliceNova(renovado())).toBe(true);
    expect(faltaApoliceNova(renovado({ apoliceNova: true }))).toBe(false);
    expect(faltaApoliceNova(emRenovacao())).toBe(false);
  });

  it('não renovou: sem motivo, com motivo de um toque e com motivo escrito', () => {
    expect(situacaoDaRenovacao(perdido())).toEqual({
      id: SITUACOES.NAO_RENOVOU,
    });
    expect(situacaoDaRenovacao(perdido(-10, { motivo: 'achou_caro' }))).toEqual(
      { id: SITUACOES.NAO_RENOVOU_MOTIVO, motivo: 'achou_caro' }
    );
    expect(
      situacaoDaRenovacao(
        perdido(-10, { motivo: MOTIVO_ESCRITO, motivoEscrito: 'Mudou de país' })
      )
    ).toEqual({ id: SITUACOES.NAO_RENOVOU_ESCRITO, texto: 'Mudou de país' });
  });

  it('"outro" sem o texto continua sendo um motivo de um toque', () => {
    expect(
      situacaoDaRenovacao(perdido(-10, { motivo: MOTIVO_ESCRITO }))
    ).toEqual({ id: SITUACOES.NAO_RENOVOU_MOTIVO, motivo: MOTIVO_ESCRITO });
  });

  it('só quem não renovou e ficou sem motivo é convidado a dizer o motivo', () => {
    expect(faltaMotivo(perdido())).toBe(true);
    expect(faltaMotivo(perdido(-10, { motivo: 'nao_respondeu' }))).toBe(false);
    expect(faltaMotivo(renovado())).toBe(false);
    expect(faltaMotivo(emRenovacao())).toBe(false);
  });

  it('a renovação terminou quando renovou ou quando não renovou', () => {
    expect(terminou(renovado())).toBe(true);
    expect(terminou(perdido())).toBe(true);
    expect(terminou(emRenovacao())).toBe(false);
    expect(terminou(terminaEm(20))).toBe(false);
  });

  it('cada situação e cada motivo têm frase nos dois idiomas', () => {
    Object.values(SITUACOES).forEach(situacao => {
      nosDoisIdiomas(daCarteira(`RENOVACAO.SITUACAO.${situacao}`));
    });
    [...MOTIVOS, MOTIVO_ESCRITO].forEach(motivo => {
      const nome = motivo.toUpperCase();
      nosDoisIdiomas(daCarteira(`RENOVACAO.MOTIVO.NOME.${nome}`));
      nosDoisIdiomas(daCarteira(`RENOVACAO.MOTIVO.NA_FRASE.${nome}`));
    });
  });

  it('são quatro motivos de um toque, e "outro" é o que se escreve', () => {
    expect(MOTIVOS).toEqual([
      'achou_caro',
      'outra_corretora',
      'vendeu_o_bem',
      'nao_respondeu',
    ]);
    expect(MOTIVOS).not.toContain(MOTIVO_ESCRITO);
  });
});

describe('os selos da renovação', () => {
  it('com a renovação aberta e o seguro valendo, o selo é Em renovação', () => {
    expect(seloDoSeguro(emRenovacao(), AGORA)).toBe(SELOS.EM_RENOVACAO);
    expect(estaValendo(emRenovacao(), AGORA)).toBe(true);
  });

  it('quem renovou tem o selo Renovado, mesmo depois de terminar', () => {
    expect(seloDoSeguro(renovado(), AGORA)).toBe(SELOS.RENOVADO);
    expect(seloDoSeguro(terminaEm(-5, { renovadoEm: 1790000000 }), AGORA)).toBe(
      SELOS.RENOVADO
    );
    expect(estaValendo(renovado(), AGORA)).toBe(false);
  });

  it('cancelado ganha de renovado, e vencido ganha de em renovação', () => {
    expect(seloDoSeguro(renovado({ canceladoEm: 1 }), AGORA)).toBe(
      SELOS.CANCELADO
    );
    expect(seloDoSeguro(emRenovacao(-3), AGORA)).toBe(SELOS.VENCIDO);
  });

  it('quem não renovou e ainda vale continua Ativo', () => {
    expect(seloDoSeguro(perdido(12), AGORA)).toBe(SELOS.ATIVO);
  });

  it('o selo que o servidor manda vale mais que a conta daqui', () => {
    const doServidor = terminaEm(20, { selo: SELOS.EM_RENOVACAO, dias: 20 });

    expect(seloDoSeguro(doServidor, AGORA)).toBe(SELOS.EM_RENOVACAO);
  });

  it('Em renovação vai em azul e Renovado em verde, com nome nos dois idiomas', () => {
    expect(tomDoSelo(SELOS.EM_RENOVACAO)).toBe('azul');
    expect(tomDoSelo(SELOS.EM_RENOVACAO, 3)).toBe('azul');
    expect(tomDoSelo(SELOS.RENOVADO)).toBe('verde');
    nosDoisIdiomas(chaveDoSelo(SELOS.EM_RENOVACAO));
    nosDoisIdiomas(chaveDoSelo(SELOS.RENOVADO));
  });

  it('na ficha: vencido, em renovação, renovado, ativo e cancelado', () => {
    const seguros = [
      terminaEm(5, { id: 1, canceladoEm: 9 }),
      terminaEm(40, { id: 2 }),
      renovado({ id: 3 }),
      emRenovacao(20, { id: 4 }),
      terminaEm(-3, { id: 5 }),
    ];

    expect(porUrgencia(seguros, AGORA).map(s => s.id)).toEqual([5, 4, 3, 2, 1]);
  });

  it('o renovado diz quando renovou, na lista, na ficha e na gaveta', () => {
    expect(quandoDoSeguro(renovado(), AGORA)).toEqual({
      id: 'RENOVOU_EM',
      data: 1790000000,
    });
    [ptBR, en].forEach(catalogo => {
      const { QUANDO, GAVETA } = catalogo.RELACIONAMENTOS_CARTEIRA;
      expect(QUANDO.LISTA.RENOVOU_EM).toContain('{data}');
      expect(QUANDO.FICHA.RENOVOU_EM).toContain('{data}');
      expect(GAVETA.FRASE.RENOVOU_EM).toContain('{data}');
    });
  });
});

describe('os grupos da renovação', () => {
  it('"Em renovação" entra na barra depois dos grupos de vencimento', () => {
    expect(GRUPOS_DE_SEGUROS.map(grupo => grupo.id)).toEqual([
      'todos',
      'vence_7_dias',
      'vence_30_dias',
      'vence_90_dias',
      GRUPO_EM_RENOVACAO,
      'vencido',
      'sem_telefone',
    ]);
  });

  it('"Em renovação" é quem tem o selo: a renovação aberta e o seguro valendo', () => {
    const noGrupo = seguro =>
      seguroPertenceAoGrupo(seguro, GRUPO_EM_RENOVACAO, AGORA);

    expect(noGrupo(emRenovacao())).toBe(true);
    expect(noGrupo(terminaEm(20))).toBe(false);
    expect(noGrupo(emRenovacao(-3))).toBe(false);
    expect(noGrupo(renovado())).toBe(false);
    expect(noGrupo(emRenovacao(20, { canceladoEm: 1 }))).toBe(false);
  });

  it('o seguro em renovação continua nos grupos de vencimento, e o renovado sai', () => {
    expect(seguroPertenceAoGrupo(emRenovacao(), 'vence_30_dias', AGORA)).toBe(
      true
    );
    expect(seguroPertenceAoGrupo(renovado(), 'vence_30_dias', AGORA)).toBe(
      false
    );
  });

  it.each([
    [30, 30, 31],
    [90, 90, 91],
    [365, 365, 366],
  ])(
    '"Não renovaram" de %i dias: terminou há até %i dias, e há %i fica de fora',
    (periodo, dentro, fora) => {
      const grupo = grupoDosQueNaoRenovaram(periodo);

      expect(seguroPertenceAoGrupo(perdido(-1), grupo, AGORA)).toBe(true);
      expect(seguroPertenceAoGrupo(perdido(-dentro), grupo, AGORA)).toBe(true);
      expect(seguroPertenceAoGrupo(perdido(-fora), grupo, AGORA)).toBe(false);
    }
  );

  it('"Não renovaram" não conta quem ainda vale, quem renovou nem quem só venceu', () => {
    const grupo = grupoDosQueNaoRenovaram(30);

    expect(seguroPertenceAoGrupo(perdido(5), grupo, AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(perdido(0), grupo, AGORA)).toBe(false);
    expect(seguroPertenceAoGrupo(terminaEm(-5), grupo, AGORA)).toBe(false);
    expect(
      seguroPertenceAoGrupo(
        terminaEm(-5, { renovacao: RENOVOU, renovadoEm: 1 }),
        grupo,
        AGORA
      )
    ).toBe(false);
  });

  it('o endereço só pede grupo que existe', () => {
    expect(grupoConhecido(GRUPO_EM_RENOVACAO)).toBe(GRUPO_EM_RENOVACAO);
    expect(grupoConhecido('vencido')).toBe('vencido');
    expect(grupoConhecido('nao_renovaram_90')).toBe('nao_renovaram_90');
    expect(grupoConhecido('inventado')).toBe('');
    expect(grupoConhecido(undefined)).toBe('');
    expect(grupoConhecido(['vencido', 'todos'])).toBe('');
  });

  it('o grupo temporário só entra na barra quando é pedido, e no fim', () => {
    const deSempre = GRUPOS_DE_SEGUROS.map(grupo => grupo.id);

    expect(gruposDaBarra().map(grupo => grupo.id)).toEqual(deSempre);
    expect(gruposDaBarra('vencido').map(grupo => grupo.id)).toEqual(deSempre);
    expect(gruposDaBarra('nao_renovaram_365').map(grupo => grupo.id)).toEqual([
      ...deSempre,
      'nao_renovaram_365',
    ]);
    expect(grupoTemporario('vencido')).toBeNull();
    expect(grupoTemporario('nao_renovaram_30').id).toBe('nao_renovaram_30');
  });

  it('cada grupo temporário tem nome e explicação nos dois idiomas', () => {
    PERIODOS.forEach(dias => {
      const { nome, explicacao } = grupoTemporario(
        grupoDosQueNaoRenovaram(dias)
      );

      nosDoisIdiomas(nome);
      nosDoisIdiomas(explicacao);
    });
  });
});

describe('o rodapé da gaveta com a renovação', () => {
  const rodape = (seguro, opcoes) =>
    rodapeDoSeguro(seguro, { agora: AGORA, ...opcoes });

  it('aberta, com PDF: "Renovou" em azul, "Não renovou" ao lado e o resto no "⋯"', () => {
    expect(rodape(emRenovacao(20, { temPdf: true }))).toEqual({
      azul: DO_RODAPE.RENOVOU,
      secundario: DO_RODAPE.NAO_RENOVOU,
      menu: [
        DO_RODAPE.VER_PDF,
        DO_RODAPE.CORRIGIR,
        DO_RODAPE.GUARDAR_OUTRO_PDF,
        DO_RODAPE.APAGAR_PDF,
        DO_RODAPE.MARCAR_CANCELADO,
      ],
    });
  });

  it('aberta, sem PDF: guardar o PDF e corrigir ficam no "⋯"', () => {
    expect(rodape(emRenovacao()).menu).toEqual([
      DO_RODAPE.GUARDAR_PDF,
      DO_RODAPE.CORRIGIR,
      DO_RODAPE.MARCAR_CANCELADO,
    ]);
  });

  it('aberta e já vencida: ainda dá para dizer se renovou', () => {
    expect(rodape(emRenovacao(-3)).azul).toBe(DO_RODAPE.RENOVOU);
  });

  it('renovou: o azul é "Guardar a apólice nova", e o "⋯" desfaz', () => {
    expect(rodape(renovado())).toEqual({
      azul: DO_RODAPE.GUARDAR_APOLICE_NOVA,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [
        DO_RODAPE.GUARDAR_PDF,
        DO_RODAPE.DESFAZER_RENOVACAO,
        DO_RODAPE.MARCAR_CANCELADO,
      ],
    });
  });

  it('renovou e já tem a apólice nova: o rodapé volta ao de sempre, com o desfazer', () => {
    expect(rodape(renovado({ apoliceNova: true, temPdf: true }))).toEqual({
      azul: DO_RODAPE.VER_PDF,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [
        DO_RODAPE.GUARDAR_OUTRO_PDF,
        DO_RODAPE.APAGAR_PDF,
        DO_RODAPE.DESFAZER_RENOVACAO,
        DO_RODAPE.MARCAR_CANCELADO,
      ],
    });
  });

  it('não renovou: sem botão da renovação, e o "⋯" desfaz', () => {
    expect(rodape(perdido())).toEqual({
      azul: null,
      secundario: DO_RODAPE.CORRIGIR,
      menu: [
        DO_RODAPE.GUARDAR_PDF,
        DO_RODAPE.DESFAZER_RENOVACAO,
        DO_RODAPE.MARCAR_CANCELADO,
      ],
    });
  });

  it('seguro cancelado não oferece "Renovou" nem a apólice nova', () => {
    const aberta = rodape(emRenovacao(20, { canceladoEm: 1 }));
    const renovada = rodape(renovado({ canceladoEm: 1 }));

    expect(aberta.azul).toBeNull();
    expect(aberta.secundario).toBe(DO_RODAPE.CORRIGIR);
    expect(aberta.menu).toContain(DO_RODAPE.DESFAZER_CANCELAMENTO);
    expect(renovada.azul).toBeNull();
  });

  it('quem só pode ver não tem nada da renovação', () => {
    expect(
      rodape(emRenovacao(20, { temPdf: true }), { podeEditar: false })
    ).toEqual({ azul: DO_RODAPE.VER_PDF, secundario: null, menu: [] });
    expect(rodape(renovado(), { podeEditar: false })).toEqual({
      azul: null,
      secundario: null,
      menu: [],
    });
  });

  it('nada da renovação vem em vermelho, e tudo tem nome nos dois idiomas', () => {
    [
      DO_RODAPE.RENOVOU,
      DO_RODAPE.NAO_RENOVOU,
      DO_RODAPE.GUARDAR_APOLICE_NOVA,
      DO_RODAPE.DESFAZER_RENOVACAO,
    ].forEach(nome => {
      expect(DESTRUTIVOS).not.toContain(nome);
      nosDoisIdiomas(daCarteira(`GAVETA.RODAPE.${nome}`));
    });
  });
});

describe('os números dos resultados', () => {
  it('a largura da barra é a parte do total, de 0 a 100', () => {
    expect(porcentagem(7, 9)).toBe(78);
    expect(porcentagem(1, 3)).toBe(33);
    expect(porcentagem(4, 4)).toBe(100);
    expect(porcentagem(0, 5)).toBe(0);
    expect(porcentagem(3, 0)).toBe(0);
  });

  it('acha o período pelo número de dias', () => {
    const periodos = [{ dias: 30 }, { dias: 90 }];

    expect(periodoEscolhido(periodos, 90)).toBe(periodos[1]);
    expect(periodoEscolhido(periodos)).toBe(periodos[0]);
    expect(periodoEscolhido(periodos, 365)).toBeNull();
    expect(periodoEscolhido()).toBeNull();
  });

  it('só vira barra o motivo que alguém escolheu, do mais citado ao menos', () => {
    const motivos = [
      { motivo: 'achou_caro', quantos: 1 },
      { motivo: 'vendeu_o_bem', quantos: 0 },
      { motivo: 'outra_corretora', quantos: 4 },
    ];

    expect(motivosCitados(motivos)).toEqual([
      { motivo: 'outra_corretora', quantos: 4 },
      { motivo: 'achou_caro', quantos: 1 },
    ]);
    expect(motivos.map(({ motivo }) => motivo)).toEqual([
      'achou_caro',
      'vendeu_o_bem',
      'outra_corretora',
    ]);
    expect(motivosCitados()).toEqual([]);
  });

  it('"sem motivo" é quem não renovou e não teve motivo dito', () => {
    const motivos = [{ quantos: 2 }, { quantos: 1 }];

    expect(semMotivo({ naoRenovou: 5, motivos })).toBe(2);
    expect(semMotivo({ naoRenovou: 3, motivos })).toBe(0);
    expect(semMotivo({ naoRenovou: 2, motivos })).toBe(0);
    expect(semMotivo({ naoRenovou: 4 })).toBe(4);
    expect(semMotivo()).toBe(0);
  });

  it('o recorte só mostra a linha em que alguém venceu', () => {
    const recortes = {
      tipo: [
        { tipo: 'auto', venceram: 9, renovou: 7 },
        { tipo: 'vida', venceram: 0, renovou: 0 },
      ],
      seguradora: [{ nome: 'Horizonte Seguros', venceram: 0, renovou: 0 }],
      cuida: [{ nome: 'Bruna Teixeirão', venceram: 2, renovou: 2 }],
    };

    expect(linhasDoRecorte(recortes, 'tipo')).toEqual([
      { tipo: 'auto', venceram: 9, renovou: 7 },
    ]);
    expect(linhasDoRecorte(recortes, 'seguradora')).toEqual([]);
    expect(linhasDoRecorte(recortes, 'inventado')).toEqual([]);
    expect(linhasDoRecorte()).toEqual([]);
    expect(recortesComLinhas(recortes)).toEqual(['tipo', 'cuida']);
    expect(recortesComLinhas()).toEqual([]);
  });

  it('cada período tem a frase do topo, o nome e o grupo nos dois idiomas', () => {
    expect(PERIODOS).toEqual([30, 90, 365]);
    PERIODOS.forEach(dias => {
      nosDoisIdiomas(daCarteira(`RESULTADOS.HEROI.DIAS_${dias}`));
      nosDoisIdiomas(daCarteira(`RESULTADOS.PERIODO.DIAS_${dias}`));
      expect(grupoConhecido(grupoDosQueNaoRenovaram(dias))).toBe(
        `nao_renovaram_${dias}`
      );
    });
    RECORTES.forEach(recorte => {
      nosDoisIdiomas(daCarteira(`RESULTADOS.RECORTE.${recorte.toUpperCase()}`));
    });
  });
});

describe('o arquivo do histórico', () => {
  const MARCA_UTF8 = String.fromCharCode(0xfeff);

  it('uma linha por passo, cada valor entre aspas, separados por ponto e vírgula', () => {
    const csv = csvDoHistorico([
      ['Data', 'O que aconteceu'],
      ['12/11', 'Renovou.'],
    ]);

    expect(csv).toBe(
      `${MARCA_UTF8}"Data";"O que aconteceu"\r\n"12/11";"Renovou."`
    );
  });

  it('aspas de dentro dobram, e o ponto e vírgula de dentro não separa', () => {
    const csv = csvDoHistorico([['Disse "depois eu vejo"; não voltou']]);

    expect(csv).toBe(`${MARCA_UTF8}"Disse ""depois eu vejo""; não voltou"`);
  });

  it.each(['=1+1', '+5511900000001', '-3', '@alguem'])(
    'o valor %j ganha um apóstrofo para a planilha não ler como fórmula',
    valor => {
      expect(csvDoHistorico([[valor]])).toBe(`${MARCA_UTF8}"'${valor}"`);
    }
  );

  it('valor vazio vira um campo vazio', () => {
    expect(csvDoHistorico([['a', null, undefined, '']])).toBe(
      `${MARCA_UTF8}"a";"";"";""`
    );
  });

  it('o nome do arquivo não leva o número da apólice nem o nome de ninguém', () => {
    expect(nomeDoArquivoDoHistorico()).toBe('historico-do-seguro.csv');
  });

  it('baixa o arquivo pelo navegador e solta o endereço depois', () => {
    const criar = vi.fn(() => 'blob:historico');
    const soltar = vi.fn();
    const antes = {
      criar: URL.createObjectURL,
      soltar: URL.revokeObjectURL,
    };
    URL.createObjectURL = criar;
    URL.revokeObjectURL = soltar;
    const baixados = [];
    const clique = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(function guardar() {
        baixados.push(this.download);
      });

    baixarArquivo('historico-do-seguro.csv', 'conteúdo');

    expect(baixados).toEqual(['historico-do-seguro.csv']);
    expect(criar).toHaveBeenCalledTimes(1);
    expect(criar.mock.calls[0][0]).toBeInstanceOf(Blob);
    expect(soltar).toHaveBeenCalledWith('blob:historico');

    clique.mockRestore();
    URL.createObjectURL = antes.criar;
    URL.revokeObjectURL = antes.soltar;
  });
});

describe('os passos da renovação no histórico', () => {
  it('o passo com detalhe usa a frase que o escreve', () => {
    expect(
      fraseDoPasso({ tipo: 'nao_renovou', valores: { motivo: 'achou_caro' } })
    ).toEqual({
      chave: 'TIPOS_COM.NAO_RENOVOU',
      detalhe: DETALHES.MOTIVO,
      valor: 'achou_caro',
    });
    expect(
      fraseDoPasso({
        tipo: 'nao_renovou_outro',
        valores: { texto: 'Mudou de país' },
      })
    ).toEqual({
      chave: 'TIPOS_COM.NAO_RENOVOU_OUTRO',
      detalhe: DETALHES.TEXTO,
      valor: 'Mudou de país',
    });
    expect(
      fraseDoPasso({ tipo: 'apolice_nova', valores: { anterior: 'AT-000451' } })
    ).toEqual({
      chave: 'TIPOS_COM.APOLICE_NOVA',
      detalhe: DETALHES.ANTERIOR,
      valor: 'AT-000451',
    });
  });

  it('sem o detalhe, vale a frase curta: nunca uma frase com buraco', () => {
    const curta = tipo => ({
      chave: `TIPOS.${tipo.toUpperCase()}`,
      detalhe: null,
      valor: null,
    });

    expect(fraseDoPasso({ tipo: 'nao_renovou', valores: {} })).toEqual(
      curta('nao_renovou')
    );
    expect(fraseDoPasso({ tipo: 'nao_renovou_outro' })).toEqual(
      curta('nao_renovou_outro')
    );
    expect(fraseDoPasso({ tipo: 'apolice_nova', valores: null })).toEqual(
      curta('apolice_nova')
    );
  });

  it('os outros passos seguem com a frase do tipo', () => {
    expect(
      fraseDoPasso({ tipo: 'corrigido', valores: { campos: [] } })
    ).toEqual({ chave: 'TIPOS.CORRIGIDO', detalhe: null, valor: null });
    expect(fraseDoPasso({ tipo: 'card_nasceu' }).chave).toBe(
      'TIPOS.CARD_NASCEU'
    );
  });

  it('cada passo da renovação tem a frase curta e, quando há detalhe, a frase com ele', () => {
    [
      'CARD_NASCEU',
      'RENOVOU',
      'NAO_RENOVOU',
      'NAO_RENOVOU_OUTRO',
      'APOLICE_NOVA',
    ].forEach(tipo => {
      nosDoisIdiomas(daCarteira(`HISTORIA.TIPOS.${tipo}`));
    });
    [
      ['NAO_RENOVOU', '{motivo}'],
      ['NAO_RENOVOU_OUTRO', '{texto}'],
      ['APOLICE_NOVA', '{anterior}'],
    ].forEach(([tipo, lugar]) => {
      [ptBR, en].forEach(catalogo => {
        expect(
          catalogo.RELACIONAMENTOS_CARTEIRA.HISTORIA.TIPOS_COM[tipo]
        ).toContain(lugar);
      });
    });
  });
});

describe('a apólice nova', () => {
  const SEGURADORAS = ['Horizonte Seguros', 'Seguradora Atlântica'];
  const ANTERIOR = {
    tipo: 'auto',
    seguradora: 'Seguradora Atlântica',
    numero: 'AT-000451',
    comeca: aoMeioDia(2025, 11, 29),
    termina: aoMeioDia(2026, 11, 29),
    valor: 2760,
    bem: 'Carro hatch prata',
  };

  it('nasce com o que não muda e com a vigência seguinte; número e valor em branco', () => {
    expect(formularioDaApoliceNova(ANTERIOR, SEGURADORAS)).toEqual({
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      outraSeguradora: '',
      numero: '',
      comeca: '2026-11-29',
      termina: '2027-11-29',
      valor: '',
      bem: 'Carro hatch prata',
    });
  });

  it('a que terminava em 29 de fevereiro vale até 1º de março do ano seguinte', () => {
    const bissexto = { ...ANTERIOR, termina: aoMeioDia(2028, 2, 29) };

    expect(formularioDaApoliceNova(bissexto, SEGURADORAS)).toMatchObject({
      comeca: '2028-02-29',
      termina: '2029-03-01',
    });
  });

  it('sempre pede o número', () => {
    const formulario = formularioDaApoliceNova(ANTERIOR, SEGURADORAS);

    expect(faltasDaApoliceNova(formulario)).toEqual({ numero: 'NUMERO' });
    expect(faltasDaApoliceNova({ ...formulario, numero: 'AT-000987' })).toEqual(
      {}
    );
  });

  it('pede a data em que termina e recusa terminar antes de começar', () => {
    const formulario = {
      ...formularioDaApoliceNova(ANTERIOR, SEGURADORAS),
      numero: 'AT-000987',
    };

    expect(faltasDaApoliceNova({ ...formulario, termina: '' })).toEqual({
      termina: 'TERMINA',
    });
    expect(
      faltasDaApoliceNova({ ...formulario, termina: '2026-01-10' })
    ).toEqual({ termina: 'TERMINA_ANTES' });
  });

  it('manda tudo o que foi preenchido, e o que ficou em branco não vai', () => {
    const formulario = {
      ...formularioDaApoliceNova(ANTERIOR, SEGURADORAS),
      numero: ' AT-000987 ',
    };

    expect(dadosDaApoliceNova(formulario)).toEqual({
      tipo: 'auto',
      seguradora: 'Seguradora Atlântica',
      numero: 'AT-000987',
      comeca: aoMeioDia(2026, 11, 29),
      termina: aoMeioDia(2027, 11, 29),
      bem: 'Carro hatch prata',
    });
    expect(dadosDaApoliceNova({ ...formulario, valor: '2.900,00' }).valor).toBe(
      2900
    );
  });
});

describe('abrir o card da renovação no CRM', () => {
  it('leva ao quadro com o card aberto', () => {
    expect(destinoDoCard(88)).toEqual({
      name: 'crm_kanban_index',
      query: { card_id: '88' },
    });
  });

  it('na demonstração, ou sem card, abre só o quadro', () => {
    expect(destinoDoCard(88, true)).toEqual({
      name: 'crm_kanban_index',
      query: undefined,
    });
    expect(destinoDoCard(null)).toEqual({
      name: 'crm_kanban_index',
      query: undefined,
    });
  });
});
