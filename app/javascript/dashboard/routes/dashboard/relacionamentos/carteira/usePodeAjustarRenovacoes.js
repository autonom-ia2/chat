// #2898 — quem pode mudar onde ficam as renovações da conta. É uma escolha da
// conta inteira e mexe no funil: o servidor pede a chave de editar contatos E
// uma das chaves de funil, a de montar os funis ou a de administrar o CRM
// (`permission_granted?`: o administrador sempre passa; a função
// personalizada, só com as chaves). O agente sem função não muda. Uma regra só
// para o atalho "Ajustar renovações", o convite para escolher o funil e o
// Salvar da tela. Esconder é conforto: quem decide de verdade é o servidor, e
// quando ele diz `semPermissao` vale o que ele disse.
import { computed } from 'vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

export const CHAVE_DE_CONTATOS = 'contact_manage';
export const CHAVES_DE_FUNIL = ['crm_manage_pipelines', 'crm_admin'];

export const usePodeAjustarRenovacoes = () => {
  const editaContatos = usePermissionGranted(CHAVE_DE_CONTATOS);
  const deFunil = CHAVES_DE_FUNIL.map(chave => usePermissionGranted(chave));
  return computed(
    () => editaContatos.value && deFunil.some(chave => chave.value)
  );
};
