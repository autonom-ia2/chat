import { COTACAO } from '../../carteira/cotacaoDoCard';
import { situacaoDaRenovacao } from '../../carteira/situacaoDaRenovacao';
import { tituloDaRenovacao } from '../../carteira/tituloDaRenovacao';

// As regras puras da renovação (#2897, onda 3).
describe('situacaoDaRenovacao: o que já foi feito e o que falta', () => {
  const proposta = { valor: 2980.8, variacao: 8 };

  it.each([
    [{ etapa: 'A vencer' }, 'NAO_COMECOU'],
    [{ etapa: 'A vencer', cotando: true }, 'COTANDO'],
    [{ etapa: 'Cotando' }, 'COTANDO'],
    [{ etapa: 'Cotando', proposta }, 'COTACAO_PRONTA'],
    [
      { etapa: 'Cotando', proposta: { ...proposta, enviadaEm: 1 } },
      'OPCOES_ENVIADAS',
    ],
    [{ etapa: 'Opções enviadas', proposta }, 'OPCOES_ENVIADAS'],
    [{ etapa: 'Negociação', proposta }, 'NEGOCIACAO'],
    [{ etapa: 'Renovado' }, 'RENOVOU'],
    [{ etapa: 'Cotando', desfecho: 'nao_renovou' }, 'NAO_RENOVOU'],
  ])('%o -> %s', (renovacao, esperado) => {
    expect(situacaoDaRenovacao(renovacao)).toEqual({ id: esperado });
  });

  it('etapa com o nome trocado por quem usa: repete o nome dela', () => {
    expect(situacaoDaRenovacao({ etapa: 'Ligar na sexta' })).toEqual({
      id: 'EM_ETAPA',
      etapa: 'Ligar na sexta',
    });
  });
});

describe('tituloDaRenovacao: a etapa e a cotação dizem a mesma coisa', () => {
  const noComeco = { etapa: 'A vencer' };

  it.each([
    [COTACAO.PARCIAL, 'PRECOS_CHEGANDO'],
    [COTACAO.FALTOU_PERGUNTADO, 'FALTA_UM_DADO'],
    [COTACAO.FALTOU_SEM_AGENTE, 'FALTA_UM_DADO'],
    [COTACAO.AGGER_FORA, 'COTACAO_PAROU'],
    [COTACAO.DEMOROU, 'COTACAO_PAROU'],
    [COTACAO.FALHOU, 'COTACAO_PAROU'],
    [COTACAO.NAO_COTA, 'FALTA_A_COTACAO'],
    [COTACAO.SEM_TELEFONE, 'PRONTA_FALTA_O_TELEFONE'],
    [COTACAO.NAO_QUER, 'PRONTA_ENVIE_NA_CONVERSA'],
  ])('na primeira etapa, cotação %s -> %s', (cotacao, esperado) => {
    expect(tituloDaRenovacao(noComeco, cotacao)).toEqual({ id: esperado });
  });

  it.each([
    [COTACAO.FALHOU, 'COTACAO_PAROU'],
    [COTACAO.PARCIAL, 'PRECOS_CHEGANDO'],
    [COTACAO.SEM_TELEFONE, 'PRONTA_FALTA_O_TELEFONE'],
  ])(
    'na etapa "Cotando" a cotação também fala: %s -> %s',
    (cotacao, esperado) => {
      expect(tituloDaRenovacao({ etapa: 'Cotando' }, cotacao)).toEqual({
        id: esperado,
      });
    }
  );

  it('o preço que chegou sem o PDF fala mais alto que "a cotação está pronta"', () => {
    const soOPreco = { ...noComeco, proposta: { valor: 100, semPdf: true } };

    expect(situacaoDaRenovacao(soOPreco)).toEqual({ id: 'COTACAO_PRONTA' });
    expect(tituloDaRenovacao(soOPreco, COTACAO.PRECO_SEM_PDF)).toEqual({
      id: 'PRECO_SEM_PDF',
    });
  });

  it.each([
    [noComeco, COTACAO.NAO_COMECOU, { id: 'NAO_COMECOU' }],
    [{ ...noComeco, cotando: true }, COTACAO.COTANDO, { id: 'COTANDO' }],
    [
      { ...noComeco, proposta: { valor: 100 } },
      COTACAO.PRONTA,
      { id: 'COTACAO_PRONTA' },
    ],
    // Depois que as opções saíram, vale o que a etapa já dizia.
    [
      { etapa: 'Opções enviadas', proposta: { valor: 100, enviadaEm: 1 } },
      COTACAO.ENVIADA_POR,
      { id: 'OPCOES_ENVIADAS' },
    ],
    [{ etapa: 'Negociação' }, COTACAO.SEM_TELEFONE, { id: 'NEGOCIACAO' }],
    [
      { etapa: 'Ligar na sexta' },
      COTACAO.NAO_COTA,
      { id: 'EM_ETAPA', etapa: 'Ligar na sexta' },
    ],
    [{ etapa: 'Renovado' }, null, { id: 'RENOVOU' }],
  ])(
    'os demais ficam como a situação diz: %j com %s',
    (renovacao, cotacao, esperado) => {
      expect(tituloDaRenovacao(renovacao, cotacao)).toEqual(esperado);
      expect(tituloDaRenovacao(renovacao, cotacao)).toEqual(
        situacaoDaRenovacao(renovacao)
      );
    }
  );
});
