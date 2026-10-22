import { ref } from 'vue';
import { useCrmPermissions } from './useCrmPermissions';

const role = ref('agent');
const customRoleId = ref(null);
const permissoes = ref([]);

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({
    getCurrentUser: ref({ id: 1 }),
    getCurrentAccountId: ref(7),
    getCurrentRole: role,
    getCurrentCustomRoleId: customRoleId,
  }),
}));
vi.mock('dashboard/helper/permissionsHelper.js', () => ({
  getUserPermissions: () => permissoes.value,
}));

const seat = ({ papel = 'agent', funcao = null, chaves = [] } = {}) => {
  role.value = papel;
  customRoleId.value = funcao;
  permissoes.value = chaves;
  return useCrmPermissions();
};

// #722 — exportar a Lista é dado pessoal em lote: diferente das outras chaves do CRM,
// o agente sem função personalizada NÃO ganha por padrão.
describe('useCrmPermissions — canExportCrm', () => {
  it('libera o administrador', () => {
    expect(seat({ papel: 'administrator' }).canExportCrm.value).toBe(true);
  });

  it('não libera o agente sem função, que vê o resto do CRM', () => {
    const permissoesDoAgente = seat();
    expect(permissoesDoAgente.canViewCrm.value).toBe(true);
    expect(permissoesDoAgente.canExportCrm.value).toBe(false);
  });

  it('libera a função com crm_export', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_view', 'crm_export'] }).canExportCrm.value
    ).toBe(true);
  });

  it('libera a função com crm_admin', () => {
    expect(seat({ funcao: 3, chaves: ['crm_admin'] }).canExportCrm.value).toBe(
      true
    );
  });

  it('não libera a função só com crm_view', () => {
    expect(seat({ funcao: 3, chaves: ['crm_view'] }).canExportCrm.value).toBe(
      false
    );
  });
});

// #1874 — arquivar tem chave própria; o agente sem função continua arquivando.
describe('useCrmPermissions — canDeleteCards', () => {
  it('libera o administrador e o agente sem função', () => {
    expect(seat({ papel: 'administrator' }).canDeleteCards.value).toBe(true);
    expect(seat().canDeleteCards.value).toBe(true);
  });

  it('não libera a função que só mexe nos cards', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_view', 'crm_manage_cards'] })
        .canDeleteCards.value
    ).toBe(false);
  });

  it('libera a função com crm_delete_cards ou crm_admin', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_view', 'crm_delete_cards'] })
        .canDeleteCards.value
    ).toBe(true);
    expect(
      seat({ funcao: 3, chaves: ['crm_admin'] }).canDeleteCards.value
    ).toBe(true);
  });
});

// #2075 — valores de venda em R$: chave protegida, o crm_admin não liga.
describe('useCrmPermissions — canSeeSalesValues', () => {
  it('libera o administrador e o agente sem função', () => {
    expect(seat({ papel: 'administrator' }).canSeeSalesValues.value).toBe(true);
    expect(seat().canSeeSalesValues.value).toBe(true);
  });

  it('libera a função com sales_value_view', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_view', 'sales_value_view'] })
        .canSeeSalesValues.value
    ).toBe(true);
  });

  it('não libera a função só com crm_admin ou crm_view', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_admin'] }).canSeeSalesValues.value
    ).toBe(false);
    expect(
      seat({ funcao: 3, chaves: ['crm_view'] }).canSeeSalesValues.value
    ).toBe(false);
  });
});
