import {
  LEVELS,
  MODULES,
  getLevel,
  hasAccess,
} from '../customRoles/permissionMatrix';
import { podeDaFuncao } from './fraseDaFuncao';
import { chavesEfetivas } from './semFuncao';

// O que quem já tem a função perde ao salvar uma alteração (#2308, especificação 5.F): as capacidades do Pode que
// saem (ids de FUNCOES_EQUIPE.PODE, na ordem do Pode: conversas, vendas, contatos, o resto) e as áreas que somem.
// Conta o que a função dá de fato (chavesEfetivas): uma função antiga só com crm_admin perde também o que ele trazia.
// Uma área que só olhava e cuja perda já saiu numa capacidade (ver os relatórios de atendimento) não se repete; quem
// mexia perde a capacidade e também deixa de ver a área, e as duas coisas aparecem. Uma área sem nível de ver
// (respostas prontas, que todo mundo usa) nunca some.
const chavesDa = module => [
  ...Object.values(module.levels || {}),
  ...(module.extras || []),
];

export const perdasDeAcesso = (gravadasAntes, gravadasDepois) => {
  const antes = chavesEfetivas(gravadasAntes);
  const depois = chavesEfetivas(gravadasDepois);
  const podeDepois = podeDaFuncao(depois);
  const perdidas = podeDaFuncao(antes).filter(id => !podeDepois.includes(id));
  const jaDita = module => {
    if (getLevel(module, antes) !== LEVELS.VIEW) return false;
    const semArea = podeDaFuncao(
      antes.filter(chave => !chavesDa(module).includes(chave))
    );
    return perdidas.some(id => !semArea.includes(id));
  };
  const areas = MODULES.filter(
    module =>
      module.levels?.view &&
      hasAccess(module, antes) &&
      !hasAccess(module, depois) &&
      !jaDita(module)
  ).map(module => module.key);
  return [
    ...perdidas.map(id => ({ id })),
    ...(areas.length ? [{ areas }] : []),
  ];
};
