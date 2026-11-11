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

  it('every price closes in whole cents (the IBAMA embargo is R$ 0,23)', () => {
    expect(faixaDePreco(['0.15', '0.23']).max).toContain('0,23');
    expect(emReais('0.23')).not.toContain('0,230');
  });

  it('nothing without a price', () => {
    expect(faixaDePreco([])).toBeNull();
    expect(faixaDePreco(undefined)).toBeNull();
  });
});
