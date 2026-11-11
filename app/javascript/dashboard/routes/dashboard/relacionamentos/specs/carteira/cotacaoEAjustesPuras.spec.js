import {
  AJUSTES_PADRAO,
  FALTAS,
  ajustesMudaram,
  comOFunil,
  diasDigitados,
  faltaEmOndeFicam,
  quantosEntram,
  umDiaAMais,
  umDiaAMenos,
} from '../../carteira/ajustesDaRenovacao';
import {
  COTACAO,
  FIM,
  contarRespostas,
  cotacaoDoCard,
  esperaEnvio,
  fimDaRenovacao,
} from '../../carteira/cotacaoDoCard';
import {
  grupoDosQueNaoRenovaram,
  periodoEscolhido,
  porcentagem,
} from '../../carteira/resultados';
import {
  grupoConhecido,
  grupoTemporario,
  gruposDeSeguros,
} from '../../fonte/gruposDeSeguros';
import { casoPedido, cotacaoDesligada } from '../../fonte/modoCarteira';

// As regras puras da onda 3 (#2897): a cotação dentro da renovação, os ajustes
// e os resultados.
const pessoa = { phone_number: '+55 11 90000-0001', opted_out_at: null };
const proposta = { valor: 100, variacao: 5 };
const seguro = (renovacao, quem = pessoa) => ({ renovacao, pessoa: quem });

