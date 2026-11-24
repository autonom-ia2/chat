import { computed, watch } from 'vue';
import { LARGURAS_DO_MENU } from 'dashboard/components-next/sidebar/provider';

// #3184 — no computador, abrir o Guia recolhe o menu lateral, e o espaço que o
// menu devolve vai para o Guia: a tela do meio não cresce nem encolhe. Fechar
// o Guia não reabre o menu (pedido do Rodrigo).
//
// Largura = a do painel antigo + o que o menu devolveu, entre 400 e 520 px.
// Ela fica gravada nas preferências: recarregar com o Guia aberto (e o menu já
// recolhido) mantém a mesma largura.
//
// Do tablet (768 px) para cima o Guia é uma coluna, como sempre foi. Numa
// tela estreita a largura guardada encolhe para a tela do meio não ficar com
// menos de 320 px; o Guia nunca fica menor que o painel antigo. Abaixo de
// 768 px (celular) o Guia ocupa a tela e o menu fica como está.
export const TELA_COM_COLUNA = 768;
const TELA_MUITO_LARGA = 1536;
export const LARGURA_DO_GUIA = { MINIMA: 400, MAXIMA: 520 };
const PAINEL_ANTIGO = { NORMAL: 320, LARGO: 360 };
const MEIO_MINIMO = 320;

const entre = (valor, minimo, maximo) =>
  Math.min(maximo, Math.max(minimo, valor));

export const larguraAoAbrir = ({ menu, tela }) => {
  const antigo =
    tela >= TELA_MUITO_LARGA ? PAINEL_ANTIGO.LARGO : PAINEL_ANTIGO.NORMAL;
  const devolvido = Math.max(0, menu - LARGURAS_DO_MENU.RECOLHIDO);
  return entre(
    antigo + devolvido,
    LARGURA_DO_GUIA.MINIMA,
    LARGURA_DO_GUIA.MAXIMA
  );
};

export const useLarguraDoGuia = ({
  aberto,
  embutido,
  larguraDaTela,
  uiSettings,
  updateUISettings,
}) => {
  const telaLarga = computed(() => larguraDaTela.value >= TELA_COM_COLUNA);

  // A guardada, encolhida ao que a tela comporta com o menu do jeito que está.
  const largura = computed(() => {
    const guardada =
      uiSettings.value.autonomia_guide_width || LARGURA_DO_GUIA.MINIMA;
    const menu = uiSettings.value.sidebar_width || LARGURAS_DO_MENU.PADRAO;
    const cabe = larguraDaTela.value - menu - MEIO_MINIMO;
    return Math.max(PAINEL_ANTIGO.NORMAL, Math.min(guardada, cabe));
  });

  watch(
    aberto,
    abriu => {
      if (!abriu || embutido || !telaLarga.value) return;
      const menu = uiSettings.value.sidebar_width || LARGURAS_DO_MENU.PADRAO;
      // Menu já recolhido: nada a devolver, fica a largura guardada.
      if (menu < LARGURAS_DO_MENU.LIMITE_RECOLHIDO) return;
      updateUISettings({
        sidebar_width: LARGURAS_DO_MENU.RECOLHIDO,
        autonomia_guide_width: larguraAoAbrir({
          menu,
          tela: larguraDaTela.value,
        }),
      });
    },
    { immediate: true }
  );

  // Só a partir do tablet o Guia é uma coluna com largura própria.
  const estilo = computed(() =>
    !embutido && telaLarga.value ? { width: `${largura.value}px` } : {}
  );

  return { telaLarga, largura, estilo };
};
