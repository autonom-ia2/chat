import { reactive, ref } from 'vue';
import { usePodeDefinirMetas } from './usePodeDefinirMetas';

// Quem abre a gaveta "Metas do mês" (#1991), a mesma régua da Crm::MetasPolicy.
const estado = reactive({
  flag: true,
  papel: 'agent',
  funcao: null,
  chaves: [],
});

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: chave =>
    ({
      getCurrentAccountId: ref(1),
      getCurrentUser: ref({
        accounts: [{ id: 1, permissions: estado.chaves }],
      }),
      getCurrentRole: ref(estado.papel),
      getCurrentCustomRoleId: ref(estado.funcao),
      'accounts/isFeatureEnabledonAccount': ref(() => estado.flag),
    })[chave],
}));

const pode = ({ flag = true, papel = 'agent', funcao = null, chaves = [] }) => {
  Object.assign(estado, { flag, papel, funcao, chaves });
  return usePodeDefinirMetas().value;
};

describe('usePodeDefinirMetas', () => {
  it('administrador e função com a chave ou crm_admin; nunca o agente sem função', () => {
    expect(pode({ papel: 'administrator' })).toBe(true);
    expect(
      pode({
        funcao: 3,
        chaves: ['crm_view', 'crm_metas_manage', 'sales_value_view'],
      })
    ).toBe(true);
    // #2075: a meta é dinheiro; sem os valores em R$, a gaveta não abre.
    expect(pode({ funcao: 3, chaves: ['crm_view', 'crm_metas_manage'] })).toBe(
      false
    );
    expect(pode({ funcao: 3, chaves: ['crm_admin', 'sales_value_view'] })).toBe(
      true
    );
    expect(pode({ funcao: 3, chaves: ['crm_admin'] })).toBe(false);
    expect(pode({ funcao: 3, chaves: ['crm_metas_manage'] })).toBe(false);
    expect(pode({})).toBe(false);
    expect(pode({ funcao: 3, chaves: ['crm_view', 'crm_view_reports'] })).toBe(
      false
    );
  });

  it('sem a flag ninguém abre', () => {
    expect(pode({ flag: false, papel: 'administrator' })).toBe(false);
  });
});
