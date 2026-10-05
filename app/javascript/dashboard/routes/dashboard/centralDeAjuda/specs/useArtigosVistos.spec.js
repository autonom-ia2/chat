import { ref } from 'vue';
import {
  useArtigosVistos,
  LIMITE_DE_VISTOS,
} from '../composables/useArtigosVistos';

const uiSettings = ref({});
const updateUISettings = vi.fn();

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings, updateUISettings }),
}));

describe('useArtigosVistos', () => {
  beforeEach(() => {
    uiSettings.value = {};
    updateUISettings.mockClear();
  });

  it('começa sem nada visto', () => {
    const { vistos, foiVisto } = useArtigosVistos();

    expect(vistos.value.size).toBe(0);
    expect(foiVisto('10.01')).toBe(false);
  });

  it('marca no perfil, com o mais novo no fim', () => {
    uiSettings.value = { central_de_ajuda_vistos: ['00.01'] };
    const { marcarVisto } = useArtigosVistos();

    marcarVisto('10.01');

    expect(updateUISettings).toHaveBeenCalledWith({
      central_de_ajuda_vistos: ['00.01', '10.01'],
    });
  });

  it('não grava de novo o que já foi visto', () => {
    uiSettings.value = { central_de_ajuda_vistos: ['10.01'] };
    const { marcarVisto, foiVisto } = useArtigosVistos();

    expect(foiVisto('10.01')).toBe(true);
    marcarVisto('10.01');
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('ignora id vazio', () => {
    useArtigosVistos().marcarVisto(undefined);

    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('descarta os mais antigos ao passar do limite', () => {
    const cheios = Array.from({ length: LIMITE_DE_VISTOS }, (_, i) => `a${i}`);
    uiSettings.value = { central_de_ajuda_vistos: cheios };

    useArtigosVistos().marcarVisto('10.01');

    const salvo = updateUISettings.mock.calls[0][0].central_de_ajuda_vistos;
    expect(salvo).toHaveLength(LIMITE_DE_VISTOS);
    expect(salvo[0]).toBe('a1');
    expect(salvo.at(-1)).toBe('10.01');
  });

  it('ignora valor estranho salvo no perfil', () => {
    uiSettings.value = { central_de_ajuda_vistos: 'quebrado' };
    const { vistos, marcarVisto } = useArtigosVistos();

    expect(vistos.value.size).toBe(0);
    marcarVisto('10.01');
    expect(updateUISettings).toHaveBeenCalledWith({
      central_de_ajuda_vistos: ['10.01'],
    });
  });

  it('acompanha o perfil quando ele muda', () => {
    const { foiVisto } = useArtigosVistos();

    uiSettings.value = { central_de_ajuda_vistos: ['10.02'] };

    expect(foiVisto('10.02')).toBe(true);
  });
});
