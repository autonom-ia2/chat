import { situacaoDaRenovacao } from '../../carteira/situacaoDaRenovacao';

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
