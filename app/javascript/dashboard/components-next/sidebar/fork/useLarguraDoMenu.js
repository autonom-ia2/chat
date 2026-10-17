import { computed, onMounted, ref, watch } from 'vue';
import { useEventListener, useWindowSize } from '@vueuse/core';

// Largura do menu novo (#1617): aberto em 256px, recolhido em 56px (o mínimo do provider.js), botão e atalho
// Ctrl/Cmd+\ para alternar, e recolher sozinho em tela média enquanto a pessoa não escolheu. Escreve em
// `sidebarWidth` (o mesmo ref do Sidebar.vue) e em uiSettings, como o redimensionar de sempre.
export const LARGURA_PADRAO = 256;
export const LARGURA_RECOLHIDA = 56;
// O provider.js grava 200px ao abrir pelo duplo clique na borda: no menu novo vale a largura padrão.
const LARGURA_DO_UPSTREAM = 200;
// Entre 768 e 1279 px a tela é média: sem escolha da pessoa, o menu começa recolhido.
export const TELA_MEDIA_DE = 768;
const TELA_MEDIA_ATE = 1279;

const larguraDoMenuNovo = largura =>
  !largura || largura === LARGURA_DO_UPSTREAM ? LARGURA_PADRAO : largura;

// Ctrl/Cmd+\ não vale dentro de campo de texto ou editor (a pessoa está escrevendo).
const escrevendo = alvo =>
  Boolean(
    alvo &&
      (alvo.isContentEditable ||
        ['INPUT', 'TEXTAREA', 'SELECT'].includes(alvo.tagName) ||
        alvo.closest?.('[contenteditable="true"], .ProseMirror'))
  );

export function useLarguraDoMenu({
  sidebarWidth,
  isCollapsed,
  uiSettings,
  updateUISettings,
  // Tela de trabalho (#1781): abrir e recolher ali valem só naquela visita, sem mexer na escolha salva.
  telaDeTrabalho = ref(false),
}) {
  const { width: larguraDaJanela } = useWindowSize();
  const celular = computed(() => larguraDaJanela.value < TELA_MEDIA_DE);
  // Escolha da pessoa: arrastou a borda, usou o botão ou o atalho (grava `sidebar_width`). Em tela de trabalho
  // (#1781) o botão e o atalho não gravam: abrir ou recolher ali vale só naquela visita.
  const escolheu = computed(() => Boolean(uiSettings.value?.sidebar_width));
  const anuncio = ref('');

  const automatica = () =>
    larguraDaJanela.value >= TELA_MEDIA_DE &&
    larguraDaJanela.value <= TELA_MEDIA_ATE
      ? LARGURA_RECOLHIDA
      : LARGURA_PADRAO;

  const aplicar = () => {
    sidebarWidth.value = escolheu.value
      ? larguraDoMenuNovo(uiSettings.value.sidebar_width)
      : automatica();
  };
  onMounted(aplicar);
  watch(larguraDaJanela, () => {
    if (!escolheu.value) sidebarWidth.value = automatica();
  });

  // Abriu pela borda (arrastar ou duplo clique): 200px do upstream vira a largura do menu novo.
  watch(isCollapsed, (recolhido, estava) => {
    if (recolhido || !estava) return;
    sidebarWidth.value = larguraDoMenuNovo(sidebarWidth.value);
  });

  // Largura aberta: a salva, se a pessoa deixou aberto; senão a última aberta antes de recolher.
  const larguraAberta = () => {
    const salva = uiSettings.value?.sidebar_width;
    return salva && salva > LARGURA_RECOLHIDA
      ? larguraDoMenuNovo(salva)
      : larguraDoMenuNovo(uiSettings.value?.menu_largura_aberta);
  };

  // Recolher sem gravar: o recolher sozinho das telas de trabalho não é escolha da pessoa.
  const recolherSemSalvar = () => {
    sidebarWidth.value = LARGURA_RECOLHIDA;
    anuncio.value = 'FORK_SIDEBAR.ANUNCIO_RECOLHIDO';
  };

  const alternarSemSalvar = () => {
    if (!isCollapsed.value) {
      recolherSemSalvar();
      return;
    }
    sidebarWidth.value = larguraAberta();
    anuncio.value = 'FORK_SIDEBAR.ANUNCIO_ABERTO';
  };

  const alternar = () => {
    if (telaDeTrabalho.value) {
      alternarSemSalvar();
      return;
    }
    if (isCollapsed.value) {
      const aberta = larguraDoMenuNovo(uiSettings.value?.menu_largura_aberta);
      sidebarWidth.value = aberta;
      updateUISettings({ sidebar_width: aberta });
      anuncio.value = 'FORK_SIDEBAR.ANUNCIO_ABERTO';
      return;
    }
    updateUISettings({
      sidebar_width: LARGURA_RECOLHIDA,
      menu_largura_aberta: sidebarWidth.value,
    });
    sidebarWidth.value = LARGURA_RECOLHIDA;
    anuncio.value = 'FORK_SIDEBAR.ANUNCIO_RECOLHIDO';
  };

  useEventListener(document, 'keydown', evento => {
    const comando = evento.ctrlKey || evento.metaKey;
    // Tecla segurada repete o evento: alternaria sem parar.
    if (evento.repeat) return;
    if (!comando || evento.key !== '\\' || celular.value) return;
    if (escrevendo(evento.target)) return;
    evento.preventDefault();
    alternar();
  });

  return { alternar, anuncio, celular, recolherSemSalvar, aplicar };
}
