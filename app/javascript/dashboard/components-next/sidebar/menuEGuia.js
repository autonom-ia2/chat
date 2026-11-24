import { onMounted, ref, watch } from 'vue';

// #3184 — o menu lateral e o Guia dividem a largura da tela.
//
// Abrir o Guia recolhe o menu, e o Guia fica com o espaço que o menu devolveu.
// O menu recolhe SEM gravar nas preferências: não foi a pessoa que escolheu.
// Gravar `sidebar_width` faria o menu novo (#1617) tratar isso como escolha e
// parar de abrir e recolher sozinho conforme a tela, e perderia a largura que
// a pessoa tinha deixado. Recarregar a página volta o menu ao que estava salvo
// (e, com o Guia aberto, recolhe de novo).
//
// Se o menu reabrir com o Guia aberto (a pessoa abriu, ou o menu novo se
// reajustou ao sair de uma tela de trabalho ou ao alargar a janela), ele não é
// recolhido de novo: brigar com o clique da pessoa é pior. O espaço devolvido
// zera e o Guia encolhe para caber.
//
// Estado de módulo, como o popover ativo do provider.js: o Guia não fica dentro
// da árvore do menu, então não alcança o provide/inject dele.
export const MENU_RECOLHIDO = 56;

export const menuEGuia = {
  // O painel do Guia está aberto como coluna (o Guia avisa; o embutido não).
  guiaAberto: ref(false),
  // #3191 — o Copiloto da equipe tem o mesmo desenho e a mesma largura do
  // Guia: aberto, ele também recolhe o menu. Um não abre junto com o outro
  // (AutonomiaCopilotContainer.vue), mas cada um avisa o seu.
  copilotoAberto: ref(false),
  // Largura do menu agora, em px. Zero no celular (o menu é gaveta por cima).
  largura: ref(0),
  // Quanto o menu devolveu ao Guia. Vale enquanto o menu continuar recolhido
  // pelo Guia.
  devolvida: ref(0),
  // O menu está recolhido porque o Guia abriu (e não por escolha ou sozinho).
  recolhidoPeloGuia: ref(false),
};

// Recolhe o menu porque o Guia abriu.
// - Celular: o menu é gaveta, nada muda.
// - Menu recolhido pelo próprio Guia (abriu, fechou, abriu de novo): mantém a
//   largura devolvida, o Guia não pula de tamanho.
// - Menu recolhido por outro motivo: nada foi devolvido.
export const recolherParaOGuia = ({ sidebarWidth, recolhido, celular }) => {
  if (celular) return;
  if (recolhido) {
    if (!menuEGuia.recolhidoPeloGuia.value) menuEGuia.devolvida.value = 0;
    return;
  }
  menuEGuia.devolvida.value = Math.max(0, sidebarWidth.value - MENU_RECOLHIDO);
  menuEGuia.recolhidoPeloGuia.value = true;
  sidebarWidth.value = MENU_RECOLHIDO;
};

// Liga o menu ao Guia: publica a largura e recolhe quando o Guia abre. Também
// ao montar, depois que o menu novo aplicou a largura salva (o onMounted do
// filho roda antes do do Sidebar.vue), e ao sair do celular com o Guia aberto.
export const useMenuRecolheComOGuia = ({
  sidebarWidth,
  isCollapsed,
  celular,
}) => {
  watch(
    [sidebarWidth, celular],
    ([largura, ehCelular]) => {
      menuEGuia.largura.value = ehCelular ? 0 : largura;
      if (ehCelular || isCollapsed.value) return;
      // Menu aberto de novo: não devolve mais nada ao Guia.
      menuEGuia.devolvida.value = 0;
      menuEGuia.recolhidoPeloGuia.value = false;
    },
    { immediate: true }
  );

  const recolherSeOGuiaAbriu = () => {
    if (!menuEGuia.guiaAberto.value && !menuEGuia.copilotoAberto.value) return;
    recolherParaOGuia({
      sidebarWidth,
      recolhido: isCollapsed.value,
      celular: celular.value,
    });
  };
  watch(
    [menuEGuia.guiaAberto, menuEGuia.copilotoAberto, celular],
    recolherSeOGuiaAbriu
  );
  onMounted(recolherSeOGuiaAbriu);
};
