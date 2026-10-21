import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useCanManage } from 'dashboard/composables/useCanManage';
import { getUserPermissions } from 'dashboard/helper/permissionsHelper.js';

// Criar, alterar, duplicar e apagar modelo: administrador ou função
// personalizada com whatsapp_templates_manage (WhatsappTemplatePolicy, #1330).
// Quem só tem whatsapp_templates_view vê e usa em campanha. As rotas já barram
// quem não tem nenhuma das duas (modelos.routes.js).
export const PERMISSOES_PARA_VER = [
  'administrator',
  'whatsapp_templates_view',
  'whatsapp_templates_manage',
];
export const PERMISSOES_PARA_CRIAR = [
  'administrator',
  'whatsapp_templates_manage',
];
// Autorização de cobranças da Meta (#1586): quem cria modelos e quem vê os custos da conta (financial_view, #1969).
export const PERMISSOES_DA_AUTORIZACAO = [
  ...PERMISSOES_PARA_CRIAR,
  'financial_view',
  'financial_manage',
];

export function usePodeCriarModelo() {
  return useCanManage('whatsapp_templates_manage');
}

// "Usar em uma campanha" só para quem cria campanha (CampaignPolicy#create?):
// administrador ou função com campaign_manage.
export function usePodeUsarEmCampanha() {
  const usuario = useMapGetter('getCurrentUser');
  const contaId = useMapGetter('getCurrentAccountId');
  return computed(() =>
    getUserPermissions(usuario.value, contaId.value).some(permissao =>
      ['administrator', 'campaign_manage'].includes(permissao)
    )
  );
}
