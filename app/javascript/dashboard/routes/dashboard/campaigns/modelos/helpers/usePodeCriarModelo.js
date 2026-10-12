import { useCanManage } from 'dashboard/composables/useCanManage';

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

export function usePodeCriarModelo() {
  return useCanManage('whatsapp_templates_manage');
}
