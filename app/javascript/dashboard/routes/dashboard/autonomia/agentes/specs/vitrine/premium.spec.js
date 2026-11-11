import {
  emReais,
  estadoDasGratis,
  faixaDePreco,
  marcasDasGratis,
} from '../../vitrine/premium';

// #2858 F7 — o preço dos cards Premium em texto de gente, a partir do que o servidor manda ("0.15").
describe('premium · faixaDePreco', () => {
  it('one price for the card with a single price', () => {
    expect(faixaDePreco(['0.09'])).toEqual({ unico: emReais('0.09') });
    expect(emReais('0.09')).toContain('0,09');
  });

  it('from the lowest to the highest when the card has several prices', () => {
    const faixa = faixaDePreco(['0.15', '0.06']);
    expect(faixa.min).toContain('0,06');
    expect(faixa.max).toContain('0,15');
  });

  it('every price closes in whole cents (the IBAMA embargo is R$ 0,23)', () => {
    expect(faixaDePreco(['0.15', '0.23']).max).toContain('0,23');
    expect(emReais('0.23')).not.toContain('0,230');
  });

  it('nothing without a price', () => {
    expect(faixaDePreco([])).toBeNull();
    expect(faixaDePreco(undefined)).toBeNull();
  });
});

describe('premium · grátis do mês', () => {
  it('two or more left, exactly one left, none left', () => {
    expect(estadoDasGratis(15)).toBe('RESTAM');
    expect(estadoDasGratis(2)).toBe('RESTAM');
    expect(estadoDasGratis(1)).toBe('RESTA_UMA');
    expect(estadoDasGratis(0)).toBe('ACABARAM');
    expect(estadoDasGratis(undefined)).toBe('ACABARAM');
  });

  it('one mark per free lookup, filled while it is left', () => {
    const marcas = marcasDasGratis(20, 15);
    expect(marcas).toHaveLength(20);
    expect(marcas.filter(Boolean)).toHaveLength(15);
    expect(marcas[0]).toBe(true);
    expect(marcas[19]).toBe(false);
    expect(marcasDasGratis(20, 0).some(Boolean)).toBe(false);
    expect(marcasDasGratis(20, 99).every(Boolean)).toBe(true);
  });
});
