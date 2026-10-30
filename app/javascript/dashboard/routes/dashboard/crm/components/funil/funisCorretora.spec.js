import ptBR from 'dashboard/i18n/locale/pt_BR';
import en from 'dashboard/i18n/locale/en';
import segurosPtBR from 'dashboard/i18n/pacotes/seguros/pt_BR.json';
import corretoraPtBR from 'dashboard/i18n/pacotes/seguros/corretora/pt_BR.json';
import corretoraEn from 'dashboard/i18n/pacotes/seguros/corretora/en.json';
import segurosEn from 'dashboard/i18n/pacotes/seguros/en.json';
import { composeMessages } from 'dashboard/i18n/pacotesDoPainel';
import { MODELOS, modeloDoFunil, modelosDoTipo } from './funil';

// #1802 — os funis da corretora: modelos a mais só para a camada
// seguros/corretora, e a "Venda de seguro" como o próprio modelo Vendas com a
// fala do corretor. Conta geral (e seguradora e insurtech) fica como hoje; a
// saúde tem os dela (funisSaude.spec.js).
const chaves = (tipo, pacote) =>
  modelosDoTipo(tipo, pacote).map(modelo => modelo.chave);

const HOJE = {
  VENDER: ['VENDAS'],
  ATENDER: ['ATENDIMENTO', 'POS_VENDA', 'COBRANCA', 'AGENDAMENTOS'],
};

describe('modelosDoTipo by account layer', () => {
  it('broker account sees Renewal next to Sales, and Claim and Endorsement first in Serve', () => {
    expect(chaves('VENDER', 'seguros.corretora')).toEqual([
      'VENDAS',
      'RENOVACAO',
    ]);
    expect(chaves('ATENDER', 'seguros.corretora')).toEqual([
      'SINISTRO',
      'ENDOSSO',
      ...HOJE.ATENDER,
    ]);
  });

  it.each([null, undefined, '', 'seguros', 'seguros.insurtech'])(
    'account %j sees exactly the list of today',
    pacote => {
      expect(chaves('VENDER', pacote)).toEqual(HOJE.VENDER);
      expect(chaves('ATENDER', pacote)).toEqual(HOJE.ATENDER);
    }
  );

  it('a saved pipeline keeps its broker template, and an old one falls back to a template for everyone', () => {
    expect(
      modeloDoFunil({
        counts_as_sale: true,
        metadata: { template: 'RENOVACAO' },
      }).chave
    ).toBe('RENOVACAO');
    expect(
      modeloDoFunil({
        counts_as_sale: false,
        metadata: { template: 'SINISTRO' },
      }).chave
    ).toBe('SINISTRO');
    expect(modeloDoFunil({ counts_as_sale: false }).chave).toBe('ATENDIMENTO');
    expect(modeloDoFunil({ counts_as_sale: true }).chave).toBe('VENDAS');
  });

  it('Renewal is Sell with both outcomes; Claim and Endorsement are Serve, positional categories', () => {
    const modelo = chave => MODELOS.find(item => item.chave === chave);
    expect(modelo('RENOVACAO')).toMatchObject({
      tipo: 'VENDER',
      venda: true,
      sucesso: true,
      falha: true,
    });
    ['SINISTRO', 'ENDOSSO'].forEach(chave => {
      expect(modelo(chave)).toMatchObject({
        tipo: 'ATENDER',
        venda: false,
        sucesso: true,
        categorias: ['novo', 'andamento', 'espera', 'resolvido'],
      });
      expect(modelo(chave).ideias).toHaveLength(3);
    });
  });
});

describe('texts of the templates', () => {
  const vendasDe = catalogo => catalogo.CRM_FUNIL.MODELOS.VENDAS;
  const motivosDe = catalogo => catalogo.CRM_CARD.DESFECHO.MOTIVO;

  it('general account keeps the Sales texts and the quick reasons of today', () => {
    [composeMessages(ptBR, []), composeMessages(ptBR, [segurosPtBR])]
      .map(vendasDe)
      .forEach(vendas =>
        expect(vendas).toEqual({
          NOME: 'Vendas',
          TEXTO: 'Do primeiro contato até fechar a venda.',
          E1: 'Novo contato',
          E2: 'Em conversa',
          E3: 'Proposta enviada',
          E4: 'Negociação',
          E5: 'Fechado',
        })
      );
    expect(motivosDe(composeMessages(ptBR, [segurosPtBR]))).toEqual({
      PRECO: 'Achou caro',
      SUMIU: 'Parou de responder',
      OUTRO_LUGAR: 'Fechou com outro',
      NAO_ERA_HORA: 'Não era a hora',
    });
    expect(vendasDe(composeMessages(en, [])).NOME).toBe('Sales');
  });

  it('broker account sees Sales as "Venda de seguro", with short stages and its reasons', () => {
    const composto = composeMessages(ptBR, [segurosPtBR, corretoraPtBR]);
    expect(vendasDe(composto)).toEqual({
      NOME: 'Venda de seguro',
      TEXTO: 'Da cotação até o seguro fechar.',
      E1: 'Novo contato',
      E2: 'Cotando',
      E3: 'Opções enviadas',
      E4: 'Negociação',
      E5: 'Fechado',
    });
    expect(Object.values(motivosDe(composto))).toEqual([
      'Achou caro',
      'Parou de responder',
      'Fechou com outra corretora',
      'A seguradora recusou',
    ]);
    expect(composto.CRM_FUNIL.SOBRE.IDEIAS.PRECO).toBe('pede uma cotação');
    expect(vendasDe(composeMessages(en, [segurosEn, corretoraEn])).NOME).toBe(
      'Insurance sale'
    );
  });

  // Nome de etapa curto: até 3 palavras em português (o maior de hoje é
  // "Esperando o cliente"); o inglês só precisa existir.
  it.each([
    ['pt_BR', ptBR, 3],
    ['en', en, Infinity],
  ])(
    '%s has name, text, every stage, outcomes and ideas of every template',
    (_, catalogo, palavras) => {
      const { MODELOS: textos, SOBRE } = catalogo.CRM_FUNIL;
      MODELOS.forEach(modelo => {
        const texto = textos[modelo.chave];
        expect(texto.NOME).toBeTruthy();
        expect(texto.TEXTO).toBeTruthy();
        modelo.etapas.forEach(chave => {
          const nome = texto[chave.split('.').at(-1)];
          expect(nome).toBeTruthy();
          expect(nome.split(' ').length).toBeLessThanOrEqual(palavras);
        });
        if (modelo.sucesso) expect(texto.SUCESSO).toBeTruthy();
        if (modelo.falha) expect(texto.FALHA).toBeTruthy();
        modelo.ideias.forEach(ideia =>
          expect(SOBRE.IDEIAS[ideia]).toBeTruthy()
        );
      });
    }
  );
});
