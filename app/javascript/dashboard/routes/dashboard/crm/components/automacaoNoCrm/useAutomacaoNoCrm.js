import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { criarFonteFalsa } from './fonteDasAutomacoes';

// #2414 F6.3/F6.5 e #2710 — a flag do protótipo, a fonte dos dados e o "abrir
// o card ganho" do selo "Já é cliente" (no quadro e no card aberto).
export const useAutomacaoNoCrmLigada = () => {
  const { isCloudFeatureEnabled } = useAccount();
  return computed(() => isCloudFeatureEnabled(FEATURE_FLAGS.AUTOMACAO_NO_CRM));
};

export const useFonteDasAutomacoes = () => {
  const { t } = useI18n();
  const route = useRoute();
  return criarFonteFalsa({ t, vazio: route.query.demo === 'vazio' });
};

export const useCardGanho = fonte => {
  const { t } = useI18n();
  const abrindo = ref(false);
  const semCompra = () => useAlert(t('AUTOMACAO_NO_CRM.CLIENTE.SEM_COMPRA'));

  const achar = async cliente => {
    if (abrindo.value || !cliente) return null;
    abrindo.value = true;
    try {
      const id = await fonte.cardGanho(cliente);
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
