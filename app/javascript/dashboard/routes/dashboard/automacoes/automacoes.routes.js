import { FEATURE_FLAGS } from '../../../featureFlags';
import { frontendURL } from '../../../helper/URLHelper';

const AutomacoesPage = () => import('./pages/AutomacoesPage.vue');
const AutomacaoConversaPage = () => import('./pages/AutomacaoConversaPage.vue');

// #859 — Automações no menu principal. As mesmas permissões do modo manual
// (settings/automation): quem vê a lista lá, vê aqui. Criar exige `_manage`.
//
// `guiaEmbutido`: a tela traz a conversa do Guia dentro dela, então o painel
// lateral e o lançador flutuante ficam escondidos.
const VER = ['administrator', 'automation_view', 'automation_manage'];
const MUDAR = ['administrator', 'automation_manage'];

export const routes = [
  {
    path: frontendURL('accounts/:accountId/automacoes'),
    name: 'automacoes_lista',
    component: AutomacoesPage,
    meta: { featureFlag: FEATURE_FLAGS.AUTOMATIONS, permissions: VER },
  },
  {
    path: frontendURL('accounts/:accountId/automacoes/nova'),
    name: 'automacoes_nova',
    component: AutomacaoConversaPage,
    meta: {
      featureFlag: FEATURE_FLAGS.AUTOMATIONS,
      permissions: MUDAR,
      guiaEmbutido: true,
    },
  },
  {
    path: frontendURL('accounts/:accountId/automacoes/:id'),
    name: 'automacoes_editar',
    component: AutomacaoConversaPage,
    meta: {
      featureFlag: FEATURE_FLAGS.AUTOMATIONS,
      permissions: VER,
      guiaEmbutido: true,
    },
  },
];
