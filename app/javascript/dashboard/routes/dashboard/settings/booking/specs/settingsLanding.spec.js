// O Agendamento saiu de Configurações e foi para o CRM (#1212): função só com
// Agendamento não abre mais "Configurações"; chega pela entrada do CRM.
import settingsRoutes from '../../settings.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../../store', () => ({ default: store }));

const home = settingsRoutes.routes.find(
  route => route.name === 'settings_home'
);

describe('settings_home depois que o Agendamento foi para o CRM', () => {
  it('não aceita mais as chaves de Agendamento', () => {
    expect(home.meta.permissions).not.toContain('agendamento_view');
    expect(home.meta.permissions).not.toContain('agendamento_manage');
  });

  it('a página continua registrada, agora no endereço do CRM', () => {
    const parent = settingsRoutes.routes.find(route =>
      route.children?.some(child => child.name === 'settings_booking')
    );
    expect(parent.path).toBe('/app/accounts/:accountId/crm/booking');
  });
});
