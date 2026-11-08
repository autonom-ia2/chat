import {
  CRM_ADMIN_PERMISSION,
  CRM_MOVE_CARDS_PERMISSION,
} from 'dashboard/constants/permissions';
import {
  CRM_EXTRAS_IMPLIED_BY_ADMIN,
  LEVELS,
  getLevel,
  moduleByKey,
  setLevel,
  toggleExtra,
} from '../customRoles/permissionMatrix';
import { motivoDasChaves } from './motivoDaTrava';

// Os quatro níveis de Vendas (#2308, especificação 7.4): Não vê, Só olha, Pode mexer e Cuida de tudo. O quarto é o
// crm_admin, que traz as seis chaves de CRM_EXTRAS_IMPLIED_BY_ADMIN; nunca grava sales_value_view.
export const CRM_ADMIN = CRM_ADMIN_PERMISSION;
export const TUDO = 'tudo';
export const NIVEIS_DE_VENDAS = [LEVELS.NONE, LEVELS.VIEW, LEVELS.MANAGE, TUDO];
export const CHAVES_DO_TUDO = [CRM_ADMIN, ...CRM_EXTRAS_IMPLIED_BY_ADMIN];

const vendas = () => moduleByKey('CRM');

export const nivelDeVendas = permissions =>
  permissions.includes(CRM_ADMIN) ? TUDO : getLevel(vendas(), permissions);

export const mexeNasVendas = permissions =>
  [LEVELS.MANAGE, TUDO].includes(nivelDeVendas(permissions));

// "Só olha" não mexe: o setLevel compartilhado tira crm_manage_cards e o que é só de quem mexe, mas deixa mover as
// vendas (crm_move_cards), que o servidor aceita sozinho (CardPolicy#move?). Só a função antiga que já a tem mostra
// a linha ligada no "Mais", para dar para desligar.
const soOlha = permissions =>
  setLevel(vendas(), LEVELS.VIEW, permissions).filter(
    chave => chave !== CRM_MOVE_CARDS_PERMISSION
  );
const comNivel = (nivel, permissions) =>
  nivel === LEVELS.VIEW
    ? soOlha(permissions)
    : setLevel(vendas(), nivel, permissions);

// Sair de "Cuida de tudo" tira o crm_admin e só o que ele trouxe: `antes` é a função de quando a pessoa entrou no 4º
// nível, e o que já estava ligado antes volta como era. Sem `antes` (a função já abriu com crm_admin), não dá para
// saber o que era dela: saem as seis, para "Pode mexer" não deixar planilhas e metas ligadas sem a pessoa ver.
export const escolherNivelDeVendas = (nivel, permissions, antes = null) => {
  if (nivel === TUDO)
    return permissions.includes(CRM_ADMIN)
      ? permissions
      : toggleExtra(vendas(), CRM_ADMIN, permissions);
  if (!permissions.includes(CRM_ADMIN)) return comNivel(nivel, permissions);
  const trouxe = CHAVES_DO_TUDO.filter(
    chave => !antes || chave === CRM_ADMIN || !antes.includes(chave)
  );
  return comNivel(
    nivel,
    permissions.filter(chave => !trouxe.includes(chave))
  );
};

// Para quem não é administrador nem tem grant_above_own, sempre DELEGATION: metas do mês precisam de R$.
export const travaDoTudo = giver => motivoDasChaves(giver, CHAVES_DO_TUDO);
