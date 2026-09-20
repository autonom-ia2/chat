import { watch, onScopeDispose } from 'vue';

const MAX_FRAMES = 20;

// A lista do menu passa da altura da tela quando um grupo grande está aberto
// (Configurações tem 17 itens). Sem isto, abrir uma página pelo endereço deixa
// o item ativo fora da área visível e o menu parece travado.
//
// O item só existe depois que o grupo termina de abrir, então procuramos por
// alguns quadros antes de desistir.
export function useScrollActiveItemIntoView(containerRef, watchSource) {
  let pendingFrame = null;

  const isInView = (item, container) => {
    const { top: itemTop, bottom: itemBottom } = item.getBoundingClientRect();
    const { top: areaTop, bottom: areaBottom } =
      container.getBoundingClientRect();
    return itemTop >= areaTop && itemBottom <= areaBottom;
  };

  const scrollActiveIntoView = (framesLeft = MAX_FRAMES) => {
    const container = containerRef.value;
    const active = container?.querySelector('a.active');

    if (!container || !active) {
      if (framesLeft > 0) {
        pendingFrame = requestAnimationFrame(() =>
          scrollActiveIntoView(framesLeft - 1)
        );
      }
      return;
    }

    if (isInView(active, container)) return;

    active.scrollIntoView({ block: 'nearest' });
    // O grupo pode continuar crescendo depois do primeiro ajuste.
    if (framesLeft > 0 && !isInView(active, container)) {
      pendingFrame = requestAnimationFrame(() =>
        scrollActiveIntoView(framesLeft - 1)
      );
    }
  };

  watch(
    watchSource,
    () => {
      if (pendingFrame) cancelAnimationFrame(pendingFrame);
      scrollActiveIntoView();
    },
    { immediate: true, flush: 'post' }
  );

  onScopeDispose(() => {
    if (pendingFrame) cancelAnimationFrame(pendingFrame);
  });

  return { scrollActiveIntoView };
}
