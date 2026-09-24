import { computed, onUnmounted, ref, watch } from 'vue';

// Sinal genérico e compartilhado: "existe algum painel fixo (gaveta, modal
// encaixado) aberto no canto direito da tela?" Qualquer componente que
// renderize algo `fixed ... right-0` sobre aquele canto chama
// `useFixedPanelPresence` com um `ref`/`computed` do próprio estado de
// aberto; quem precisa desviar (ex.: o lançador do Guia, #646) lê
// `isFixedPanelOpen`. Contador, não booleano: dois painéis podem coexistir
// (ex.: um se abre por cima do outro) sem que o fechamento de um apague o
// sinal do outro.
const openPanelCount = ref(0);

export const isFixedPanelOpen = computed(() => openPanelCount.value > 0);

export function useFixedPanelPresence(isOpenRef) {
  let counted = false;

  const sync = isOpen => {
    if (isOpen && !counted) {
      openPanelCount.value += 1;
      counted = true;
    } else if (!isOpen && counted) {
      openPanelCount.value -= 1;
      counted = false;
    }
  };

  watch(isOpenRef, sync, { immediate: true });
  onUnmounted(() => sync(false));
}
