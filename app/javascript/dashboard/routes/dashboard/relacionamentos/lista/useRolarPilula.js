import { nextTick, watch } from 'vue';

// #2894 — quando o grupo escolhido muda (o botão do herói escolhe um grupo que
// pode estar fora da vista na fila do celular), rola a pílula dele para dentro
// da fila. `nearest` nos dois eixos: só mexe no que for preciso e não leva a
// rolagem vertical da página junto. Acha a pílula pelo `data-grupo` que a peça
// comum já põe.
const DESKTOP = '(min-width: 768px)';

export const useRolarPilula = (raiz, grupo) => {
  watch(grupo, async id => {
    await nextTick();
    // De `md` em diante a fileira quebra em linhas: nada para rolar de lado.
    if (window.matchMedia?.(DESKTOP)?.matches) return;
    const pilula = [
      ...(raiz.value?.querySelectorAll('[data-grupo]') ?? []),
    ].find(el => el.dataset.grupo === id);
    pilula?.scrollIntoView?.({ inline: 'nearest', block: 'nearest' });
  });
};
