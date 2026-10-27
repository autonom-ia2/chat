import { mount, enableAutoUnmount } from '@vue/test-utils';
import { ref } from 'vue';
import { pedidoDeFoco, useAtalhoDaBusca } from '../atalhoDaBusca';

// #2211 — ⌘/Ctrl+K foca o campo da lista; de outra tela, abre Conversas. Sem a chave, nada muda.
const push = vi.fn();
const ligada = ref(true);
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(1),
}));
vi.mock('../../useListaNova', () => ({ useListaNova: () => ligada }));

enableAutoUnmount(afterEach);

const montar = () =>
  mount({ template: '<div />', setup: () => useAtalhoDaBusca() });

const apertar = (extras = {}) => {
  const evento = new KeyboardEvent('keydown', {
    code: 'KeyK',
    key: 'k',
    metaKey: true,
    bubbles: true,
    cancelable: true,
    ...extras,
  });
  document.body.dispatchEvent(evento);
  return evento;
};

describe('useAtalhoDaBusca', () => {
  beforeEach(() => {
    push.mockReset();
    ligada.value = true;
    document.body.innerHTML = '';
  });

  it('com o campo na tela, pede foco e não troca de tela', () => {
    document.body.innerHTML = '<input data-campo-da-busca />';
    montar();
    const antes = pedidoDeFoco.value;
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(true);
    expect(pedidoDeFoco.value).toBe(antes + 1);
    expect(push).not.toHaveBeenCalled();
  });

  it('de outra tela, abre Conversas (o campo foca quando montar)', () => {
    montar();
    apertar({ metaKey: false, ctrlKey: true });
    expect(push).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: 1 },
    });
  });

  it('sem a chave lista_quem_espera, não mexe no ⌘K', () => {
    ligada.value = false;
    montar();
    const evento = apertar();
    expect(evento.defaultPrevented).toBe(false);
    expect(push).not.toHaveBeenCalled();
  });

  it('⌘⇧K não é o atalho', () => {
    montar();
    expect(apertar({ shiftKey: true }).defaultPrevented).toBe(false);
  });
});
