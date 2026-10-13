import { nextTick, onBeforeUnmount, watch } from 'vue';

// #1423 — foco preso na gaveta (TK-02): ao abrir, o foco vai para ela; Tab e
// Shift+Tab giram dentro; ao fechar (ou desmontar), volta para onde estava.
// Com um diálogo aberto por cima, quem cuida do foco é o diálogo.
const FOCAVEIS = [
  'button:not([disabled])',
  '[href]',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

export const useFocoPreso = ({ raiz, mostrar }) => {
  let anterior = null;

  watch(
    mostrar,
    async aberta => {
      if (aberta) {
        anterior =
          document.activeElement instanceof HTMLElement
            ? document.activeElement
            : null;
        await nextTick();
        if (mostrar.value) raiz.value?.focus();
        return;
      }
      if (anterior?.isConnected) anterior.focus();
      anterior = null;
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    if (mostrar.value && anterior?.isConnected) anterior.focus();
  });

  const prender = evento => {
    if (evento.key !== 'Tab' || document.querySelector('dialog[open]')) return;
    const lista = Array.from(
      raiz.value?.querySelectorAll(FOCAVEIS) || []
    ).filter(el => el.getClientRects().length > 0);
    if (!lista.length) {
      evento.preventDefault();
      raiz.value?.focus();
      return;
    }
    const primeiro = lista[0];
    const ultimo = lista[lista.length - 1];
    const ativo = document.activeElement;
    if (evento.shiftKey && (ativo === primeiro || ativo === raiz.value)) {
      evento.preventDefault();
      ultimo.focus();
    } else if (!evento.shiftKey && ativo === ultimo) {
      evento.preventDefault();
      primeiro.focus();
    }
  };

  return { prender };
};
