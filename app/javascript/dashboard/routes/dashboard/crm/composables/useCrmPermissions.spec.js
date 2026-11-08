import { ref } from 'vue';
import {
  PLAIN_AGENT_DENIED_KEYS,
  useCrmPermissions,
} from './useCrmPermissions';

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

  // #2142 — o escopo sales_value_view do token segue a mesma regra, não o crm_admin.
  it('hasCrmPermission de sales_value_view segue a mesma regra', () => {
    expect(
      seat({ funcao: 3, chaves: ['crm_admin'] }).hasCrmPermission(
        'sales_value_view'
      )
    ).toBe(false);
    expect(
      seat({ funcao: 3, chaves: ['sales_value_view'] }).hasCrmPermission(
        'sales_value_view'
      )
    ).toBe(true);
    expect(seat().hasCrmPermission('sales_value_view')).toBe(true);
    expect(
      seat({ papel: 'administrator' }).hasCrmPermission('sales_value_view')
    ).toBe(true);
  });
});

// #2142 — o agente sem função perde no servidor as mesmas chaves; a tela não
// pode mostrar botão que vai dar 403.
describe('useCrmPermissions — agente sem função', () => {
  // Cópia de PLAIN_AGENT_DENIED_KEYS em enterprise/app/policies/crm_permissions.rb.
  // Mudou lá, muda aqui.
  const NEGADAS_NO_SERVIDOR = [
    'crm_manage_pipelines',
    'crm_manage_ai',
    'crm_admin',
    'crm_export',
  ];
  const LIBERADAS = [
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
    'crm_delete_cards',
    'crm_view_reports',
  ];

  it('nega a mesma lista do servidor', () => {
    expect([...PLAIN_AGENT_DENIED_KEYS].sort()).toEqual(
      [...NEGADAS_NO_SERVIDOR].sort()
    );
  });

  it('não libera funis, IA, admin do CRM nem exportar', () => {
    const agente = seat();
    expect(agente.canManagePipelines.value).toBe(false);
    expect(agente.canManageAi.value).toBe(false);
    expect(agente.canAdminCrm.value).toBe(false);
    expect(agente.canExportCrm.value).toBe(false);
    NEGADAS_NO_SERVIDOR.forEach(chave => {
      expect(agente.hasCrmPermission(chave)).toBe(false);
    });
  });

  it('continua vendo e mexendo nos cards como antes', () => {
    const agente = seat();
    expect(agente.canViewCrm.value).toBe(true);
    expect(agente.canManageCards.value).toBe(true);
    expect(agente.canMoveCards.value).toBe(true);
    expect(agente.canDeleteCards.value).toBe(true);
    expect(agente.canViewReports.value).toBe(true);
    LIBERADAS.forEach(chave => {
      expect(agente.hasCrmPermission(chave)).toBe(true);
    });
  });

  it('o administrador continua com tudo', () => {
    const admin = seat({ papel: 'administrator' });
    expect(admin.canManagePipelines.value).toBe(true);
    expect(admin.canManageAi.value).toBe(true);
    expect(admin.canAdminCrm.value).toBe(true);
    expect(admin.canExportCrm.value).toBe(true);
    [...NEGADAS_NO_SERVIDOR, ...LIBERADAS].forEach(chave => {
      expect(admin.hasCrmPermission(chave)).toBe(true);
    });
  });

  it('a função personalizada segue as chaves gravadas', () => {
    const comFunis = seat({
      funcao: 3,
      chaves: ['crm_view', 'crm_manage_pipelines', 'crm_manage_ai'],
    });
    expect(comFunis.canManagePipelines.value).toBe(true);
    expect(comFunis.canManageAi.value).toBe(true);
    expect(comFunis.canAdminCrm.value).toBe(false);
    expect(comFunis.canManageCards.value).toBe(false);

    const soVer = seat({ funcao: 3, chaves: ['crm_view'] });
    expect(soVer.canManagePipelines.value).toBe(false);
    expect(soVer.canManageAi.value).toBe(false);

    const crmAdmin = seat({ funcao: 3, chaves: ['crm_admin'] });
    expect(crmAdmin.canManagePipelines.value).toBe(true);
    expect(crmAdmin.canManageAi.value).toBe(true);
    expect(crmAdmin.canAdminCrm.value).toBe(true);
  });
});
