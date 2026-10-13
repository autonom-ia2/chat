import { nextTick, onMounted, ref, watch } from 'vue';
import { useResizeObserver } from '@vueuse/core';

// #1385 — a rolagem para o lado do quadro em miniatura, com a mesma regra do quadro do funil (FunilQuadro, PR da
// rolagem do quadro): colunas sempre; com mais de cinco, a quinta fica cortada na borda, setas de 44 px do lado em que
// há mais, aviso "mais N etapas" e a coluna em foco rola sozinha até o meio. A lógica é a mesma do FunilQuadro, de
// propósito: quando aquele PR entrar, os dois quadros passam a usar um componente só.
//
// `trilho`: ref do <ol> que rola. `foco`: getter do índice da coluna em foco (-1 sem foco). `total`: getter do número
// de colunas.
const FOLGA = 1; // o navegador arredonda a posição das colunas

export const MAX_COLUNAS_LADO_A_LADO = 5;

export function useTrilhoRolagem({ trilho, foco, total }) {
  const escondidas = ref({ antes: 0, depois: 0 });

  const itens = () => [...(trilho.value?.children || [])];
  const direitaParaEsquerda = () =>
    trilho.value && getComputedStyle(trilho.value).direction === 'rtl';

  const medir = () => {
    const el = trilho.value;
    if (!el) return;
    const caixa = el.getBoundingClientRect();
    const rtl = direitaParaEsquerda();
    let antes = 0;
    let depois = 0;
    itens().forEach(item => {
      const r = item.getBoundingClientRect();
      const passaEsquerda = r.left < caixa.left - FOLGA;
      const passaDireita = r.right > caixa.right + FOLGA;
      if (rtl ? passaDireita : passaEsquerda) antes += 1;
      if (rtl ? passaEsquerda : passaDireita) depois += 1;
    });
    escondidas.value = { antes, depois };
  };

  // Desloca na horizontal pela distância física, que vale em LTR e RTL.
  const deslocar = delta => {
    if (trilho.value && delta) trilho.value.scrollLeft += delta;
  };

  // A coluna em foco vai para o meio do quadro, com vizinhas dos dois lados.
  const mostrarColuna = indice => {
    const el = trilho.value;
    const item = itens()[indice];
    if (!el || !item) return;
    const caixa = el.getBoundingClientRect();
    const r = item.getBoundingClientRect();
    if (r.left >= caixa.left - FOLGA && r.right <= caixa.right + FOLGA) {
      const margem = Math.min(r.left - caixa.left, caixa.right - r.right);
      if (margem >= r.width / 2) return;
    }
    deslocar(r.left + r.width / 2 - (caixa.left + caixa.width / 2));
  };

  // A seta avança uma "página": a última coluna inteira daquele lado vai para a borda oposta, e nenhuma etapa é
  // pulada.
  const rolar = sentido => {
    const el = trilho.value;
    if (!el) return;
    const caixa = el.getBoundingClientRect();
    const rtl = direitaParaEsquerda();
    const paraDireita = rtl ? sentido === 'antes' : sentido === 'depois';
    const lista = itens().map(item => item.getBoundingClientRect());
    if (paraDireita) {
      const cortada = lista.findIndex(r => r.right > caixa.right + FOLGA);
      if (cortada < 0) return;
      const alvo = lista[Math.max(cortada - 1, 0)];
      deslocar(alvo.left - caixa.left);
    } else {
      const cortada = lista.findLastIndex(r => r.left < caixa.left - FOLGA);
      if (cortada < 0) return;
      const alvo = lista[Math.min(cortada + 1, lista.length - 1)];
      deslocar(alvo.right - caixa.right);
    }
  };

  watch(
    () => [foco(), total()],
    async () => {
      await nextTick();
      if (foco() >= 0) mostrarColuna(foco());
      medir();
    },
    { flush: 'post' }
  );

  // Se a seta em foco some (chegou ao fim), o foco passa para a do outro lado, em vez de cair no início da página.
  const setaAntes = ref(null);
  const setaDepois = ref(null);
  watch(escondidas, async (agora, antes) => {
    const ativo = document.activeElement;
    const perdeuAntes =
      antes.antes && !agora.antes && ativo === setaAntes.value;
    const perdeuDepois =
      antes.depois && !agora.depois && ativo === setaDepois.value;
    if (!perdeuAntes && !perdeuDepois) return;
    await nextTick();
    (perdeuAntes ? setaDepois.value : setaAntes.value)?.focus();
  });

  useResizeObserver(trilho, medir);
  onMounted(() => {
    if (foco() >= 0) mostrarColuna(foco());
    medir();
  });

  return { escondidas, medir, rolar, setaAntes, setaDepois };
}
