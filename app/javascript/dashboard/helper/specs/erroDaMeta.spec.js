import {
  erroDaMeta,
  codigoDoErro,
  CODIGOS_CONHECIDOS,
  CHAVES,
} from '../erroDaMeta';
import en from 'dashboard/i18n/locale/en/erroDaMeta.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/erroDaMeta.json';

describe('erroDaMeta', () => {
  it('lê o código no formato "N: título"', () => {
    const texto = '131042: Business eligibility payment issue';

    expect(erroDaMeta(texto, true)).toEqual({
      chave: 'ERRO_DA_META.SEM_PAGAMENTO',
      detalhe: texto,
      podeReenviar: true,
    });
  });

  it('lê o código no formato "(#N) mensagem"', () => {
    const texto = '(#132001) Template name does not exist in the translation';

    expect(erroDaMeta(texto, true).chave).toBe(
      'ERRO_DA_META.MODELO_NAO_EXISTE'
    );
    expect(erroDaMeta(texto, true).detalhe).toBe(texto);
  });

  it('368 e 131031 usam a mesma frase', () => {
    expect(erroDaMeta('368: Temporarily blocked', true).chave).toBe(
      'ERRO_DA_META.CONTA_BLOQUEADA'
    );
    expect(erroDaMeta('131031: Account has been locked', true).chave).toBe(
      'ERRO_DA_META.CONTA_BLOQUEADA'
    );
  });

  it('texto sem código fica como hoje', () => {
    const texto = 'O WhatsApp API não confirmou o envio. Confira no celular.';

    expect(erroDaMeta(texto, true)).toEqual({
      chave: null,
      detalhe: texto,
      podeReenviar: true,
    });
  });

  it('texto com ":" mas sem número fica como hoje', () => {
    expect(erroDaMeta('Fora da janela: o cliente sumiu', true).chave).toBe(
      null
    );
    expect(erroDaMeta('13a42: quase número', true).chave).toBe(null);
    expect(erroDaMeta('(#abc) sem número', true).chave).toBe(null);
    expect(erroDaMeta('(#131042 sem fechar', true).chave).toBe(null);
  });

  it('código que a tabela não conhece vira a frase genérica', () => {
    expect(erroDaMeta('131999: Something went wrong', true)).toEqual({
      chave: 'ERRO_DA_META.DESCONHECIDO',
      detalhe: '131999: Something went wrong',
      podeReenviar: true,
    });
  });

  it('caixa que não é WhatsApp fica como hoje, mesmo com código', () => {
    expect(erroDaMeta('131042: Business eligibility', false)).toEqual({
      chave: null,
      detalhe: '131042: Business eligibility',
      podeReenviar: true,
    });
  });

  it('texto vazio ou ausente não quebra', () => {
    expect(erroDaMeta('', true)).toEqual({
      chave: null,
      detalhe: '',
      podeReenviar: true,
    });
    expect(erroDaMeta(undefined, true).chave).toBe(null);
    expect(codigoDoErro(null)).toBe(null);
  });

  it('esconde o reenvio só em 131047, 131050 e 132016', () => {
    const semReenvio = CODIGOS_CONHECIDOS.filter(
      codigo => !erroDaMeta(`${codigo}: x`, true).podeReenviar
    );

    expect(semReenvio.sort()).toEqual(['131047', '131050', '132016']);
    expect(erroDaMeta('(#131047) Re-engagement', true).podeReenviar).toBe(
      false
    );
  });

  it('a tabela tem os 20 códigos aprovados', () => {
    expect([...CODIGOS_CONHECIDOS].sort()).toEqual(
      [
        '131042',
        '131047',
        '131026',
        '131049',
        '131050',
        '131051',
        '131053',
        '130472',
        '368',
        '131031',
        '131048',
        '131056',
        '190',
        '132000',
        '132001',
        '132005',
        '132007',
        '132012',
        '132015',
        '132016',
      ].sort()
    );
  });

  it.each([
    ['en', en],
    ['pt_BR', ptBR],
  ])('todo código tem frase e o que fazer em %s', (_locale, catalogo) => {
    const textos = catalogo.ERRO_DA_META;

    CODIGOS_CONHECIDOS.forEach(codigo => {
      const nome = erroDaMeta(`${codigo}: x`, true).chave.split('.')[1];
      expect(textos[nome].O_QUE).toBeTruthy();
      expect(textos[nome].FAZER).toBeTruthy();
    });
    CHAVES.forEach(nome => {
      expect(Object.keys(textos[nome]).sort()).toEqual(['FAZER', 'O_QUE']);
    });
    expect(textos.NAO_SAIU).toBeTruthy();
    expect(textos.O_QUE_FAZER).toBeTruthy();
    expect(textos.DETALHE).toBeTruthy();
  });
});
