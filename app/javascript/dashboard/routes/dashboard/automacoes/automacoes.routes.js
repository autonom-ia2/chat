import { FEATURE_FLAGS } from '../../../featureFlags';
import { frontendURL } from '../../../helper/URLHelper';

const AutomacoesInicio = () => import('./pages/AutomacoesInicio.vue');
const LivreEditorPage = () => import('./livre/pages/LivreEditorPage.vue');
const AutomacaoConversaPage = () => import('./pages/AutomacaoConversaPage.vue');

// #859 — Automações no menu principal. As mesmas permissões do modo manual
// (settings/automation): quem vê a lista lá, vê aqui. Criar exige `_manage`.
//
// `guiaEmbutido`: a tela traz a conversa do Guia dentro dela, então o painel
// lateral e o lançador flutuante ficam escondidos.
const VER = ['administrator', 'automation_view', 'automation_manage'];
const MUDAR = ['administrator', 'automation_manage'];

// #2414 F5 — com automacao_editor ligada, a lista vira a lista única e as
// automações novas abrem no editor gerado do catálogo. Desligada, tudo como hoje.
const EDITOR = FEATURE_FLAGS.AUTOMACAO_EDITOR;

export const routes = [
  {
    path: frontendURL('accounts/:accountId/automacoes'),
    name: 'automacoes_lista',
    component: AutomacoesInicio,
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
    path: frontendURL('accounts/:accountId/automacoes/livre/nova'),
    name: 'automacoes_livre_nova',
    component: LivreEditorPage,
    meta: { featureFlag: EDITOR, permissions: MUDAR },
  },
  {
    path: frontendURL('accounts/:accountId/automacoes/livre/:id'),
    name: 'automacoes_livre_editar',
    component: LivreEditorPage,
    meta: { featureFlag: EDITOR, permissions: VER },
  },
  // #2889 — a automação do motor novo que o Guia montou, ao lado da conversa.
  // Rota própria: os ids da Automação livre e das regras antigas se repetem.
  {
    path: frontendURL('accounts/:accountId/automacoes/guia/:id'),
    name: 'automacoes_guia_editar',
    component: AutomacaoConversaPage,
    meta: {
      featureFlag: FEATURE_FLAGS.AUTOMACAO_PORTA,
      permissions: VER,
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
