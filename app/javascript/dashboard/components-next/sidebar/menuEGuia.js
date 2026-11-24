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
// Estado de módulo, como o popover ativo do provider.js: o Guia não fica dentro
// da árvore do menu, então não alcança o provide/inject dele.
export const MENU_RECOLHIDO = 56;

export const menuEGuia = {
  // O painel do Guia está aberto como coluna (o Guia avisa; o embutido não).
  guiaAberto: ref(false),
  // Largura do menu agora, em px. Zero no celular (o menu é gaveta por cima).
  largura: ref(0),
  // Quanto o menu devolveu da última vez que recolheu por causa do Guia.
  devolvida: ref(0),
};

// Recolhe o menu porque o Guia abriu. Menu já recolhido ou celular: nada muda,
// e a última largura devolvida continua valendo (o Guia mantém a largura).
export const recolherParaOGuia = ({ sidebarWidth, recolhido, celular }) => {
  if (celular || recolhido) return;
  menuEGuia.devolvida.value = Math.max(0, sidebarWidth.value - MENU_RECOLHIDO);
  sidebarWidth.value = MENU_RECOLHIDO;
};

// Liga o menu ao Guia: publica a largura e recolhe quando o Guia abre. Também
// ao montar, depois que o menu novo aplicou a largura salva (o onMounted do
// filho roda antes do do Sidebar.vue).
export const useMenuRecolheComOGuia = ({
  sidebarWidth,
  isCollapsed,
  celular,
}) => {
  watch(
    [sidebarWidth, celular],
    ([largura, ehCelular]) => {
      menuEGuia.largura.value = ehCelular ? 0 : largura;
    },
    { immediate: true }
  );

  const recolherSeOGuiaAbriu = () => {
    if (!menuEGuia.guiaAberto.value) return;
    recolherParaOGuia({
      sidebarWidth,
      recolhido: isCollapsed.value,
      celular: celular.value,
    });
  };
  watch(menuEGuia.guiaAberto, recolherSeOGuiaAbriu);
  onMounted(recolherSeOGuiaAbriu);
};
