import { mount } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { useAbaNumeros } from './useAbaNumeros';

// Aba Números do CRM (#1617): só com o menu novo e com a mesma regra de hoje do item Dashboard.
const estado = {
  ligado: true,
  papel: 'administrator',
  funcao: null,
  chaves: [],
  rotaAbre: true,
  porPapel: false,
};

vi.mock('dashboard/components-next/sidebar/fork/useMenuNovo', async () => {
  const { computed } = await import('vue');
  return { useMenuNovo: () => ({ ligado: computed(() => estado.ligado) }) };
});
vi.mock('dashboard/components-next/sidebar/fork/usePodeAbrir', () => ({
  usePodeAbrir: () => ({ podeAbrir: () => estado.rotaAbre }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: chave =>
    ({
      getCurrentAccountId: ref(1),
      getCurrentUser: ref({
        accounts: [{ id: 1, permissions: estado.chaves }],
      }),
      getCurrentRole: ref(estado.papel),
      getCurrentCustomRoleId: ref(estado.funcao),
      'accounts/isFeatureEnabledonAccount': ref(() => estado.porPapel),
      'accounts/getAccount': ref(() => ({ id: 1, features: {} })),
    })[chave],
}));

const mostrar = () => {
  let api;
  mount(
    defineComponent({
      setup() {
        api = useAbaNumeros();
        return () => null;
      },
    })
  );
  return api.mostrar.value;
};

describe('useAbaNumeros', () => {
  beforeEach(() => {
    Object.assign(estado, {
      ligado: true,
      papel: 'administrator',
      funcao: null,
      chaves: [],
      rotaAbre: true,
      porPapel: false,
    });
  });

  it('administrador e agente sem função veem; menu novo desligado esconde', () => {
    expect(mostrar()).toBe(true);
    estado.papel = 'agent';
    expect(mostrar()).toBe(true);
    estado.ligado = false;
    expect(mostrar()).toBe(false);
  });

  it('função personalizada precisa de crm_view_reports ou crm_admin', () => {
    Object.assign(estado, { papel: 'agent', funcao: 7, chaves: ['crm_view'] });
    expect(mostrar()).toBe(false);
    estado.chaves = ['crm_view_reports'];
    expect(mostrar()).toBe(true);
    estado.chaves = ['crm_admin'];
    expect(mostrar()).toBe(true);
  });

  it('com Números por papel (#1897), quem só trabalha no CRM também vê a aba', () => {
    Object.assign(estado, { papel: 'agent', funcao: 7, chaves: ['crm_view'] });
    estado.porPapel = true;
    expect(mostrar()).toBe(true);
    estado.chaves = ['conversation_manage'];
    expect(mostrar()).toBe(false);
  });

  it('sem a permissão da rota, a aba não aparece', () => {
    estado.rotaAbre = false;
    expect(mostrar()).toBe(false);
  });
});
