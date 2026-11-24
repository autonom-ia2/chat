import {
  MINIMO_NO_RESTO,
  duasVersoesVazias,
  frasesDaAutomacao,
  frasesDoPlano,
  motivoDaSegunda,
  planoDoTeste,
  regraPadrao,
  segundaVersaoPronta,
  trocarCriterio,
} from '../duasVersoes';
import { CAMPAIGN_CHANNELS } from '../campaignChannels';

// #3099 — o tamanho do teste das duas versões e a frase do plano: a tela promete o que o servidor vai fazer.
describe('planoDoTeste', () => {
  it('testa com 20% do público quando isso passa do mínimo', () => {
    expect(planoDoTeste(1350)).toEqual({
      modo: 'teste',
      teste: 270,
      versao1: 135,
      versao2: 135,
      resto: 1080,
      pequeno: false,
      minimo: 200,
    });
  });

  it('usa o mínimo de 100 por versão em público médio', () => {
    const plano = planoDoTeste(450);
    expect(plano).toMatchObject({ modo: 'teste', teste: 200, resto: 250 });
    expect(plano.versao1 + plano.versao2).toBe(200);
  });

  it('com 70 e 30, a versão menor ainda recebe 100 pessoas', () => {
    const plano = planoDoTeste(1000, { divisao: 70 });
    expect(plano).toMatchObject({ modo: 'teste', teste: 334, resto: 666 });
    expect(plano.versao2).toBe(100);
    expect(plano.versao1).toBe(234);
  });

  it('manda as duas para todo mundo quando o resto ficaria pequeno', () => {
    const plano = planoDoTeste(200 + MINIMO_NO_RESTO - 1);
    expect(plano).toMatchObject({
      modo: 'todos',
      teste: 299,
      resto: 0,
      pequeno: false,
    });
    expect(plano.versao1 + plano.versao2).toBe(299);
  });

  it('avisa quando o público é menor que o mínimo do teste', () => {
    expect(planoDoTeste(120)).toMatchObject({
      modo: 'todos',
      versao1: 60,
      versao2: 60,
      pequeno: true,
    });
  });

  it('público vazio ou inválido não quebra', () => {
    expect(planoDoTeste(0)).toMatchObject({ modo: 'todos', teste: 0 });
    expect(planoDoTeste(undefined)).toMatchObject({ modo: 'todos', teste: 0 });
  });
});

describe('frasesDoPlano', () => {
  it('teste e resto, pelas respostas, com a regra do empate', () => {
    const chaves = frasesDoPlano(planoDoTeste(1350), regraPadrao()).map(
      frase => frase.chave
    );
    expect(chaves).toEqual(['TESTE', 'DEPOIS_RESPOSTAS', 'EMPATE']);
  });

  it('eu escolho não fala de empate', () => {
    const regra = { ...regraPadrao(), criterio: 'eu_escolho' };
    const frases = frasesDoPlano(planoDoTeste(1350), regra);
    expect(frases.map(frase => frase.chave)).toEqual([
      'TESTE',
      'DEPOIS_EU_ESCOLHO',
    ]);
    expect(frases[1].params).toEqual({ horas: 4, resto: 1080 });
  });

  it('público pequeno: todos, e o aviso de sorte', () => {
    const chaves = frasesDoPlano(planoDoTeste(120), regraPadrao()).map(
      frase => frase.chave
    );
    expect(chaves).toEqual(['TODOS', 'PEQUENO']);
  });

  it('automação fala de cada pessoa que passa e da divisão', () => {
    const regra = { criterio: 'compras', divisao: 70, espera: 24 };
    expect(frasesDaAutomacao(regra).map(frase => frase.chave)).toEqual([
      'AUTOMACAO_MAIS_NA_1',
      'AUTOMACAO_DEPOIS_COMPRAS',
      'EMPATE',
    ]);
  });
});

describe('trocarCriterio', () => {
  it('leva a espera para o padrão do critério novo', () => {
    expect(trocarCriterio(regraPadrao(), 'compras').espera).toBe(24);
  });

  it('mantém a espera que a pessoa mudou à mão', () => {
    const regra = { ...regraPadrao(), espera: 2 };
    expect(trocarCriterio(regra, 'compras')).toMatchObject({
      criterio: 'compras',
      espera: 2,
    });
  });
});

describe('motivoDaSegunda', () => {
  const ligado = patch => ({ ...duasVersoesVazias(), ligado: true, ...patch });

  it('desligado nunca trava', () => {
    expect(motivoDaSegunda(CAMPAIGN_CHANNELS.SMS, duasVersoesVazias())).toBe(
      null
    );
  });

  it('texto vazio ou igual à versão 1', () => {
    const primeira = { texto: 'Oi, {{contact.first_name}}!' };
    expect(
      motivoDaSegunda(CAMPAIGN_CHANNELS.SMS, ligado({ texto: '  ' }), primeira)
    ).toBe('VAZIA');
    expect(
      motivoDaSegunda(
        CAMPAIGN_CHANNELS.WHATSAPP_API,
        ligado({ texto: ' Oi, {{contact.first_name}}! ' }),
        primeira
      )
    ).toBe('IGUAL');
    expect(
      segundaVersaoPronta(
        CAMPAIGN_CHANNELS.SMS,
        ligado({ texto: 'Olá de novo' }),
        primeira
      )
    ).toBe(true);
  });

  it('no WhatsApp Oficial compara o modelo; no e-mail, o assunto', () => {
    expect(
      motivoDaSegunda(
        CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
        ligado({ templateId: 'promo_a' }),
        { templateId: 'promo_a' }
      )
    ).toBe('IGUAL');
    expect(
      motivoDaSegunda(CAMPAIGN_CHANNELS.EMAIL, ligado({ assunto: '' }), {
        assunto: 'Oferta',
      })
    ).toBe('VAZIA');
    expect(
      motivoDaSegunda(CAMPAIGN_CHANNELS.EMAIL, ligado({ assunto: 'Outra' }), {
        assunto: 'Oferta',
      })
    ).toBe(null);
  });
});
