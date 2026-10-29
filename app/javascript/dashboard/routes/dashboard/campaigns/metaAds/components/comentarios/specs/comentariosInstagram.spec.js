import { podeEntrar } from '../comentariosInstagram';

// #2358: o botão de entrar só aparece para quem chega ao fim do caminho, na régua de MetaAdsOrganic.vue.
describe('comentariosInstagram.podeEntrar', () => {
  it('conectar o Instagram pede criar a caixa', () => {
    expect(podeEntrar('not_connected', { criarCaixa: true })).toBe(true);
    expect(
      podeEntrar('not_connected', { criarCaixa: false, reautorizar: true })
    ).toBe(false);
  });

  it('entrar de novo pede trocar a credencial e criar a caixa, as duas', () => {
    const entra = permissoes => podeEntrar('needs_login', permissoes);

    expect(entra({ criarCaixa: true, reautorizar: true })).toBe(true);
    expect(entra({ criarCaixa: true, reautorizar: false })).toBe(false);
    expect(entra({ criarCaixa: false, reautorizar: true })).toBe(false);
  });
});
