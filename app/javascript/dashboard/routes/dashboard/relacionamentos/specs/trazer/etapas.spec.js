import {
  ETAPAS,
  EVENTOS,
  estadoInicial,
  etapaDoTopo,
  proximo,
} from '../../trazer/etapas';

// A máquina de etapas de "Trazer minha lista" (#2894): funções puras.
const passa = (estado, ...tipos) =>
  tipos.reduce((atual, tipo) => proximo(atual, { tipo }), estado);
const leu = (estado, perguntas) =>
  proximo(estado, { tipo: EVENTOS.LEU, perguntas });

describe('etapas: ida', () => {
  it('começa em enviar', () => {
    expect(estadoInicial().etapa).toBe(ETAPAS.ENVIAR);
  });

  it('vai direto para conferir quando a leitura não tem pergunta', () => {
    expect(leu(estadoInicial(), 0).etapa).toBe(ETAPAS.CONFERIR);
  });

  it('vai para a primeira pergunta quando a leitura pede', () => {
    const estado = leu(estadoInicial(), 2);
    expect(estado).toMatchObject({
      etapa: ETAPAS.PERGUNTAS,
      pergunta: 0,
      totalDePerguntas: 2,
    });
  });

  it('anda uma pergunta por vez e chega em conferir depois da última', () => {
    const segunda = passa(leu(estadoInicial(), 2), EVENTOS.CONTINUAR);
    expect(segunda).toMatchObject({ etapa: ETAPAS.PERGUNTAS, pergunta: 1 });
    expect(passa(segunda, EVENTOS.CONTINUAR).etapa).toBe(ETAPAS.CONFERIR);
  });

  it('do conferir vai para trazendo e termina em pronto', () => {
    const conferir = leu(estadoInicial(), 0);
    const trazendo = passa(conferir, EVENTOS.TRAZER);
    expect(trazendo.etapa).toBe(ETAPAS.TRAZENDO);
    expect(passa(trazendo, EVENTOS.TERMINOU).etapa).toBe(ETAPAS.PRONTO);
  });
});

describe('etapas: Voltar', () => {
  it('da segunda pergunta volta para a primeira', () => {
    const estado = passa(leu(estadoInicial(), 2), EVENTOS.CONTINUAR);
    expect(passa(estado, EVENTOS.VOLTAR)).toMatchObject({
      etapa: ETAPAS.PERGUNTAS,
      pergunta: 0,
    });
  });

  it('da primeira pergunta volta para enviar', () => {
    expect(passa(leu(estadoInicial(), 2), EVENTOS.VOLTAR).etapa).toBe(
      ETAPAS.ENVIAR
    );
  });

  it('do conferir volta para a última pergunta', () => {
    const conferir = passa(
      leu(estadoInicial(), 2),
      EVENTOS.CONTINUAR,
      EVENTOS.CONTINUAR
    );
    expect(passa(conferir, EVENTOS.VOLTAR)).toMatchObject({
      etapa: ETAPAS.PERGUNTAS,
      pergunta: 1,
    });
  });

  it('do conferir sem perguntas volta para enviar', () => {
    expect(passa(leu(estadoInicial(), 0), EVENTOS.VOLTAR).etapa).toBe(
      ETAPAS.ENVIAR
    );
  });
});

describe('etapas: fora de hora e recomeço', () => {
  it('evento fora de hora devolve o mesmo estado', () => {
    const inicial = estadoInicial();
    expect(passa(inicial, EVENTOS.CONTINUAR)).toEqual(inicial);
    expect(passa(inicial, EVENTOS.TRAZER)).toEqual(inicial);
    expect(passa(inicial, EVENTOS.TERMINOU)).toEqual(inicial);
    expect(proximo(inicial, { tipo: 'inventado' })).toEqual(inicial);
    expect(proximo(inicial, undefined)).toEqual(inicial);
  });

  it('não volta uma lista que já está sendo trazida', () => {
    const trazendo = passa(leu(estadoInicial(), 0), EVENTOS.TRAZER);
    expect(passa(trazendo, EVENTOS.VOLTAR)).toEqual(trazendo);
  });

  it('não muda o estado que recebeu', () => {
    const inicial = Object.freeze(estadoInicial());
    expect(() => leu(inicial, 2)).not.toThrow();
    expect(inicial.etapa).toBe(ETAPAS.ENVIAR);
  });

  it('"Trazer outra lista" recomeça em enviar', () => {
    const pronto = passa(
      leu(estadoInicial(), 0),
      EVENTOS.TRAZER,
      EVENTOS.TERMINOU
    );
    expect(passa(pronto, EVENTOS.RECOMECAR)).toEqual(estadoInicial());
  });
});

describe('etapaDoTopo', () => {
  it('junta perguntas em Enviar e trazendo em Pronto', () => {
    const base = estadoInicial();
    expect(etapaDoTopo({ ...base, etapa: ETAPAS.PERGUNTAS })).toBe(
      ETAPAS.ENVIAR
    );
    expect(etapaDoTopo({ ...base, etapa: ETAPAS.CONFERIR })).toBe(
      ETAPAS.CONFERIR
    );
    expect(etapaDoTopo({ ...base, etapa: ETAPAS.TRAZENDO })).toBe(
      ETAPAS.PRONTO
    );
  });
});
