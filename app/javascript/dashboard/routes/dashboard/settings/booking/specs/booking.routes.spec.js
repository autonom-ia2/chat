// CRM › Agendamento (#1187, F1-D; no CRM desde o #1212): permissões da rota,
// guarda da flag (instalação + conta, com F5) e o item do menu.
import bookingRoutes, {
  ensureBookingEnabled,
  ensureCrmBookingEnabled,
} from '../booking.routes';
import {
  bookingResultsSidebarItems,
  bookingSidebarItems,
  myBookingHoursSidebarItems,
} from '../bookingAccess';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));

const [parent] = bookingRoutes.routes;
const page = parent.children.find(route => route.name === 'settings_booking');

const enter = async () => {
  const next = vi.fn();
  await ensureBookingEnabled({ params: { accountId: '9' } }, {}, next);
  return next;
};

const accountLoadsLater = account => {
  let loaded = null;
  store.getters['accounts/getAccount'] = () => loaded;
  store.dispatch.mockImplementation(async () => {
    loaded = account;
  });
};

const withFlag = enabled => ({
  id: 9,
  features: { crm_booking_v2: enabled },
});

describe('rota settings_booking', () => {
  beforeEach(() => {
    store.dispatch.mockReset();
    store.getters['accounts/getAccount'] = () => null;
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
  });

  it('fica em accounts/:accountId/crm/booking, com o guarda do CRM e da flag', () => {
    expect(parent.path).toBe('/app/accounts/:accountId/crm/booking');
    expect(parent.beforeEnter).toBe(ensureCrmBookingEnabled);
  });

  it('exige o CRM ligado na instalação, além da flag do agendamento', async () => {
    store.getters['accounts/getAccount'] = () => withFlag(true);
    window.globalConfig.CRM_KANBAN_ENABLED = 'true';
    const open = vi.fn();
    await parent.beforeEnter({ params: { accountId: '9' } }, {}, open);
    expect(open).toHaveBeenCalledWith();

    window.globalConfig.CRM_KANBAN_ENABLED = 'false';
    const blocked = vi.fn();
    await parent.beforeEnter({ params: { accountId: '9' } }, {}, blocked);
    expect(blocked).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it.each([
    ['settings/booking', 'settings_booking'],
    ['settings/booking/results', 'settings_booking_results'],
  ])('o endereço antigo %s leva ao novo, com a mesma query', (old, name) => {
    const moved = bookingRoutes.routes.find(
      route => route.path === `/app/accounts/:accountId/${old}`
    );
    const to = { params: { accountId: '9' }, query: { from: 'link' } };
    expect(moved.redirect(to)).toEqual({ name, ...to });
    expect(moved.name).toBeUndefined();
  });

  it('abre para administrador e para as duas chaves de Agendamento, e só', () => {
    const expected = [
      'administrator',
      'agendamento_view',
      'agendamento_manage',
    ];
    expect(parent.meta.permissions).toEqual(expected);
    expect(page.meta.permissions).toEqual(expected);
    expect(page.meta.permissions).not.toContain('agent');
  });

  it('com link direto (F5) espera a conta e entra quando a flag está ligada', async () => {
    accountLoadsLater(withFlag(true));
    const next = await enter();
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  it('com a conta já na store, não busca de novo', async () => {
    store.getters['accounts/getAccount'] = () => withFlag(true);
    const next = await enter();
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith();
  });

  it('flag da conta desligada manda para home', async () => {
    accountLoadsLater(withFlag(false));
    const next = await enter();
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('calendário desligado na instalação manda para home sem buscar a conta', async () => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    store.getters['accounts/getAccount'] = () => withFlag(true);
    const next = await enter();
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('conta que não carrega manda para home', async () => {
    store.dispatch.mockRejectedValue(new Error('rede'));
    const next = await enter();
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });
});

describe('item do menu Agendamento', () => {
  const build = (overrides = {}) =>
    bookingSidebarItems({
      account: withFlag(true),
      isAdministrator: false,
      permissions: [],
      t: key => key,
      accountScopedRoute: name => ({ name }),
      ...overrides,
    });

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
  });

  it('aparece para o administrador com a flag ligada, como item do CRM', () => {
    const [item] = build({ isAdministrator: true });
    expect(item.name).toBe('CRM Booking');
    expect(item.label).toBe('SIDEBAR.BOOKING');
    expect(item.to).toEqual({ name: 'settings_booking' });
  });

  it.each(['agendamento_view', 'agendamento_manage'])(
    'aparece para função com %s',
    key => {
      expect(build({ permissions: [key] })).toHaveLength(1);
    }
  );

  it('não aparece para agente sem função nem para função sem o módulo', () => {
    expect(build({ permissions: ['agent'] })).toEqual([]);
    expect(build({ permissions: ['crm_view', 'custom_role'] })).toEqual([]);
  });

  it('não aparece com a flag da conta ou o calendário desligados', () => {
    expect(build({ isAdministrator: true, account: withFlag(false) })).toEqual(
      []
    );
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    expect(build({ isAdministrator: true })).toEqual([]);
  });
});

describe('Meus horários (#1195): rota e item do menu', () => {
  const myHours = bookingRoutes.routes.find(
    route => route.name === 'crm_my_booking_hours'
  );

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
  });

  it('fica no CRM, com o guarda da flag, aberta a quem pode atender e só', () => {
    expect(myHours.path).toBe('/app/accounts/:accountId/crm/my-booking-hours');
    expect(myHours.beforeEnter).toBe(ensureCrmBookingEnabled);
    expect(myHours.meta.permissions).toEqual([
      'administrator',
      'agent',
      'crm_view',
      'crm_admin',
    ]);
    expect(myHours.meta.permissions).not.toContain('agendamento_view');
    expect(myHours.meta.permissions).not.toContain('agendamento_manage');
  });

  it('o item aparece no CRM com a flag ligada e some com ela desligada', () => {
    const build = account =>
      myBookingHoursSidebarItems({
        account,
        t: key => key,
        accountScopedRoute: name => ({ name }),
      });
    const [item] = build(withFlag(true));
    expect(item).toEqual({
      name: 'CRM My Booking Hours',
      label: 'BOOKING.MY_HOURS.MENU',
      to: { name: 'crm_my_booking_hours' },
      activeOn: ['crm_my_booking_hours'],
    });
    expect(build(withFlag(false))).toEqual([]);
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'false' };
    expect(build(withFlag(true))).toEqual([]);
  });
});

// Painel de resultados (#1194, J7-A5, J8-A12): aba do Agendamento para quem
// tem o módulo e "Meus números" no CRM para quem atende.
describe('rotas do painel de resultados', () => {
  const results = parent.children.find(
    route => route.name === 'settings_booking_results'
  );
  const crm = bookingRoutes.routes.find(
    route => route.name === 'crm_booking_results'
  );

  beforeEach(() => {
    store.dispatch.mockReset();
    window.globalConfig = {
      CRM_CALENDAR_MEETINGS_ENABLED: 'true',
      CRM_KANBAN_ENABLED: 'true',
    };
  });

  it('a aba Resultados fica em crm/booking/results, com as mesmas permissões e a equipe', () => {
    expect(results.path).toBe('results');
    expect(results.meta.permissions).toEqual([
      'administrator',
      'agendamento_view',
      'agendamento_manage',
    ]);
    expect(results.props).toEqual({ entry: 'settings' });
  });

  it('"Meus números" fica no CRM e abre para quem atende, não para função só de agendamento', () => {
    expect(crm.path).toBe('/app/accounts/:accountId/crm/booking-results');
    expect(crm.meta.permissions).toEqual([
      'administrator',
      'agent',
      'crm_view',
      'crm_admin',
    ]);
    expect(crm.props).toEqual({ entry: 'crm' });
  });

  it('"Meus números" exige o CRM e a flag do agendamento novo', async () => {
    store.getters['accounts/getAccount'] = () => withFlag(true);
    const next = vi.fn();
    await crm.beforeEnter({ params: { accountId: '9' } }, {}, next);
    expect(next).toHaveBeenCalledWith();

    window.globalConfig.CRM_KANBAN_ENABLED = 'false';
    const blocked = vi.fn();
    await crm.beforeEnter({ params: { accountId: '9' } }, {}, blocked);
    expect(blocked).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });

    window.globalConfig.CRM_KANBAN_ENABLED = 'true';
    store.getters['accounts/getAccount'] = () => withFlag(false);
    const off = vi.fn();
    await crm.beforeEnter({ params: { accountId: '9' } }, {}, off);
    expect(off).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });

  it('o item "Meus números" só aparece com a flag, e o menu Agendamento acende nas duas abas', () => {
    const args = { t: key => key, accountScopedRoute: name => ({ name }) };
    expect(
      bookingResultsSidebarItems({ ...args, account: withFlag(true) })
    ).toEqual([
      {
        name: 'CRM Booking Results',
        label: 'BOOKING.RESULTS.MENU',
        to: { name: 'crm_booking_results' },
        activeOn: ['crm_booking_results'],
      },
    ]);
    expect(
      bookingResultsSidebarItems({ ...args, account: withFlag(false) })
    ).toEqual([]);

    const [settingsItem] = bookingSidebarItems({
      ...args,
      account: withFlag(true),
      isAdministrator: true,
      permissions: [],
    });
    expect(settingsItem.activeOn).toEqual([
      'settings_booking',
      'settings_booking_results',
    ]);
  });
});
