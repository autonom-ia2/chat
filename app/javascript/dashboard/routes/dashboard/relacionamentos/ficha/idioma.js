// #2894 — o idioma do painel no formato do Intl ("pt_BR" -> "pt-BR").
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { idiomaDoPainel } from 'dashboard/components-next/conversa-canal/dataDaConversa';

export const useIdioma = () => {
  const { locale } = useI18n();
  return computed(() => idiomaDoPainel(locale?.value));
};
