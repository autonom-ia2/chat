import { guideRouteParams } from '../guideNavigation';

// O botão do Guia leva à tela de UM registro com o id que o modelo leu (#590).
describe('guideRouteParams', () => {
  it('repassa os ids da tela', () => {
    expect(guideRouteParams({ inboxId: '12', tab: 'business-hours' })).toEqual({
      inboxId: '12',
      tab: 'business-hours',
    });
  });

  // `accountScopedRoute` espalha estes parâmetros depois do id da conta aberta:
  // um accountId aqui trocaria a conta do botão.
  it('nunca deixa a resposta escolher a conta', () => {
    expect(guideRouteParams({ accountId: '99', inboxId: 12 })).toEqual({
      inboxId: 12,
    });
  });

  it('descarta o que não é valor simples', () => {
    expect(
      guideRouteParams({ inboxId: { id: 1 }, tab: ['a'], x: null })
    ).toEqual({});
  });

  it('aceita navegação sem parâmetro nenhum', () => {
    expect(guideRouteParams(undefined)).toEqual({});
  });
});
