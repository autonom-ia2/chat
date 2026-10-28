import { MODULES, hasAccess, keysOf } from '../customRoles/permissionMatrix';
import { podeDaFuncao } from './fraseDaFuncao';
import { chavesEfetivas } from './semFuncao';

// O que quem já tem a função perde ao salvar uma alteração (#2308, especificação 5.F): as capacidades do Pode que
// saem ({ id } de FUNCOES_EQUIPE.PODE, na ordem do Pode: conversas, vendas, contatos, o resto) e as áreas que somem
// ({ area }, uma por item, para a contagem do título bater com a lista). Conta o que a função dá de fato
// (chavesEfetivas): uma função antiga só com crm_admin perde também o que ele trazia. Cada coisa sai uma vez, e a mais
// específica vence: a área cuja perda já saiu numa capacidade dela (procurar clientes novos, ver os relatórios de
// atendimento) não se repete (revisão do #2308, rodada 3). Uma área sem nível de ver (respostas prontas, que todo
// mundo usa) nunca some.
export const perdasDeAcesso = (gravadasAntes, gravadasDepois) => {
  const antes = chavesEfetivas(gravadasAntes);
  const depois = chavesEfetivas(gravadasDepois);
  const podeDepois = podeDaFuncao(depois);
  const perdidas = podeDaFuncao(antes).filter(id => !podeDepois.includes(id));
  const jaDita = module => {
    const semArea = podeDaFuncao(
      antes.filter(chave => !keysOf(module).includes(chave))
    );
    return perdidas.some(id => !semArea.includes(id));
  };
  const areas = MODULES.filter(
    module =>
      module.levels?.view &&
      hasAccess(module, antes) &&
      !hasAccess(module, depois) &&
      !jaDita(module)
  );
  return [
    ...perdidas.map(id => ({ id })),
    ...areas.map(module => ({ area: module.key })),
  ];
};
