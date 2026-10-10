import { usePermissoesDaJornada } from '../composables/usePermissoesDaJornada';

const getters = vi.hoisted(() => ({
  getCurrentUser: null,
  getCurrentAccountId: 3,
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: nome => computed(() => getters[nome]) };
});

const usuario = permissions => ({ accounts: [{ id: 3, permissions }] });

// Os links "Conectar seu WhatsApp ou outro canal" e "Escolher quem recebe" só aparecem para quem
// pode abrir a tela de destino (DECISOES.md item 8). Sem permissão, a tela pede a um administrador.
describe('usePermissoesDaJornada', () => {
  beforeEach(() => {
    window.globalConfig = {
      CRM_KANBAN_ENABLED: 'true',
      CRM_AI_ENABLED: 'true',
    };
  });

  it('lets an administrator reach both screens', () => {
    getters.getCurrentUser = usuario(['administrator']);
    const { podeConectarCanal, podeEscolherQuemRecebe } =
      usePermissoesDaJornada();
    expect(podeConectarCanal.value).toBe(true);
    expect(podeEscolherQuemRecebe.value).toBe(true);
  });

  it('follows the custom role keys of each screen', () => {
    getters.getCurrentUser = usuario(['custom_role', 'inbox_manage']);
    const { podeConectarCanal, podeEscolherQuemRecebe } =
      usePermissoesDaJornada();
    expect(podeConectarCanal.value).toBe(true);
    expect(podeEscolherQuemRecebe.value).toBe(false);

    getters.getCurrentUser = usuario(['custom_role', 'crm_manage_ai']);
    const outra = usePermissoesDaJornada();
    expect(outra.podeConectarCanal.value).toBe(false);
    expect(outra.podeEscolherQuemRecebe.value).toBe(true);
  });

  it('hides both from a seat with only the agents keys', () => {
    getters.getCurrentUser = usuario(['custom_role', 'autonomia_manage']);
    const { podeConectarCanal, podeEscolherQuemRecebe } =
      usePermissoesDaJornada();
    expect(podeConectarCanal.value).toBe(false);
    expect(podeEscolherQuemRecebe.value).toBe(false);
  });

  it('hides "Escolher quem recebe" when the CRM AI is off on the install', () => {
    getters.getCurrentUser = usuario(['administrator']);
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
    const { podeEscolherQuemRecebe, crmLigado } = usePermissoesDaJornada();
    expect(podeEscolherQuemRecebe.value).toBe(false);
    expect(crmLigado.value).toBe(false);
  });

  it('tells the CRM assignment screen exists apart from the permission', () => {
    getters.getCurrentUser = usuario(['custom_role', 'autonomia_manage']);
    const { podeEscolherQuemRecebe, crmLigado } = usePermissoesDaJornada();
    expect(podeEscolherQuemRecebe.value).toBe(false);
    expect(crmLigado.value).toBe(true);
  });
});
