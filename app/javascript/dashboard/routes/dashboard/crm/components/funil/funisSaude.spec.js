import ptBR from 'dashboard/i18n/locale/pt_BR';
import en from 'dashboard/i18n/locale/en';
import segurosPtBR from 'dashboard/i18n/pacotes/seguros/pt_BR.json';
import segurosEn from 'dashboard/i18n/pacotes/seguros/en.json';
import saudePtBR from 'dashboard/i18n/pacotes/seguros/saude_beneficios/pt_BR.json';
import saudeEn from 'dashboard/i18n/pacotes/seguros/saude_beneficios/en.json';
import { composeMessages } from 'dashboard/i18n/pacotesDoPainel';
import {
  MODELOS,
  categoriasDoModelo,
  modeloDoFunil,
  modelosDoTipo,
  usaNomeDoDesfecho,
} from './funil';

// #2083 — os funis da saúde: a "Venda de plano" é o próprio modelo Vendas com
// as etapas que o Rodrigo aprovou, e a Carteira é um modelo de Atender só da
// camada seguros/saude_beneficios.
const SAUDE = 'seguros.saude_beneficios';
const chaves = (tipo, pacote) =>
  modelosDoTipo(tipo, pacote).map(modelo => modelo.chave);
const carteira = MODELOS.find(modelo => modelo.chave === 'CARTEIRA');
const folhas = (no, prefixo = '') =>
  Object.entries(no).flatMap(([chave, valor]) =>
    typeof valor === 'object'
      ? folhas(valor, `${prefixo}${chave}.`)
      : [`${prefixo}${chave}`]
  );

describe('health templates', () => {
  it('health account: Sell keeps only Sales; Serve starts at the Portfolio', () => {
    expect(chaves('VENDER', SAUDE)).toEqual(['VENDAS']);
    expect(chaves('ATENDER', SAUDE)).toEqual([
      'CARTEIRA',
      'ATENDIMENTO',
      'POS_VENDA',
      'COBRANCA',
      'AGENDAMENTOS',
    ]);
  });

  it.each([null, '', 'seguros', 'seguros.corretora', 'seguros.insurtech'])(
    'account %j does not see the Portfolio',
    pacote => {
      expect(chaves('ATENDER', pacote)).not.toContain('CARTEIRA');
    }
  );

  it('Portfolio is Serve with both outcome names and no pause on the contract anniversary', () => {
    expect(carteira).toMatchObject({
      tipo: 'ATENDER',
      venda: false,
      sucesso: true,
      falha: true,
    });
    expect(categoriasDoModelo(carteira, SAUDE)).toEqual([
      'novo',
      'andamento',
      'andamento',
      'resolvido',
    ]);
  });

  it('a saved Portfolio keeps its template and uses its own outcome names', () => {
    const funil = { counts_as_sale: false, metadata: { template: 'CARTEIRA' } };
    expect(modeloDoFunil(funil).chave).toBe('CARTEIRA');
    expect(usaNomeDoDesfecho(funil)).toBe(true);
    expect(usaNomeDoDesfecho({ metadata: { template: 'VENDAS' } })).toBe(false);
  });
});

describe('health texts', () => {
  const composto = composeMessages(ptBR, [segurosPtBR, saudePtBR]);

  it('Sales is the "Venda de plano", ending in Implantado', () => {
    expect(composto.CRM_FUNIL.MODELOS.VENDAS).toEqual({
      NOME: 'Venda de plano',
      TEXTO: 'Da cotação até o plano ser implantado.',
      E1: 'Novo',
      E2: 'Cotação',
      E3: 'Proposta',
      E4: 'Na operadora',
      E5: 'Implantado',
    });
    expect(composto.CRM_CARD.DESFECHO.GANHOU).toBe('Implantado');
    expect(composto.CRM_CARD.DESFECHO.GANHOU_CONFIRMA_PADRAO).toBe(
      'Marcar como implantado'
    );
    expect(
      composeMessages(en, [segurosEn, saudeEn]).CRM_FUNIL.MODELOS.VENDAS.NOME
    ).toBe('Plan sale');
  });

  it('Portfolio ends in Renovado or Cancelado', () => {
    expect(composto.CRM_FUNIL.MODELOS.CARTEIRA).toMatchObject({
      NOME: 'Carteira',
      E1: 'Boas-vindas',
      E2: 'Em uso',
      E3: 'Aniversário do contrato',
      E4: 'Renovado',
      SUCESSO: 'Renovado',
      FALHA: 'Cancelado',
    });
  });

  // O vocabulário que o Rodrigo aprovou: nada de seguro de carro, apólice ou
  // "fechou o plano" no que a conta de saúde vê nas chaves que as camadas de
  // seguros trocam (o texto da saúde ou, sem ele, o da camada seguros).
  it.each([
    [
      'pt_BR',
      saudePtBR,
      ['segurad', 'apólice', 'sinistro', 'fechou o plano', 'beneficiári'],
    ],
    [
      'en',
      saudeEn,
      ['policyholder', 'policy', 'insured', 'claim', 'closed a plan'],
    ],
  ])(
    '%s health texts avoid the words of other lines',
    (_, pacote, palavras) => {
      const [base, seguros] =
        pacote === saudePtBR ? [ptBR, segurosPtBR] : [en, segurosEn];
      const visto = composeMessages(base, [seguros, pacote]);
      const caminhos = [...folhas(seguros), ...folhas(pacote)];
      caminhos.forEach(caminho => {
        const texto = caminho
          .split('.')
          .reduce((no, parte) => no?.[parte], visto)
          .toLowerCase();
        palavras.forEach(palavra =>
          expect(texto, caminho).not.toContain(palavra)
        );
      });
    }
  );
});