describe('cotacaoDoCard: um estado de cada vez', () => {
  it.each([
    [{ etapa: 'A vencer' }, true, COTACAO.NAO_COMECOU],
    [{ etapa: 'A vencer' }, false, COTACAO.NAO_COTA],
    [{ etapa: 'Cotando', cotando: true }, true, COTACAO.COTANDO],
    [
      { etapa: 'A vencer', faltou: 'nascimento', perguntou: 'Nina' },
      true,
      COTACAO.FALTOU_PERGUNTADO,
    ],
    [
      { etapa: 'A vencer', faltou: 'nascimento', perguntou: null },
      true,
      COTACAO.FALTOU_SEM_AGENTE,
    ],
    [{ etapa: 'A vencer', parou: 'agger_fora' }, true, COTACAO.AGGER_FORA],
    [{ etapa: 'A vencer', parou: 'demorou' }, true, COTACAO.DEMOROU],
    [{ etapa: 'A vencer', parou: 'falhou' }, true, COTACAO.FALHOU],
    [{ etapa: 'A vencer', respostas: [] }, true, COTACAO.PARCIAL],
    [{ etapa: 'Cotando', proposta }, true, COTACAO.PRONTA],
    [
      { etapa: 'Cotando', proposta: { ...proposta, semPdf: true } },
      true,
      COTACAO.PRECO_SEM_PDF,
    ],
    [
      {
        etapa: 'Opções enviadas',
        proposta: { ...proposta, enviadaEm: 1, enviadaPor: 'Bia' },
      },
      true,
      COTACAO.ENVIADA_POR,
    ],
    [
      {
        etapa: 'Opções enviadas',
        proposta: { ...proposta, enviadaEm: 1, enviadaPor: { papel: 'voce' } },
      },
      true,
      COTACAO.ENVIADA_POR_VOCE,
    ],
    [
      {
        etapa: 'Opções enviadas',
        proposta: { ...proposta, enviadaEm: 1, enviadaSozinha: true },
      },
      true,
      COTACAO.ENVIADA_SOZINHA,
    ],
  ])('%j (cota sozinha: %s) -> %s', (renovacao, cotaSozinha, esperado) => {
    expect(cotacaoDoCard(seguro(renovacao), { cotaSozinha })).toBe(esperado);
  });

  it('sem telefone e "não quer mensagens" só falam quando há o que enviar; antes disso a cotação segue à vista', () => {
    const semFone = { ...pessoa, phone_number: null };
    const recusou = { ...pessoa, opted_out_at: 123 };
    const cotandoAinda = { etapa: 'Cotando', cotando: true };
    const semNada = { etapa: 'A vencer' };

    expect(cotacaoDoCard(seguro(cotandoAinda, semFone))).toBe(COTACAO.COTANDO);
    expect(cotacaoDoCard(seguro(cotandoAinda, recusou))).toBe(COTACAO.COTANDO);
    expect(cotacaoDoCard(seguro(semNada, semFone), { cotaSozinha: true })).toBe(
      COTACAO.NAO_COMECOU
    );
    expect(cotacaoDoCard(seguro(semNada, recusou))).toBe(COTACAO.NAO_COTA);
  });

  it('com a proposta pronta, sem telefone e "não quer mensagens" dizem o que impede de chegar', () => {
    const semTelefone = { ...pessoa, phone_number: null };
    const naoQuer = { ...pessoa, opted_out_at: 123 };
    const pronta = { etapa: 'Cotando', proposta };
    const enviada = {
      etapa: 'Opções enviadas',
      proposta: { ...proposta, enviadaEm: 1, enviadaPor: 'Bia' },
    };

    expect(cotacaoDoCard(seguro(pronta, semTelefone))).toBe(
      COTACAO.SEM_TELEFONE
    );
    expect(cotacaoDoCard(seguro(pronta, naoQuer))).toBe(COTACAO.NAO_QUER);
    expect(esperaEnvio(seguro(pronta, semTelefone))).toBe(false);
    expect(esperaEnvio(seguro(pronta))).toBe(true);
    // Só o preço, sem o PDF: dá para enviar o preço.
    const soOPreco = { ...pronta, proposta: { ...proposta, semPdf: true } };
    expect(esperaEnvio(seguro(soOPreco))).toBe(true);
    expect(esperaEnvio(seguro(soOPreco, semTelefone))).toBe(false);
    expect(esperaEnvio(seguro({ etapa: 'Cotando', cotando: true }))).toBe(
      false
    );
    // O que já saiu continua dito como saiu.
    expect(cotacaoDoCard(seguro(enviada, semTelefone))).toBe(
      COTACAO.ENVIADA_POR
    );
  });

  it('renovação terminada (ou seguro sem renovação) não tem cotação a mostrar', () => {
    expect(cotacaoDoCard(seguro(null))).toBeNull();
    expect(cotacaoDoCard(seguro({ etapa: 'Renovado' }))).toBeNull();
    expect(
      cotacaoDoCard(seguro({ etapa: 'Cotando', desfecho: 'nao_renovou' }))
    ).toBeNull();
    expect(fimDaRenovacao({ etapa: 'Renovado' })).toBe(FIM.RENOVOU);
    expect(fimDaRenovacao({ etapa: 'Cotando', desfecho: 'nao_renovou' })).toBe(
      FIM.NAO_RENOVOU
    );
    expect(fimDaRenovacao({ etapa: 'Cotando' })).toBe('');
  });

  it('conta quem já deu preço e quem ainda não respondeu', () => {
    expect(
      contarRespostas([{ valor: 1 }, { valor: 2 }, { valor: null }])
    ).toEqual({ deram: 2, faltam: 1 });
  });
});

