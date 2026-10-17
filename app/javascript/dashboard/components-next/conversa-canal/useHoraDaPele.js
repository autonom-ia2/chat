// Com a pele (#1702) a hora do balão é só "14:32", como no app, no fuso da conta.
// Sem pele devolve vazio e a hora segue no formato de sempre.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFuso, usePele } from './pele';
import { horaDaMensagem, idiomaDoPainel } from './dataDaConversa';

export const useHoraDaPele = criadaEm => {
  const pele = usePele();
  const fuso = useFuso();
  const { locale } = useI18n();

  return computed(() => {
    if (!pele.value || !criadaEm.value) return '';
    return horaDaMensagem(
      criadaEm.value,
      fuso.value,
      idiomaDoPainel(locale.value)
    );
  });
};
