import { MODULES, hasAccess } from '../customRoles/permissionMatrix';
import { podeDaFuncao } from './fraseDaFuncao';

// O que quem já tem a função perde ao salvar uma alteração (#2308, especificação 5.F): as capacidades do Pode que
// saem (ids de FUNCOES_EQUIPE.PODE) e as áreas que deixam de ser vistas, inclusive as que só olhava. Só contam as
// áreas com "Só olha": as de mexer (e as conversas) já saem como capacidade, e uma área com base (respostas prontas,
// que todo mundo usa) nunca some do menu.
export const perdasDeAcesso = (antes, depois) => {
  const podeDepois = new Set(podeDaFuncao(depois));
  return [
    ...podeDaFuncao(antes)
      .filter(id => !podeDepois.has(id))
      .map(id => ({ id })),
    ...MODULES.filter(
      module =>
        module.levels?.view &&
        hasAccess(module, antes) &&
        !hasAccess(module, depois)
    ).map(module => ({ area: module.key })),
  ];
};
