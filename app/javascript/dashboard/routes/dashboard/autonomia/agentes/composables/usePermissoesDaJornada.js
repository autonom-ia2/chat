import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';
import { CRM_MANAGE_AI_PERMISSION } from 'dashboard/constants/permissions';

// #1181 (DECISOES.md item 8) — links para telas de fora do módulo só aparecem para quem pode
// abri-las. As listas repetem o `meta.permissions` das rotas de destino:
// settings_inbox_new (inbox.routes.js) e crm_handoff_settings_index (assignmentPolicy.routes.js,
// que também exige CRM e IA do CRM ligados na instalação).
const CONECTAR_CANAL = ['administrator', 'inbox_manage'];
const QUEM_RECEBE = ['administrator', CRM_MANAGE_AI_PERMISSION];

const crmComIaLigado = () =>
  window.globalConfig?.CRM_KANBAN_ENABLED === 'true' &&
  window.globalConfig?.CRM_AI_ENABLED === 'true';

export function usePermissoesDaJornada() {
  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');

  const permissoes = computed(() =>
    getUserPermissions(usuario.value, contaId.value)
  );

  const podeConectarCanal = computed(() =>
    hasPermissions(CONECTAR_CANAL, permissoes.value)
  );
  const podeEscolherQuemRecebe = computed(
    () => crmComIaLigado() && hasPermissions(QUEM_RECEBE, permissoes.value)
  );

  // Sem CRM e IA do CRM na instalação, a tela de Atribuição não existe: quem usa esconde o "Peça a
  // um administrador", que só faz sentido quando falta permissão.
  const crmLigado = computed(() => crmComIaLigado());

  return { podeConectarCanal, podeEscolherQuemRecebe, crmLigado };
}
