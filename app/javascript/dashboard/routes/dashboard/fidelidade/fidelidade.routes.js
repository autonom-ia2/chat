import { frontendURL } from 'dashboard/helper/URLHelper';

// #3100 — a tela Fidelidade, item próprio em Crescer, depois de Campanhas
// (decisão D5 do Rodrigo, 23/11). Sem flag: o cartão só existe quando a conta
// cria, e ele mesmo tem pausar e ligar (docs/3100-desenho, seção 11).
// - fidelidade_index (?aba=cartao): o painel do cartão, para quem vê
//   (administrador ou fidelidade_view; fidelidade_manage também vê);
// - fidelidade_montar: criar ou mudar as regras, só para quem pode mudar;
// - fidelidade_cupom_novo: criar um cupom, também só para quem pode mudar.
// O servidor confere de novo (Fidelidade::ProgramaPolicy).
export const PERMISSOES_DA_FIDELIDADE = [
  'administrator',
  'fidelidade_view',
  'fidelidade_manage',
];
export const PERMISSOES_DE_MONTAR = ['administrator', 'fidelidade_manage'];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/fidelidade'),
    name: 'fidelidade_index',
    meta: { permissions: PERMISSOES_DA_FIDELIDADE },
    component: () => import('./pages/FidelidadePage.vue'),
  },
  {
    path: frontendURL('accounts/:accountId/fidelidade/montar'),
    name: 'fidelidade_montar',
    meta: { permissions: PERMISSOES_DE_MONTAR },
    component: () => import('./pages/MontarProgramaPage.vue'),
  },
  {
    path: frontendURL('accounts/:accountId/fidelidade/cupons/novo'),
    name: 'fidelidade_cupom_novo',
    meta: { permissions: PERMISSOES_DE_MONTAR },
    component: () => import('./pages/MontarCupomPage.vue'),
  },
];
