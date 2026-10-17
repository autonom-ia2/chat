import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import {
  useEventListener,
  usePreferredReducedMotion,
  useResizeObserver,
} from '@vueuse/core';

// O menu não rola sozinho (#1781): quando há itens fora da área visível, a borda esmaece e uma pílula flutuante
// "3 itens abaixo"/"2 itens acima" rola uma tela (suave; instantâneo com movimento reduzido). Na primeira vez que
// cada pílula aparece numa tela, o chevron "respira" dois ciclos; com movimento reduzido nada se mexe.
const FOLGA = 4;
const SOBRA = 48;
const MEIO_CICLO = 350;
const MEIOS_CICLOS = 4;
// Itens de topo: os da lista principal e os de cada grupo (os filhos de um grupo aberto não contam).
const ITENS_DE_TOPO =
  ':scope > div > ul > li, :scope > div > section > ul > li';

export function useSetasDeRolagem(caixa, conteudo, chaveDaTela = () => '') {
  const acima = ref(false);
  const abaixo = ref(false);
  const itensAcima = ref(0);
  const itensAbaixo = ref(0);
  const respirando = ref({ acima: false, abaixo: false });
  const movimento = usePreferredReducedMotion();
  const reduzido = computed(() => movimento.value === 'reduce');

  const contar = el => {
    const { top, bottom } = el.getBoundingClientRect();
    let emCima = 0;
    let embaixo = 0;
    el.querySelectorAll(ITENS_DE_TOPO).forEach(item => {
      const caixaDoItem = item.getBoundingClientRect();
      if (!caixaDoItem.height) return;
      if (caixaDoItem.top < top - FOLGA) emCima += 1;
      if (caixaDoItem.bottom > bottom + FOLGA) embaixo += 1;
    });
    itensAcima.value = emCima;
    itensAbaixo.value = embaixo;
  };

  const medir = () => {
    const el = caixa.value;
    if (!el) return;
    acima.value = el.scrollTop > FOLGA;
    abaixo.value = el.scrollTop + el.clientHeight < el.scrollHeight - FOLGA;
    contar(el);
  };

  useEventListener(caixa, 'scroll', medir, { passive: true });
  useResizeObserver(caixa, medir);
  useResizeObserver(conteudo, medir);
  onMounted(medir);

  // Respiro: uma vez por pílula em cada entrada na tela.
  let jaRespirou = { acima: false, abaixo: false };
  const relogios = { acima: null, abaixo: null };
  const pararRespiro = lado => {
    clearInterval(relogios[lado]);
    relogios[lado] = null;
    respirando.value = { ...respirando.value, [lado]: false };
  };
  const respirar = lado => {
    if (jaRespirou[lado] || reduzido.value) return;
    jaRespirou = { ...jaRespirou, [lado]: true };
    let passos = 0;
    relogios[lado] = setInterval(() => {
      passos += 1;
      if (passos > MEIOS_CICLOS) {
        pararRespiro(lado);
        return;
      }
      respirando.value = { ...respirando.value, [lado]: passos % 2 === 1 };
    }, MEIO_CICLO);
  };
  watch(acima, visivel => visivel && respirar('acima'));
  watch(abaixo, visivel => visivel && respirar('abaixo'));
  watch(chaveDaTela, () => {
    pararRespiro('acima');
    pararRespiro('abaixo');
    jaRespirou = { acima: false, abaixo: false };
    if (acima.value) respirar('acima');
    if (abaixo.value) respirar('abaixo');
  });
  onBeforeUnmount(() => {
    pararRespiro('acima');
    pararRespiro('abaixo');
  });

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
    itensAcima,
    itensAbaixo,
    respirando,
    reduzido,
    medir,
    rolarParaCima: () => rolar(-1),
    rolarParaBaixo: () => rolar(1),
  };
}
