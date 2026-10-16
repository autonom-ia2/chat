import { mount } from '@vue/test-utils';
import { defineComponent, nextTick, reactive } from 'vue';
import { useSoComMenuNovo } from '../useSoComMenuNovo';

// settings_inicio pelo endereço com a flag desligada (#1617): espera a conta e manda para settings_home.
const estado = reactive({ conta: null, flags: [] });
const replace = vi.fn();

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ replace }),
}));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      get 'accounts/getAccount'() {
        return id => (estado.conta?.id === id ? estado.conta : undefined);
      },
      get 'accounts/isFeatureEnabledonAccount'() {
        return (id, flag) =>
          estado.conta?.id === id && estado.flags.includes(flag);
      },
    },
  }),
}));

const montar = () =>
  mount(defineComponent({ setup: useSoComMenuNovo, template: '<div />' }));

describe('useSoComMenuNovo', () => {
  beforeEach(() => {
    replace.mockClear();
    estado.conta = null;
    estado.flags = [];
  });

  it('flag desligada: depois que a conta carrega, vai para settings_home', async () => {
    montar();
    expect(replace).not.toHaveBeenCalled();
    estado.conta = { id: 1 };
    await nextTick();
    expect(replace).toHaveBeenCalledWith({
      name: 'settings_home',
      params: { accountId: '1' },
    });
  });

  it('flag ligada: fica na página', async () => {
    estado.conta = { id: 1 };
    estado.flags = ['menu_lateral_novo'];
    montar();
    await nextTick();
    expect(replace).not.toHaveBeenCalled();
  });
});
