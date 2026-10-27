// #2202 — com a chave lista_quem_espera, a preferência de layout expandido não vale: no
// computador, a lista nova é sempre a condensada (o CardDaConversa ao lado da conversa). No
// celular continua o de sempre: o painel força o expandido (Dashboard.vue), que é o que deixa a
// lista na tela toda e a conversa no lugar dela. A preferência salva não é apagada nem alterada;
// desligando a chave, volta como era.
import { computed } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useUISettings } from 'dashboard/composables/useUISettings';
import wootConstants from 'dashboard/constants/globals';
import { useListaNova } from './useListaNova';

export function useLayoutExpandidoDaLista() {
  const { isOnExpandedLayout } = useUISettings();
  const listaNova = useListaNova();
  const { width } = useWindowSize();
  return computed(() =>
    listaNova.value
      ? width.value <= wootConstants.SMALL_SCREEN_BREAKPOINT
      : isOnExpandedLayout.value
  );
}
