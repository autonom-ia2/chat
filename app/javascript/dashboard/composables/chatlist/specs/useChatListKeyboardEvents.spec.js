import { ref } from 'vue';
import { useChatListKeyboardEvents } from '../useChatListKeyboardEvents';

// #2211 — Alt+J/K navega a lista; com a busca da lista aberta, a lista fica escondida (v-show)
// e o atalho não abre conversa que a pessoa não está vendo.
const atalhos = vi.hoisted(() => ({ mapa: null }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: mapa => {
    atalhos.mapa = mapa;
  },
}));

const montarLista = () => {
  const raiz = document.createElement('div');
  raiz.className = 'conversations-list';
  raiz.innerHTML = `<div class="conversations-list">
    <div class="conversation active"></div><div class="conversation"></div>
  </div>`;
  const [primeira, segunda] = raiz.querySelectorAll('div.conversation');
  primeira.click = vi.fn();
  segunda.click = vi.fn();
  return { raiz, segunda };
};

describe('useChatListKeyboardEvents', () => {
  it('Alt+K abre a próxima conversa da lista', () => {
    const { raiz, segunda } = montarLista();
    useChatListKeyboardEvents(ref(raiz));
    atalhos.mapa['Alt+KeyK'].action();
    expect(segunda.click).toHaveBeenCalledTimes(1);
  });

  it('lista escondida pela busca: Alt+J/K não fazem nada', () => {
    const { raiz, segunda } = montarLista();
    raiz.style.display = 'none';
    useChatListKeyboardEvents(ref(raiz));
    atalhos.mapa['Alt+KeyK'].action();
    atalhos.mapa['Alt+KeyJ'].action();
    expect(segunda.click).not.toHaveBeenCalled();
  });
});
