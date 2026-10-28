// Espelho de CustomRole.with_implied_permissions (enterprise/app/models/custom_role.rb, #2124): uma chave de editar
// as vendas traz crm_view, e é assim que o servidor grava e confere o alcance de quem dá (GrantGuard#reach?). Mora em
// helper/peopleAccess.js, que confere o alcance das funções em todas as telas (revisão do #2308, rodada 4).
export {
  CRM_EDITING_KEYS,
  withImpliedPermissions as comImplicadas,
} from 'dashboard/helper/peopleAccess';
