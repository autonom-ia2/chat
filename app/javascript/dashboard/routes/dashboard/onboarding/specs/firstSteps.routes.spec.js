import { routes } from '../firstSteps.routes';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';

// O nome da rota importa: o guard do cadastro trata QUALQUER rota com
// `onboarding_` no nome como tela do fluxo de cadastro e, numa conta que já
// passou dele, devolve a pessoa para o dashboard. Com esse prefixo, o item
// "Primeiros passos" do menu não abria nada em conta de produção.
describe('rota dos Primeiros passos', () => {
  const [rota] = routes;

  it('não é confundida com o fluxo de cadastro', () => {
    expect(isOnOnboardingView(rota)).toBe(false);
    expect(rota.name).not.toContain('onboarding_');
  });

  it('abre em /primeiros-passos e é só de administrador', () => {
    expect(rota.path).toContain('primeiros-passos');
    expect(rota.meta.permissions).toEqual(['administrator']);
  });
});
