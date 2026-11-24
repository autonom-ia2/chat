import {
  TIPOS,
  carimbosDaCompra,
  codigoDigitado,
  colunasDoCartao,
  compraDeExemplo,
  cupomNovo,
  errosDoCupom,
  errosDoPrograma,
  exemploDeCodigo,
  pertoDoPremio,
  prefixoLimpo,
  programaNovo,
  progresso,
  saldoDeExemplo,
  taxaDeUso,
  textoDeExemplo,
  trocarTipo,
} from '../regras';
import { fraseDoMovimento, sinalDoMovimento } from '../historico';
import {
  darCarimbosPronto,
  faltaOCodigo,
  mandarCupomPronto,
  novoMandarCupom,
} from '../../automacoes/livre/passosNovos/fidelidadeNaAutomacao';

// #3100 — as contas do cartão fidelidade e do cupom, sem tela.
const programa = (extra = {}) => ({
  ...programaNovo(),
  premio: 'Lavagem grátis',
  ...extra,
});

describe('cliente de exemplo', () => {
  it('a compra de exemplo mostra o troco e nunca fica abaixo de R$ 100', () => {
    expect(compraDeExemplo(programa())).toBe(120);
    expect(compraDeExemplo(programa({ a_cada: 1 }))).toBe(100);
  });

  it('o saldo de exemplo fica perto do prêmio', () => {
    expect(saldoDeExemplo(programa())).toBe(7);
    expect(saldoDeExemplo(programa({ tipo: TIPOS.PONTOS, meta: 500 }))).toBe(
      320
    );
    expect(saldoDeExemplo(programa({ meta: null }))).toBe(0);
  });
});

describe('carimbosDaCompra', () => {
  it('dá um carimbo a cada faixa inteira, sem guardar o troco', () => {
    expect(carimbosDaCompra(120, programa())).toBe(2);
    expect(carimbosDaCompra(49.9, programa())).toBe(0);
    expect(carimbosDaCompra(50, programa())).toBe(1);
  });

  it('multiplica pelo que cada faixa dá', () => {
    expect(carimbosDaCompra(120, programa({ ganha: 3 }))).toBe(6);
  });

  it('não dá nada com valor ou programa inválido', () => {
    expect(carimbosDaCompra(-10, programa())).toBe(0);
    expect(carimbosDaCompra(Number.NaN, programa())).toBe(0);
    expect(carimbosDaCompra(100, programa({ a_cada: 0 }))).toBe(0);
    expect(carimbosDaCompra(100, null)).toBe(0);
  });
});

describe('progresso e pertoDoPremio', () => {
  it('conta o que falta e o que sobra depois do prêmio', () => {
    expect(progresso(7, 10)).toEqual({
      tem: 7,
      feitos: 7,
      faltam: 3,
      completo: false,
      premios: 0,
      sobra: 0,
    });
    expect(progresso(23, 10)).toMatchObject({
      feitos: 10,
      faltam: 0,
      completo: true,
      premios: 2,
      sobra: 13,
    });
  });

  it('trata saldo negativo ou vazio como zero', () => {
    expect(progresso(-2, 10).tem).toBe(0);
    expect(progresso(undefined, 10).faltam).toBe(10);
  });

  it('perto é faltar até 20% da meta (no mínimo 1), sem estar completo', () => {
    expect(pertoDoPremio(8, 10)).toBe(true);
    expect(pertoDoPremio(7, 10)).toBe(false);
    expect(pertoDoPremio(10, 10)).toBe(false);
    expect(pertoDoPremio(4, 5)).toBe(true);
    expect(pertoDoPremio(400, 500)).toBe(true);
  });
});

describe('errosDoPrograma', () => {
  it('programa novo com prêmio está pronto', () => {
    expect(errosDoPrograma(programa())).toEqual([]);
  });

  it('aponta cada campo que falta, na ordem da tela', () => {
    expect(
      errosDoPrograma(
        programa({ a_cada: 0, ganha: null, meta: 1, premio: ' ' })
      )
    ).toEqual(['A_CADA', 'GANHA', 'META', 'PREMIO']);
  });

  it('carimbos param em 20; pontos aceitam metas grandes', () => {
    expect(errosDoPrograma(programa({ meta: 21 }))).toEqual(['META']);
    expect(
      errosDoPrograma(programa({ tipo: TIPOS.PONTOS, meta: 5000 }))
    ).toEqual([]);
  });

  it('recusa prêmio com mais de 80 letras', () => {
    expect(errosDoPrograma(programa({ premio: 'a'.repeat(81) }))).toEqual([
      'PREMIO',
    ]);
  });
});

describe('trocarTipo', () => {
  it('ajusta a meta para o outro jeito de juntar', () => {
    const pontos = trocarTipo(programa(), TIPOS.PONTOS);
    expect(pontos).toMatchObject({ tipo: 'pontos', a_cada: 1, meta: 500 });
    expect(trocarTipo(pontos, TIPOS.CARIMBOS)).toMatchObject({
      tipo: 'carimbos',
      a_cada: 50,
      meta: 10,
    });
  });

  it('mantém o mesmo objeto quando o tipo não muda', () => {
    const atual = programa();
    expect(trocarTipo(atual, TIPOS.CARIMBOS)).toBe(atual);
  });
});

describe('colunasDoCartao', () => {
  it.each([
    [5, 5],
    [6, 6],
    [8, 4],
    [10, 5],
    [12, 6],
    [15, 5],
    [20, 5],
    [7, 5],
  ])('meta %i fica em linhas de %i', (meta, colunas) => {
    expect(colunasDoCartao(meta)).toBe(colunas);
  });
});

