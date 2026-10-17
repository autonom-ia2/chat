import { computed, onMounted, ref } from 'vue';
import {
  useEventListener,
  usePreferredReducedMotion,
  useResizeObserver,
} from '@vueuse/core';

// O menu não rola sozinho (#1781): quando há itens fora da área visível, a borda esmaece e uma setinha
// "Mais acima"/"Mais abaixo" rola uma tela (suave; instantâneo com movimento reduzido).
const FOLGA = 4;
const SOBRA = 48;

export function useSetasDeRolagem(caixa, conteudo) {
  const acima = ref(false);
  const abaixo = ref(false);
  const movimento = usePreferredReducedMotion();
  const reduzido = computed(() => movimento.value === 'reduce');

  const medir = () => {
    const el = caixa.value;
    if (!el) return;
    acima.value = el.scrollTop > FOLGA;
    abaixo.value = el.scrollTop + el.clientHeight < el.scrollHeight - FOLGA;
  };

  useEventListener(caixa, 'scroll', medir, { passive: true });
  useResizeObserver(caixa, medir);
  useResizeObserver(conteudo, medir);
  onMounted(medir);

  const rolar = sentido => {
    const el = caixa.value;
    if (!el) return;
    const passo = Math.max(el.clientHeight - SOBRA, SOBRA);
    el.scrollBy?.({
      top: sentido * passo,
      behavior: reduzido.value ? 'auto' : 'smooth',
    });
  };

  return {
    acima,
    abaixo,
    medir,
    rolarParaCima: () => rolar(-1),
    rolarParaBaixo: () => rolar(1),
  };
}
