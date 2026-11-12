import { ref } from 'vue';
import { useOpcoesDaConta } from '../useOpcoesDaConta';

// #2744: o aviso "a conta não tem campo personalizado" só vale com a lista
// carregada. O estado sai da flag da store: carregando, falhou ou carregou.
const flags = ref({ isFetching: false, fetchFailed: false });
const dispatch = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: nome => {
    if (nome === 'attributes/getUIFlags') return flags;
    if (nome === 'attributes/getAttributesByModel') return ref(() => []);
    return ref([]);
  },
}));
vi.mock('dashboard/api/autonomia/automacoes', () => ({
  default: { agentesDeIa: vi.fn().mockResolvedValue({ data: {} }) },
}));
vi.mock('dashboard/api/emailLists', () => ({
  default: { index: vi.fn().mockResolvedValue({ data: [] }) },
}));

describe('useOpcoesDaConta: estado dos campos personalizados', () => {
  beforeEach(() => {
    flags.value = { isFetching: false, fetchFailed: false };
  });

  it('antes de pedir a lista, carregando (nunca "a conta não tem")', () => {
    const { opcoes } = useOpcoesDaConta();
    expect(opcoes.value.atributosEstado).toBe('carregando');
  });

  it('pedida e chegando, carregando; chegou, carregou', () => {
    const { opcoes, carregarOpcoes } = useOpcoesDaConta();
    carregarOpcoes();
    expect(dispatch).toHaveBeenCalledWith('attributes/get');

    flags.value = { isFetching: true, fetchFailed: false };
    expect(opcoes.value.atributosEstado).toBe('carregando');

    flags.value = { isFetching: false, fetchFailed: false };
    expect(opcoes.value.atributosEstado).toBe('carregou');
  });

  it('a lista não veio: falhou', () => {
    const { opcoes, carregarOpcoes } = useOpcoesDaConta();
    carregarOpcoes();
    flags.value = { isFetching: false, fetchFailed: true };
    expect(opcoes.value.atributosEstado).toBe('falhou');
  });
});