describe('código do cupom', () => {
  it('limpa o começo do código: maiúsculas, sem acento, só letra e número', () => {
    expect(prefixoLimpo('volta à loja!')).toBe('VOLTAALO');
    expect(prefixoLimpo('São João')).toBe('SAOJOAO');
    expect(prefixoLimpo('')).toBe('');
  });

  it('monta o exemplo com o fim fixo', () => {
    expect(exemploDeCodigo('volta')).toBe('VOLTA-7KD2');
    expect(exemploDeCodigo('')).toBe('7KD2');
  });

  it('o código digitado perde os espaços e o hífen e vira maiúsculas', () => {
    expect(codigoDigitado('  volta - 7kd2 ')).toBe('VOLTA7KD2');
    expect(codigoDigitado('volta7kd2')).toBe('VOLTA7KD2');
  });
});

describe('errosDoCupom', () => {
  const cupom = (extra = {}) => ({
    ...cupomNovo(),
    nome: 'Volta',
    prefixo: 'VOLTA',
    ...extra,
  });

  it('cupom novo com nome e começo do código está pronto', () => {
    expect(errosDoCupom(cupom())).toEqual([]);
  });

  it('desconto em % vai de 1 a 100', () => {
    expect(
      errosDoCupom(cupom({ oferta: { tipo: 'porcentagem', valor: 120 } }))
    ).toEqual(['OFERTA']);
  });

  it('presente precisa do texto', () => {
    expect(
      errosDoCupom(cupom({ oferta: { tipo: 'presente', texto: '' } }))
    ).toEqual(['OFERTA']);
  });

  it('aponta nome, começo e validade', () => {
    expect(
      errosDoCupom(cupom({ nome: '', prefixo: '!!', validade_dias: 9 }))
    ).toEqual(['NOME', 'PREFIXO', 'VALIDADE']);
  });
});

describe('taxaDeUso e textoDeExemplo', () => {
  it('arredonda a porcentagem e não divide por zero', () => {
    expect(taxaDeUso({ mandados: 240, usados: 37 })).toBe(15);
    expect(taxaDeUso({ mandados: 0, usados: 0 })).toBeNull();
  });

  it('troca cada dado pelo exemplo', () => {
    expect(
      textoDeExemplo(['Seu cupom ', { $valor: 'cupom.codigo' }, '.'], {
        'cupom.codigo': 'VOLTA-7KD2',
      })
    ).toBe('Seu cupom VOLTA-7KD2.');
  });
});

describe('historico da ficha', () => {
  const textos = {
    unidade: n => `${n} carimbos`,
    dinheiro: valor => `R$ ${valor}`,
    tipo: 'carimbos',
  };

  it.each([
    [{ tipo: 'compra', quantos: 2, valor: { total: 120 } }, 'compra'],
    [{ tipo: 'compra', quantos: 2 }, 'compra_sem_valor'],
    [{ tipo: 'presente', quantos: 1, motivo: 'aniversário' }, 'presente'],
    [{ tipo: 'presente', quantos: 1 }, 'presente_sem_motivo'],
    [{ tipo: 'ajuste', quantos: -2, quem: 'Ana' }, 'ajuste_menos'],
    [{ tipo: 'ajuste', quantos: 2, quem: 'Ana' }, 'ajuste_mais'],
    [{ tipo: 'premio', quantos: -10, quem: 'Ana' }, 'premio'],
    [{ tipo: 'premio', quantos: -10 }, 'premio_sem_quem'],
    [{ tipo: 'venceu', quantos: -3 }, 'venceu'],
    [{ tipo: 'estorno', quantos: -1 }, 'estorno'],
    [{ tipo: 'novo', quantos: 1 }, 'outro'],
  ])('%o vira a frase %s', (movimento, chave) => {
    expect(fraseDoMovimento(movimento, textos).chave).toBe(chave);
  });

  it('usa o valor da compra e o número sem sinal na frase', () => {
    expect(
      fraseDoMovimento(
        { tipo: 'compra', quantos: 2, valor: { total: 120, moeda: 'BRL' } },
        textos
      ).valores
    ).toMatchObject({ quantos: '2 carimbos', valor: 'R$ 120' });
  });

  it('o sinal mostra ganho com + e saída com o traço de menos', () => {
    expect(sinalDoMovimento(2)).toBe('+2');
    expect(sinalDoMovimento(-10)).toBe('−10');
  });
});

describe('passos da automação', () => {
  it('dar carimbos precisa de quantos e motivo curto', () => {
    expect(darCarimbosPronto({ quantos: 2, motivo: '' })).toBe(true);
    expect(darCarimbosPronto({ quantos: 0 })).toBe(false);
    expect(darCarimbosPronto({ quantos: 1, motivo: 'a'.repeat(61) })).toBe(
      false
    );
  });

  it('mandar cupom nasce com o código no texto e só fica pronto com o cupom', () => {
    const passo = novoMandarCupom('p1', chave => chave);
    expect(faltaOCodigo(passo)).toBe(false);
    expect(mandarCupomPronto(passo)).toBe(false);
    expect(mandarCupomPronto({ ...passo, cupom_id: 3 })).toBe(true);
    expect(mandarCupomPronto({ ...passo, cupom_id: 3, texto: ['Oi!'] })).toBe(
      false
    );
  });
});
