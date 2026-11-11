import { emReais, faixaDePreco } from '../../vitrine/premium';

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

  it('keeps the third decimal of the IBAMA embargo (R$ 0,225)', () => {
    expect(faixaDePreco(['0.15', '0.225']).max).toContain('0,225');
  });

  it('nothing without a price', () => {
    expect(faixaDePreco([])).toBeNull();
    expect(faixaDePreco(undefined)).toBeNull();
  });
});
