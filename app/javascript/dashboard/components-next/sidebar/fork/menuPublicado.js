import { shallowRef } from 'vue';

// O menu do Sidebar.vue, já com flags e permissões aplicadas, para a página inicial de Configurações (#1617)
// saber quais cartões a pessoa vê sem repetir a regra. Quem publica é o ForkSidebarNav, que está sempre
// montado quando a flag está ligada (no celular ele fica fora da tela, mas montado).
const publicado = shallowRef(null);

export const publicarMenu = itens => {
  publicado.value = itens;
};

export const useMenuPublicado = () => publicado;
