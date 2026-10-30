import { defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { useLayoutExpandidoDaLista } from '../useLayoutDaLista';

// #2202 — com a lista nova, a preferência de layout expandido não vale no computador; no celular,
// o expandido que o painel força continua. A preferência salva não é tocada.
const expandidoSalvo = ref(true);
const updateUISettings = vi.fn();
const listaNova = ref(false);
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    isOnExpandedLayout: expandidoSalvo,
    updateUISettings,
  }),
}));
vi.mock('../useListaNova', () => ({ useListaNova: () => listaNova }));

const ler = largura => {
  window.innerWidth = largura;
  let layout;
  mount(
    defineComponent({
      setup() {
        layout = useLayoutExpandidoDaLista();
        return () => h('span');
      },
    })
  );
  return layout.value;
};

describe('useLayoutExpandidoDaLista (#2202)', () => {
  const larguraOriginal = window.innerWidth;
  afterEach(() => {
    window.innerWidth = larguraOriginal;
  });

  it('chave desligada: vale o que está salvo, como na main', () => {
    listaNova.value = false;
    expandidoSalvo.value = true;
    expect(ler(1440)).toBe(true);
    expandidoSalvo.value = false;
    expect(ler(1440)).toBe(false);
  });

  it('chave ligada, no computador: condensado, sem alterar a preferência salva', () => {
    listaNova.value = true;
    expandidoSalvo.value = true;
    expect(ler(1440)).toBe(false);
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('chave ligada, no celular: o expandido de sempre (lista na tela toda)', () => {
    listaNova.value = true;
    expect(ler(390)).toBe(true);
  });

  it('desligando a chave, a preferência salva volta a valer', () => {
    listaNova.value = false;
    expandidoSalvo.value = true;
    expect(ler(1440)).toBe(true);
  });
});
