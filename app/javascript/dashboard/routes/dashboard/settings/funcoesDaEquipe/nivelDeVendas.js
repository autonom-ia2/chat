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
const CRM_ADMIN = 'crm_admin';
export const TUDO = 'tudo';
export const NIVEIS_DE_VENDAS = [LEVELS.NONE, LEVELS.VIEW, LEVELS.MANAGE, TUDO];
export const CHAVES_DO_TUDO = [CRM_ADMIN, ...CRM_EXTRAS_IMPLIED_BY_ADMIN];

const vendas = () => moduleByKey('CRM');

export const nivelDeVendas = permissions =>
  permissions.includes(CRM_ADMIN) ? TUDO : getLevel(vendas(), permissions);

// Sair de "Cuida de tudo" tira o crm_admin e as seis que vieram com ele: voltar a "Pode mexer" não deixa as
// planilhas e as metas ligadas sem a pessoa ver.
export const escolherNivelDeVendas = (nivel, permissions) => {
  if (nivel === TUDO)
    return permissions.includes(CRM_ADMIN)
      ? permissions
      : toggleExtra(vendas(), CRM_ADMIN, permissions);
  const semTudo = permissions.includes(CRM_ADMIN)
    ? permissions.filter(chave => !CHAVES_DO_TUDO.includes(chave))
    : permissions;
  return setLevel(vendas(), nivel, semTudo);
};

// Para quem não é administrador nem tem grant_above_own, sempre DELEGATION: metas do mês precisam de R$.
export const travaDoTudo = giver => motivoDasChaves(giver, CHAVES_DO_TUDO);