describe('ajustes da renovação', () => {
  it('todo ajuste já nasce respondido', () => {
    expect(AJUSTES_PADRAO).toMatchObject({
      onde: 'criar',
      dias: 60,
      mensagens: 'mandar',
      algoMudou: 'perguntar',
      quemCota: 'robo',
      comoEnvia: 'confere',
      quemResponde: 'agente',
      palavras: 'confiro',
    });
    expect(faltaEmOndeFicam(AJUSTES_PADRAO)).toBe('');
  });

  it('os dias: inteiro a partir de 1; menos e mais não saem disso', () => {
    expect(['60', ' 7 ', '1'].map(diasDigitados)).toEqual([60, 7, 1]);
    expect(['0', '-3', '2,5', 'dez', ''].map(diasDigitados)).toEqual([
      null,
      null,
      null,
      null,
      null,
    ]);
    expect([umDiaAMenos(60), umDiaAMenos(1), umDiaAMenos(null)]).toEqual([
      59, 1, 1,
    ]);
    expect([umDiaAMais(60), umDiaAMais(null)]).toEqual([61, 1]);
  });

  it('quantos seguros entram com N dias', () => {
    const vencimentos = [0, 3, 30, 31, 60, 61, -2];
    expect(quantosEntram(vencimentos, 30)).toBe(3);
    expect(quantosEntram(vencimentos, 60)).toBe(5);
    expect(quantosEntram(vencimentos, null)).toBe(0);
  });

  it('diz o que falta em "onde ficam": a escolha, o funil ou os dias', () => {
    expect(faltaEmOndeFicam({ onde: '', dias: 60 })).toBe(FALTAS.ONDE);
    expect(faltaEmOndeFicam({ onde: 'usar', funil: '', dias: 60 })).toBe(
      FALTAS.FUNIL
    );
    expect(faltaEmOndeFicam({ onde: 'criar', dias: null })).toBe(FALTAS.DIAS);
    expect(faltaEmOndeFicam({ onde: 'usar', funil: 'Vendas', dias: 30 })).toBe(
      ''
    );
  });

  it('escolher o funil já escolhe a primeira etapa dele; e sabe quando algo mudou', () => {
    const funis = [{ nome: 'Vendas', etapas: ['Novo contato', 'Proposta'] }];
    expect(comOFunil(AJUSTES_PADRAO, funis, 'Vendas')).toMatchObject({
      funil: 'Vendas',
      etapa: 'Novo contato',
    });
    expect(ajustesMudaram(AJUSTES_PADRAO, { ...AJUSTES_PADRAO })).toBe(false);
    expect(
      ajustesMudaram(AJUSTES_PADRAO, { ...AJUSTES_PADRAO, dias: 45 })
    ).toBe(true);
  });
});

describe('resultados e o grupo temporário "Não renovaram"', () => {
  it('a barra e o período', () => {
    expect([porcentagem(7, 9), porcentagem(0, 0), porcentagem(2, 2)]).toEqual([
      78, 0, 100,
    ]);
    const periodos = [{ dias: 30 }, { dias: 90 }];
    expect(periodoEscolhido(periodos, 90)).toEqual({ dias: 90 });
    expect(periodoEscolhido(periodos, 7)).toBeNull();
  });

  it('o grupo só aparece quando pedido, e o endereço só aceita grupo que existe', () => {
    const id = grupoDosQueNaoRenovaram(30);
    expect(id).toBe('nao_renovaram_30');
    expect(gruposDeSeguros().map(g => g.id)).not.toContain(id);
    expect(
      gruposDeSeguros({ temporario: id })
        .map(g => g.id)
        .pop()
    ).toBe(id);
    expect(grupoTemporario(id).nome).toBe(
      'RELACIONAMENTOS_CARTEIRA.GRUPOS.NAO_RENOVARAM_30.NOME'
    );
    expect(grupoTemporario('vencido')).toBeNull();
    expect(
      ['vence_30_dias', id, 'inventado', undefined].map(grupoConhecido)
    ).toEqual(['vence_30_dias', id, '', '']);
  });

  it('os casos e a chave da cotação só valem na demonstração (desenvolvimento)', () => {
    expect(casoPedido({ caso: 'cotacao_parcial' }, true)).toBe(
      'cotacao_parcial'
    );
    expect(casoPedido({ caso: 'cotacao_parcial' }, false)).toBeNull();
    expect(cotacaoDesligada({ cotacao: 'desligada' }, true)).toBe(true);
    expect(cotacaoDesligada({ cotacao: 'desligada' }, false)).toBe(false);
    expect(cotacaoDesligada({}, true)).toBe(false);
  });
});
