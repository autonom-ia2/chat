import { nextTick, watch } from 'vue';

// Foco de teclado no menu novo (#1781): recolher ou abrir troca os itens pelos ícones do trilho (e vice-versa), e a
// seta de rolagem some quando chega na ponta. Nos dois casos o foco não pode cair no <body>.
const perdido = () =>
  !document.activeElement?.isConnected ||
  document.activeElement === document.body;

const focavel = el => el?.querySelector('a[href], button');

// Os itens de topo aparecem na mesma ordem no menu aberto e no trilho: lista principal, grupos e rodapé.
export function useFocoAoAlternar({ raiz, idDaLista, isCollapsed }) {
  const itens = () => [
    ...(raiz.value?.querySelectorAll(
      `#${idDaLista} > div > ul > li, #${idDaLista} > div > section > ul > li, [data-menu-rodape] > li`
    ) || []),
  ];
  let posicao = -1;

  watch(
    isCollapsed,
    () => {
      const ativo = document.activeElement;
      posicao = raiz.value?.contains(ativo)
        ? itens().findIndex(li => li.contains(ativo))
        : -1;
    },
    { flush: 'pre' }
  );

  watch(
    isCollapsed,
    () => {
      if (posicao < 0 || !perdido()) return;
      const alvo =
        focavel(itens()[posicao]) ||
        raiz.value?.querySelector('[data-recolher-menu]');
      alvo?.focus();
      posicao = -1;
    },
    { flush: 'post' }
  );
}

// Seta focada que some: o foco vai para a seta do outro lado, se houver, ou para a lista.
export function useFocoDasSetas({ raiz, lista, acima, abaixo }) {
  const focadaSome = lado => async visivel => {
    if (visivel) return;
    const ativo = document.activeElement;
    if (ativo?.getAttribute?.('data-seta') !== lado) return;
    await nextTick();
    const outra = raiz.value?.querySelector(
      `[data-seta="${lado === 'acima' ? 'abaixo' : 'acima'}"]`
    );
    (outra || lista.value)?.focus();
  };
  watch(acima, focadaSome('acima'), { flush: 'pre' });
  watch(abaixo, focadaSome('abaixo'), { flush: 'pre' });
}
