import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { usePermissionGranted } from 'dashboard/composables/useCanManage';
import { criarFonteFalsa } from './fonteDasAutomacoes';
import { cardGanhoDoContato } from './clienteQueAgendou';

// #2414 F6.3/F6.5 e #2710 (protótipo só da demo) — quem pode ver, a fonte dos dados e o "abrir a compra".

// Ver as automações pede `automation_view` (quem tem `automation_manage` também vê); o administrador sempre vê.
export const usePodeVerAutomacoes = () => {
  const ver = usePermissionGranted('automation_view');
  const mudar = usePermissionGranted('automation_manage');
  return computed(() => ver.value || mudar.value);
};

// `marca`: a marca do seed no funil (marcaDaDemo), ou null.
export const useFonteDasAutomacoes = marca => {
  const { t } = useI18n();
  const route = useRoute();
  return criarFonteFalsa({ t, marca, vazio: route.query.demo === 'vazio' });
};

// Erro de permissão não é falha passageira: some o painel, sem "Tentar de novo".
export const semPermissao = erro => [401, 403].includes(erro?.response?.status);

export const useCardGanho = () => {
  const { t } = useI18n();
  const abrindo = ref(false);
  const semCompra = () => useAlert(t('AUTOMACAO_NO_CRM.CLIENTE.SEM_COMPRA'));

  const achar = async cliente => {
    if (abrindo.value || !cliente) return null;
    abrindo.value = true;
    try {
      const id = await cardGanhoDoContato(cliente.contatoId);
      if (!id) semCompra();
      return id;
    } catch {
      semCompra();
      return null;
    } finally {
      abrindo.value = false;
    }
  };

  return { abrindo, achar };
};
