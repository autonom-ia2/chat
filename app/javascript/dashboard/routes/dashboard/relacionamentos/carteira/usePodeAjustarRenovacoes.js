// #2898 — quem pode mudar onde ficam as renovações da conta. É uma escolha da
// conta inteira e mexe no funil: o servidor pede as DUAS chaves, a de editar
// contatos e a de montar os funis (`permission_granted?`: o administrador
// sempre passa; a função personalizada, só com as duas). O agente sem função
// não muda. Uma regra só para o atalho "Ajustar renovações", o convite para
// escolher o funil e o Salvar da tela. Esconder é conforto: quem decide de
// verdade é o servidor.
import { computed } from 'vue';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';

export const CHAVES_PARA_AJUSTAR = ['contact_manage', 'crm_manage_pipelines'];

export const usePodeAjustarRenovacoes = () => {
  const cadaChave = CHAVES_PARA_AJUSTAR.map(chave =>
    usePermissionGranted(chave)
  );
  return computed(() => cadaChave.every(chave => chave.value));
};
