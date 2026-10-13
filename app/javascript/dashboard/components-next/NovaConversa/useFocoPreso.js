import { nextTick, watch } from 'vue';

// #1459 — foco preso de uma gaveta/diálogo: ao abrir, o foco entra; Tab e
// Shift+Tab dão a volta lá dentro; ao fechar, o foco volta para o botão que
// abriu. Reutilizável: recebe a raiz e o estado de aberto.
const FOCAVEIS = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'textarea:not([disabled])',
  '[contenteditable="true"]',
  '[tabindex]:not([tabindex="-1"])',
].join(',');

// Só o que está à vista conta (um campo escondido não pode ser a ponta da
// volta). Onde o navegador não sabe dizer, vale o que está no documento.
export const focaveisDe = raiz =>
  raiz
    ? [...raiz.querySelectorAll(FOCAVEIS)].filter(
        item => item.checkVisibility?.() ?? true
      )
    : [];

// O foco entra no primeiro `[data-foco]` (o campo que a pessoa vai usar) e, na
// falta dele, no título (`[data-view-title]`), para o leitor de tela anunciar.
export function useFocoPreso(raiz, aberta) {
  let quemAbriu = null;

  const prender = evento => {
    if (evento.key !== 'Tab') return;
    const itens = focaveisDe(raiz.value);
    if (!itens.length) return;
    const inicio = itens[0];
    const fim = itens.at(-1);
    const atual = document.activeElement;
    if (evento.shiftKey && (atual === inicio || !raiz.value.contains(atual))) {
      evento.preventDefault();
      fim.focus();
    } else if (!evento.shiftKey && atual === fim) {
      evento.preventDefault();
      inicio.focus();
    }
  };

  const entrar = async () => {
    await nextTick();
    const alvo =
      raiz.value?.querySelector('[data-foco]') ||
      raiz.value?.querySelector('[data-view-title]');
    alvo?.focus();
  };

  watch(aberta, estaAberta => {
    if (estaAberta) {
      quemAbriu = document.activeElement;
      entrar();
      return;
    }
    quemAbriu?.focus?.();
    quemAbriu = null;
  });

  return { prender, entrar };
}
