import { ref } from 'vue';
import {
  useLevarAteLa,
  ESPERA_DO_DESTAQUE_MS,
} from 'dashboard/composables/useLevarAteLa';

const push = vi.fn();
const resolve = vi.fn();
const show = vi.fn();
const recursoLigado = ref(true);

vi.mock('vue-router', () => ({ useRouter: () => ({ push, resolve }) }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter =>
    getter === 'getCurrentAccountId' ? ref(7) : ref(() => recursoLigado.value),
}));
vi.mock('dashboard/store/modules/guideHighlight', () => ({
  useGuideHighlight: () => ({ show }),
}));

describe('useLevarAteLa', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    push.mockClear();
    show.mockClear();
    resolve.mockReturnValue({ matched: [{}] });
    recursoLigado.value = true;
  });

  afterEach(() => vi.useRealTimers());

  it('leva até a tela e acende o destaque depois que ela abre', () => {
    const { levar } = useLevarAteLa();

    expect(
      levar({ rota: 'profile_settings_index', destaque: 'perfil-foto' })
    ).toBe(true);
    expect(push).toHaveBeenCalledWith({
      name: 'profile_settings_index',
      params: {},
    });
    expect(show).not.toHaveBeenCalled();
    vi.advanceTimersByTime(ESPERA_DO_DESTAQUE_MS);
    expect(show).toHaveBeenCalledWith('perfil-foto');
  });

  it('não leva para rota fora da lista do Guia', () => {
    const { destino, levar } = useLevarAteLa();

    expect(destino('rota_que_nao_existe')).toBeNull();
    expect(levar({ rota: 'rota_que_nao_existe' })).toBe(false);
    expect(push).not.toHaveBeenCalled();
  });

  it('não leva quando o recurso da tela está desligado na conta', () => {
    recursoLigado.value = false;

    expect(useLevarAteLa().destino('agent_list')).toBeNull();
  });

  it('não leva quando a rota não resolve no roteador', () => {
    resolve.mockReturnValue({ matched: [] });

    expect(useLevarAteLa().destino('profile_settings_index')).toBeNull();
  });
});
