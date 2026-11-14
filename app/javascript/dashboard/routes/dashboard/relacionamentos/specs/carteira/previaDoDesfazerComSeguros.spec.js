import { previaDoDesfazerDaTela } from '../../fonte/trazerTraducao';

// #2897 — a prévia do Desfazer como a tela a lê: na lista que trouxe seguros o
// servidor manda também o que acontece com eles; na que não trouxe, não.
describe('a prévia do Desfazer', () => {
  it('leva os seguros da lista que os trouxe', () => {
    expect(
      previaDoDesfazerDaTela({
        tira: 2,
        ficam: 1,
        devolve: 0,
        seguros: { saem: 5, ficam: 1, voltam: 2, outra_chave: 9 },
      })
    ).toEqual({
      tira: 2,
      ficam: 1,
      devolve: 0,
      seguros: { saem: 5, ficam: 1, voltam: 2 },
    });
  });

  it('a lista sem seguros não ganha a chave', () => {
    expect(previaDoDesfazerDaTela({ tira: 2, ficam: 1, devolve: 0 })).toEqual({
      tira: 2,
      ficam: 1,
      devolve: 0,
    });
  });
});
