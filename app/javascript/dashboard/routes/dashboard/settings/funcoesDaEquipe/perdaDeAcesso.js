import {
  CONVERSATION_LEVELS,
  LEVELS,
  MODULES,
  getLevel,
  hasAccess,
  keysOf,
} from '../customRoles/permissionMatrix';
import { contidasEm, podeDaFuncao, soOlhaNaArea } from './fraseDaFuncao';
import { NIVEIS_DE_VENDAS, nivelDeVendas } from './nivelDeVendas';
import { chavesEfetivas } from './semFuncao';

// O que quem já tem a função perde ao salvar uma alteração (#2308, especificação 5.F): as capacidades do Pode que
// saem ({ id } de FUNCOES_EQUIPE.PODE, na ordem do Pode: conversas, vendas, contatos, o resto) e as áreas que somem
// ({ area }, uma por item, para a contagem do título bater com a lista). Conta o que a função dá de fato
// (chavesEfetivas): uma função antiga só com crm_admin perde também o que ele trazia. Cada coisa sai uma vez, e a mais
// específica vence: a área cuja perda já saiu numa capacidade dela (procurar clientes novos, ver os relatórios de
// atendimento) não se repete (revisão do #2308, rodada 3). Uma área sem nível de ver (respostas prontas, que todo
// mundo usa) nunca some. Uma capacidade contida numa maior que a função passa a ter (atender todas cobre responder as
// entregues) não é perda (rodada 4).
export const perdasDeAcesso = (gravadasAntes, gravadasDepois) => {
  const antes = chavesEfetivas(gravadasAntes);
  const depois = chavesEfetivas(gravadasDepois);
  const podeDepois = podeDaFuncao(depois);
  const cobertas = [...podeDepois, ...contidasEm(podeDepois)];
  const perdidas = podeDaFuncao(antes).filter(id => !cobertas.includes(id));
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

// O que fica numa queda de nível (especificação 5.F: "A partir de agora, só vão olhar os contatos."): a área que
// desceu sem sumir, com o nível de agora. `nivel` é 'OLHA' (ficou só vendo) ou, nas conversas que descem de todas para
// as próprias, a frase do que ainda atende (fraseDasProprias); null quando nenhuma ou mais de uma área desceu assim, ou
// quando o nível de agora não cabe numa frase (Vendas de "Cuida de tudo" para "Pode mexer", ou um "Só olha" que ainda
// muda algo na área).
const ORDEM_DAS_CONVERSAS = [
  CONVERSATION_LEVELS.NONE,
  CONVERSATION_LEVELS.VIEW,
  CONVERSATION_LEVELS.LIMITED,
  CONVERSATION_LEVELS.ALL,
];
const ORDEM = [LEVELS.NONE, LEVELS.VIEW, LEVELS.MANAGE];
const leitura = module => {
  if (module.type === 'conversations')
    return { nivel: p => getLevel(module, p), ordem: ORDEM_DAS_CONVERSAS };
  if (module.type === 'crm')
    return { nivel: nivelDeVendas, ordem: NIVEIS_DE_VENDAS };
  return { nivel: p => getLevel(module, p), ordem: ORDEM };
};
// As próprias conversas e o que vem junto, pelo Pode de agora (o mesmo da prévia): pegar as novas que estão sem
// ninguém e ajudar pelo link. "Só as próprias" é só quando não vem nada junto (revisão do #2308, rodada 5).
const fraseDasProprias = permissions => {
  const pode = podeDaFuncao(permissions);
  const novas = pode.includes('PEGAR_NOVAS');
  const link = pode.includes('AJUDAR_PELO_LINK');
  if (novas && link) return 'PROPRIAS_NOVAS_E_LINK';
  if (novas) return 'PROPRIAS_E_NOVAS';
  return link ? 'PROPRIAS_E_LINK' : 'PROPRIAS';
};
// "Só olha" só quando nada do que a função ainda pode nessa área muda ou leva algo (soOlhaNaArea, a mesma regra da
// frase, de Ajustes e dos cartões). Vendas em "Só olha" que ainda monta as colunas ou usa a IA não "só olha"; aí não
// há frase do que fica (revisão do #2308, rodada 6).
const soOlha = (permissions, module) =>
  soOlhaNaArea(module.key, permissions) ? 'OLHA' : null;
const FRASE_DO_NIVEL = {
  [LEVELS.VIEW]: soOlha,
  [CONVERSATION_LEVELS.LIMITED]: fraseDasProprias,
};

export const nivelQueFica = (gravadasAntes, gravadasDepois) => {
  const desceram = MODULES.map(module => {
    const { nivel, ordem } = leitura(module);
    const antes = nivel(gravadasAntes);
    const depois = nivel(gravadasDepois);
    const desceu =
      depois !== LEVELS.NONE && ordem.indexOf(depois) < ordem.indexOf(antes);
    const frase = FRASE_DO_NIVEL[depois];
    return desceu
      ? {
          area: module.key,
          nivel: frase ? frase(gravadasDepois, module) : null,
        }
      : null;
  }).filter(Boolean);
  if (desceram.length !== 1 || !desceram[0].nivel) return null;
  return desceram[0];
};
