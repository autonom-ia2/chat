import { frontendURL } from '../../../../helper/URLHelper';
import { SCHEDULING_PERMISSIONS } from 'dashboard/constants/permissions.js';
import store from 'dashboard/store';
import { isBookingV2Available } from './bookingAccess';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const BookingSettingsPage = () => import('./BookingSettingsPage.vue');

// Configurações › Agendamento (#1187, F1-D). Ver pede agendamento_view; mudar,
// agendamento_manage (a tela esconde os botões de escrita). O backend aplica o
// mesmo corte (Crm::BookingPagePolicy).
const meta = { permissions: ['administrator', ...SCHEDULING_PERMISSIONS] };

// Link direto / F5: o guarda roda antes de a store ter a conta. Carrega a conta
// antes de decidir (mesmo cuidado de autonomia.routes.js); sem conta, ou com a
// flag desligada, vai para home.
const accountOf = async to => {
  const accountId = Number(to.params.accountId);
  const account = store.getters['accounts/getAccount'](accountId);
  if (account?.id) return account;
  try {
    await store.dispatch('accounts/get');
  } catch {
    return null;
  }
  return store.getters['accounts/getAccount'](accountId);
};

export const ensureBookingEnabled = async (to, _from, next) => {
  const calendarOn =
    window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true';
  const account = calendarOn ? await accountOf(to) : null;

  if (isBookingV2Available(account)) {
    next();
    return;
  }
  next({ name: 'home', params: to.params });
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/booking'),
      meta,
      beforeEnter: ensureBookingEnabled,
      component: SettingsWrapper,
      props: { keepAlive: false },
      children: [
        {
          path: '',
          name: 'settings_booking',
          component: BookingSettingsPage,
          meta,
        },
      ],
    },
  ],
};
