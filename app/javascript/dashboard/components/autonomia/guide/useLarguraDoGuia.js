import { computed } from 'vue';
import { menuEGuia } from 'dashboard/components-next/sidebar/menuEGuia';

// #3184 — largura do Guia como coluna. Quem recolhe o menu ao abrir o Guia é o
// próprio menu (Sidebar.vue + menuEGuia.js), sem gravar preferência. Aqui só se
// calcula a largura; nada é gravado.
//
// Alvo = painel antigo (320, ou 360 em tela muito larga) + o que o menu
// devolveu ao recolher, entre 400 e 520 px. Com o menu recolhido desde antes,
// o Guia abre com 400: mais largo que o antigo, que era estreito demais.
//
// Teto: a tela do meio fica com pelo menos 320 px. Piso: o Guia nunca fica
// menor que o painel antigo (320). Quando os dois não cabem, por exemplo num
// tablet com o menu reaberto, vale o piso: é o mesmo aperto que já existia.
//
// Do tablet (768 px) para cima o Guia é uma coluna, como sempre foi. Abaixo
// disso (celular) ocupa a tela, e a largura vem do CSS.
export const TELA_COM_COLUNA = 768;
const TELA_MUITO_LARGA = 1536;
export const LARGURA_DO_GUIA = { MINIMA: 400, MAXIMA: 520 };
const PAINEL_ANTIGO = { NORMAL: 320, LARGO: 360 };
const MEIO_MINIMO = 320;

const entre = (valor, minimo, maximo) =>
  Math.min(maximo, Math.max(minimo, valor));

export const larguraDoGuia = ({ tela, menu, devolvida }) => {
  const antigo =
    tela >= TELA_MUITO_LARGA ? PAINEL_ANTIGO.LARGO : PAINEL_ANTIGO.NORMAL;
  const alvo = entre(
    antigo + devolvida,
    LARGURA_DO_GUIA.MINIMA,
    LARGURA_DO_GUIA.MAXIMA
  );
  const cabe = tela - menu - MEIO_MINIMO;
  return Math.max(PAINEL_ANTIGO.NORMAL, Math.min(alvo, cabe));
};

export const useLarguraDoGuia = ({ embutido, larguraDaTela }) => {
  const coluna = computed(
    () => !embutido && larguraDaTela.value >= TELA_COM_COLUNA
  );

  const largura = computed(() =>
    larguraDoGuia({
      tela: larguraDaTela.value,
      menu: menuEGuia.largura.value,
      devolvida: menuEGuia.devolvida.value,
    })
  );

  const estilo = computed(() =>
    coluna.value ? { width: `${largura.value}px` } : {}
  );

  return { coluna, largura, estilo };
};
