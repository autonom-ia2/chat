import { PERMISSOES_PARA_ENTRAR, podeEntrar } from '../comentariosInstagram';

// #2358: o botão de entrar só aparece para quem chega ao fim do caminho, na régua de MetaAdsOrganic.vue.
describe('comentariosInstagram.podeEntrar', () => {
  const com =
    (...chaves) =>
    chave =>
      chaves.includes(chave);

  it('conectar o Instagram pede criar a caixa (inbox_manage)', () => {
    expect(podeEntrar('not_connected', com('inbox_manage'))).toBe(true);
    expect(podeEntrar('not_connected', com('integration_manage'))).toBe(false);
  });

  it('entrar de novo pede integration_manage e inbox_manage, as duas', () => {
    expect(
      podeEntrar('needs_login', com('inbox_manage', 'integration_manage'))
    ).toBe(true);
    expect(podeEntrar('needs_login', com('inbox_manage'))).toBe(false);
    expect(podeEntrar('needs_login', com('integration_manage'))).toBe(false);
  });

  it('declara as permissões que a tela precisa ler', () => {
    expect([...PERMISSOES_PARA_ENTRAR].sort()).toEqual([
      'inbox_manage',
      'integration_manage',
    ]);
  });
});
