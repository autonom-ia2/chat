import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

// Três tamanhos, do menor ao maior. Começa no do meio, maior que o do resto do painel: quem lê a Central
// muitas vezes tem dificuldade com letra miúda. A escolha fica no perfil e vale em todos os aparelhos.
export const TAMANHOS = ['normal', 'grande', 'maior'];
export const TAMANHO_PADRAO = 'grande';
const CHAVE = 'central_de_ajuda_letra';

const CLASSES = {
  normal: 'prose-base',
  grande: 'prose-lg',
  maior: 'prose-xl',
};

export function useTamanhoDaLetra() {
  const { uiSettings, updateUISettings } = useUISettings();

  const tamanho = computed(() =>
    TAMANHOS.includes(uiSettings.value?.[CHAVE])
      ? uiSettings.value[CHAVE]
      : TAMANHO_PADRAO
  );
  const indice = computed(() => TAMANHOS.indexOf(tamanho.value));

  const mudar = passo => {
    const novo = TAMANHOS[indice.value + passo];
    if (novo) updateUISettings({ [CHAVE]: novo });
  };

  return {
    tamanho,
    classe: computed(() => CLASSES[tamanho.value]),
    podeDiminuir: computed(() => indice.value > 0),
    podeAumentar: computed(() => indice.value < TAMANHOS.length - 1),
    diminuir: () => mudar(-1),
    aumentar: () => mudar(1),
  };
}
