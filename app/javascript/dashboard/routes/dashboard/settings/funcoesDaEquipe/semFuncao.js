import {
  DELEGATION_KEYS,
  KEY_DEPENDENCIES,
} from 'dashboard/constants/permissions';
import { holdsKey } from 'dashboard/helper/peopleAccess';
import { modulesWithKeys } from '../customRoles/permissionMatrix';
import { DONO_DAS_CHAVES } from './areasDaFuncao';
import { comImplicadas } from './comImplicadas';
import contratoGerado from './semFuncaoCapacidades.json';

// O que muda para quem fica sem função (#2308, especificação 5.D, 5.E e 7.9). Lê o contrato gerado das policies
// (semFuncaoCapacidades.json, PR 2) e nunca uma lista escrita à mão por função. `estaLigada(flag)` diz se uma flag da
// conta está ligada: os relatórios das vendas dependem de crm_numeros_lentes. Os specs passam um contrato próprio.
//
// Cada item do diff tem `chave` (para a tela) e `tipo`: 'capacidade' (texto em FUNCOES_EQUIPE.SEM_FUNCAO.<id>) ou
// 'area' (o que a função dava numa área e o "Sem função" não dá). `jeito` diz o tamanho da perda: 'MEXER' ou 'VER' quando
// a área inteira some; 'PARTE' quando o "Sem função" ainda usa a área (as vendas das colunas) e só um pedaço sai.
const CHAVES_DE_VENDAS = Object.values(DONO_DAS_CHAVES)
  .flat()
  .filter(chave => chave.startsWith('crm_'));
const ALCANCES = [
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];
const PREMISSAS = ['na_caixa', 'participa_da_coluna'];

const podeSemFuncao = (capacidade, estaLigada) => {
  const flag = capacidade.depende_da_flag;
  if (!flag) return capacidade.pode;
  return estaLigada(flag.flag) ? flag.ligada : flag.desligada;
};

// As capacidades e os extras que têm chave (anuncio_de_origem → meta_ads_view), com a flag resolvida.
const itensDo = (contrato, estaLigada) =>
  [
    ...contrato.capacidades,
    ...(contrato.extras || []).filter(extra => extra.chaves.length),
  ].map(item => ({ ...item, pode: podeSemFuncao(item, estaLigada) }));

export const capacidadesSemFuncao = (estaLigada, contrato = contratoGerado) =>
  itensDo(contrato, estaLigada).map(({ id, pode, chaves }) => ({
    id,
    pode,
    chaves,
  }));

// O que só vale num pedaço da conta (nos canais em que a pessoa está, nas colunas de que participa), pelas premissas
// do contrato: [{ premissa, ids }].
export const premissasSemFuncao = (estaLigada, contrato = contratoGerado) =>
  PREMISSAS.map(premissa => ({
    premissa,
    ids: itensDo(contrato, estaLigada)
      .filter(item => item.pode && (item.premissas || []).includes(premissa))
      .map(item => item.id),
  })).filter(item => item.ids.length);

// O que a função dá de fato: as implicadas que o servidor grava, e crm_admin vale como dona de toda chave das vendas
// (espelho de CrmPermissions#crm_permission?). Chave que depende de outra (KEY_DEPENDENCIES) só vale com ela: metas do
// mês pedem os valores em R$, que o crm_admin não liga (Enterprise::Crm::MetasPolicy#manage?). Sem R$, a função não
// define metas, e ir para "Sem função" não as tira.
const comAdmin = chaves =>
  chaves.includes('crm_admin')
    ? [...new Set([...chaves, ...CHAVES_DE_VENDAS])]
    : chaves;
const efetivas = permissions => {
  const chaves = comAdmin(comImplicadas(permissions));
  return chaves.filter(
    chave =>
      !KEY_DEPENDENCIES[chave] || chaves.includes(KEY_DEPENDENCIES[chave])
  );
};

// O que quem está sem função tem: só as chaves das capacidades que ele pode, com as implicadas. Atender todas as
// conversas grava também os dois alcances (setLevel em ALL), então os cobre.
const chavesSemFuncao = itens => {
  const chaves = comImplicadas(
    itens.filter(item => item.pode).flatMap(item => item.chaves)
  );
  return chaves.includes('conversation_manage')
    ? [...chaves, ...ALCANCES]
    : chaves;
};

// `_manage` vale como `_view`, como no servidor.
const quemTem = chaves => chave => holdsKey({ permissions: chaves }, chave);

const capacidade = item => ({
  chave: item.id,
  tipo: 'capacidade',
  chaves: item.chaves,
  delegacao: item.chaves.some(chave => DELEGATION_KEYS.includes(chave)),
});

// As áreas inteiras que se perdem, na ordem do mapa. Uma área cujo nível já saiu numa capacidade do contrato
// (procurar clientes novos) não se repete.
const areasPerdidas = (perdidas, cobertas, semFuncao) =>
  modulesWithKeys(perdidas)
    .filter(
      module =>
        !Object.values(module.levels || {}).some(chave =>
          cobertas.includes(chave)
        )
    )
    .map(module => {
      const daArea = perdidas.filter(
        chave => modulesWithKeys([chave])[0] === module
      );
      const mexia = daArea.some(chave => chave !== module.levels?.view);
      const ficaNaArea = modulesWithKeys(semFuncao).includes(module);
      return {
        chave: module.key,
        tipo: 'area',
        jeito: (ficaNaArea && 'PARTE') || (mexia ? 'MEXER' : 'VER'),
      };
    });

export const diffEntre = (
  permissions,
  estaLigada,
  contrato = contratoGerado
) => {
  const itens = itensDo(contrato, estaLigada);
  const daFuncao = efetivas(permissions);
  const funcaoTem = quemTem(daFuncao);
  const semFuncao = chavesSemFuncao(itens);
  const semFuncaoTem = quemTem(semFuncao);
  const perdidasNoContrato = itens.filter(
    item => !item.pode && item.chaves.some(funcaoTem)
  );
  const cobertas = perdidasNoContrato.flatMap(item => item.chaves);
  const perdidas = daFuncao.filter(
    chave => !semFuncaoTem(chave) && !cobertas.includes(chave)
  );
  return {
    ganha: itens
      .filter(item => item.pode && !item.chaves.every(funcaoTem))
      .map(capacidade),
    perde: [
      ...perdidasNoContrato.map(capacidade),
      ...areasPerdidas(perdidas, cobertas, semFuncao),
    ],
  };
};
