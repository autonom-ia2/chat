import { ref } from 'vue';
import { useTamanhoDaLetra } from '../composables/useTamanhoDaLetra';

const uiSettings = ref({});
const updateUISettings = vi.fn();

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));

describe('useTamanhoDaLetra', () => {
  beforeEach(() => {
    uiSettings.value = {};
    updateUISettings.mockClear();
  });

  it('começa na letra grande', () => {
    const { tamanho, classe } = useTamanhoDaLetra();

    expect(tamanho.value).toBe('grande');
    expect(classe.value).toBe('prose-lg');
  });

  it('guarda a escolha no perfil', () => {
    const { aumentar, diminuir } = useTamanhoDaLetra();

    aumentar();
    expect(updateUISettings).toHaveBeenLastCalledWith({
      central_de_ajuda_letra: 'maior',
    });

    diminuir();
    expect(updateUISettings).toHaveBeenLastCalledWith({
      central_de_ajuda_letra: 'normal',
    });
  });

  it('para nos extremos', () => {
    uiSettings.value = { central_de_ajuda_letra: 'maior' };
    const { podeAumentar, podeDiminuir, aumentar, classe } =
      useTamanhoDaLetra();

    expect(classe.value).toBe('prose-xl');
    expect(podeAumentar.value).toBe(false);
    expect(podeDiminuir.value).toBe(true);
    aumentar();
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('ignora valor desconhecido salvo no perfil', () => {
    uiSettings.value = { central_de_ajuda_letra: 'gigante' };

    expect(useTamanhoDaLetra().tamanho.value).toBe('grande');
  });
});
