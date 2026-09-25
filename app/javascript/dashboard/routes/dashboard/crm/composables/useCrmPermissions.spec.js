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
