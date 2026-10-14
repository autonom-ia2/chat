import {
  levaProdutos,
  pedidoDeProdutos,
  produtosParaEnvio,
  produtosPendentes,
} from '../helpers/produtosNaCampanha';
import {
  extrasParaEnvio,
  oQuePedir,
  pendencias,
  soModeloCompleto,
} from '../helpers/formatoNaCampanha';

// #1418: produtos do catálogo na campanha, lidos da estrutura do modelo da Meta.
const corpo = { type: 'BODY', text: 'Oi {{1}}' };
const um = {
  components: [
    { type: 'HEADER', format: 'PRODUCT' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] },
  ],
};
const varios = {
  components: [
    { type: 'HEADER', format: 'TEXT', text: 'Novidades' },
    corpo,
    { type: 'BUTTONS', buttons: [{ type: 'MPM', text: 'Ver itens' }] },
  ],
};
const cartao = {
  components: [
    { type: 'HEADER', format: 'PRODUCT' },
    { type: 'BUTTONS', buttons: [{ type: 'SPM' }] },
  ],
};
const carrossel = {
  components: [corpo, { type: 'CAROUSEL', cards: [cartao, cartao] }],
};
const deFotos = {
  components: [
    corpo,
    {
      type: 'CAROUSEL',
      cards: [{ components: [{ type: 'HEADER', format: 'IMAGE' }] }],
    },
  ],
};
const produto = (id, disponivel = true) => ({
  id,
  nome: `Produto ${id}`,
  preco: 'R$1',
  foto: '',
  disponivel,
});

describe('produtosNaCampanha', () => {
  it('reads one, several or a carousel of products from the structure', () => {
    expect(pedidoDeProdutos(um)).toEqual({ tipo: 'um', minimo: 1, maximo: 1 });
    expect(pedidoDeProdutos(varios)).toEqual({
      tipo: 'varios',
      minimo: 1,
      maximo: 30,
    });
    expect(pedidoDeProdutos(carrossel)).toEqual({
      tipo: 'carrossel',
      minimo: 2,
      maximo: 10,
    });
    expect(levaProdutos(deFotos)).toBe(false);
    expect(pedidoDeProdutos({ components: [corpo] })).toBeNull();
  });

  it('is pending without the right number of products or with one sold out', () => {
    const pedido = pedidoDeProdutos(carrossel);
    expect(produtosPendentes(pedido, [produto('a')])).toBe(true);
    expect(produtosPendentes(pedido, [produto('a'), produto('b')])).toBe(false);
    expect(produtosPendentes(pedido, [produto('a'), produto('b', false)])).toBe(
      true
    );
    expect(produtosPendentes(null, [])).toBe(false);
  });

  it('sends the codes in the chosen order and the names for the pause message', () => {
    expect(produtosParaEnvio([produto('b'), produto('a')])).toEqual({
      products: {
        retailer_ids: ['b', 'a'],
        names: { b: 'Produto b', a: 'Produto a' },
      },
    });
  });

  it('asks the products in the campaign, never a photo per product card', () => {
    const pedido = oQuePedir(carrossel);
    expect(pedido.cartoes).toEqual([]);
    expect(pendencias(pedido, {}, { timeZone: 'UTC' })).toEqual(['PRODUTOS']);
    const valores = { produtos: [produto('a'), produto('b')] };
    expect(pendencias(pedido, valores, { timeZone: 'UTC' })).toEqual([]);
    expect(extrasParaEnvio(pedido, valores, { timeZone: 'UTC' })).toEqual(
      produtosParaEnvio(valores.produtos)
    );
  });

  it('keeps the products in the full template (no written message instead)', () => {
    expect([um, varios, carrossel].every(soModeloCompleto)).toBe(true);
  });
});
