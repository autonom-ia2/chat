import { semQuemSaiuDaCopia } from '../semQuemSaiuDaCopia';

describe('semQuemSaiuDaCopia', () => {
  const destinos = {
    to: ['ana@familia.com.br'],
    cc: ['rh@empresa.com.br', 'joao@empresa.com.br'],
    bcc: [],
  };

  it('sem ninguém que saiu, devolve o mesmo preenchimento', () => {
    expect(semQuemSaiuDaCopia(destinos, undefined, 'joao@empresa.com.br')).toBe(
      destinos
    );
  });

  it('tira quem saiu de Para e Cc; Para vazio volta ao cliente', () => {
    expect(
      semQuemSaiuDaCopia(
        destinos,
        ['Ana@Familia.com.br'],
        'joao@empresa.com.br'
      )
    ).toEqual({
      to: ['joao@empresa.com.br'],
      cc: ['rh@empresa.com.br', 'joao@empresa.com.br'],
      bcc: [],
    });
  });

  it('o cliente nunca sai, mesmo se estiver na lista', () => {
    expect(
      semQuemSaiuDaCopia(
        destinos,
        ['joao@empresa.com.br'],
        'joao@empresa.com.br'
      )
    ).toBe(destinos);
  });
});
