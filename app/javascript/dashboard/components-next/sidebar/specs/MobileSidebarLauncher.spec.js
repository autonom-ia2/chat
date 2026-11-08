import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import MobileSidebarLauncher from '../MobileSidebarLauncher.vue';

// #2211 — no celular, a conversa vazia ("Escrever" na busca da lista) é tela de conversa: o botão do menu
// some, como numa conversa aberta. Só com a chave lista_quem_espera; desligada, fica como na main.
const rota = { name: 'home', query: { comecar: '3' } };
const listaNova = ref(true);
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useListaNova',
  () => ({ useListaNova: () => listaNova })
);

const botao = () =>
  mount(MobileSidebarLauncher, {
    global: { stubs: { Button: true, ButtonGroup: true } },
  }).find('#mobile-sidebar-launcher');

describe('MobileSidebarLauncher com a conversa vazia (#2211)', () => {
  it('chave ligada: na conversa vazia, o botão do menu some', () => {
    listaNova.value = true;
    expect(botao().exists()).toBe(false);
  });

  it('chave desligada: ?comecar= não muda nada, o botão continua', () => {
    listaNova.value = false;
    expect(botao().exists()).toBe(true);
  });
});
