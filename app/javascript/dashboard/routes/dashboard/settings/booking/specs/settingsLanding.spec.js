// Função só com Agendamento (#1187, F1-D): "Configurações" leva direto para a
// tela de Agendamento, em vez de cair numa página que a função não abre.
import settingsRoutes from '../../settings.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../../store', () => ({ default: store }));

const home = settingsRoutes.routes.find(
  route => route.name === 'settings_home'
);

const seat = permissions => {
  store.getters.getCurrentRole = 'agent';
  store.getters.getCurrentCustomRoleId = 7;
  store.getters.getCurrentUser = {
    accounts: [{ id: 9, custom_role_id: 7, permissions }],
  };
};

describe('settings_home com função de Agendamento', () => {
  it('aceita as chaves de Agendamento', () => {
    expect(home.meta.permissions).toEqual(
      expect.arrayContaining(['agendamento_view', 'agendamento_manage'])
    );
  });

  it.each(['agendamento_view', 'agendamento_manage'])(
    'função só com %s abre settings_booking',
    key => {
      seat([key]);
      const target = home.redirect({ params: { accountId: '9' } });
      expect(target).toEqual({
        name: 'settings_booking',
        params: { accountId: '9' },
      });
    }
  );
});
