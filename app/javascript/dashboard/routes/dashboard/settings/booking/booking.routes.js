import { frontendURL } from '../../../../helper/URLHelper';
import {
  CRM_ADMIN_PERMISSION,
  CRM_VIEW_PERMISSION,
  SCHEDULING_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import store from 'dashboard/store';
import { isBookingV2Available } from './bookingAccess';

const SettingsWrapper = () => import('../SettingsWrapper.vue');
const BookingSettingsPage = () => import('./BookingSettingsPage.vue');
const MyBookingHoursPage = () => import('./MyBookingHoursPage.vue');
const BookingResultsPage = () => import('./results/BookingResultsPage.vue');

// Configurações › Agendamento (#1187, F1-D). Ver pede agendamento_view; mudar,
// agendamento_manage (a tela esconde os botões de escrita). O backend aplica o
// mesmo corte (Crm::BookingPagePolicy).
const meta = { permissions: ['administrator', ...SCHEDULING_PERMISSIONS] };

// CRM › Meus horários (#1195, J8-A11) e Meus números (#1194, J8-A12): quem
// pode atender reuniões, o mesmo corte do CRM (Crm::BookingV2::HostEligibility
// e Crm::BookingStatsPolicy): administrador, agente sem função e função com
// crm_view ou crm_admin. As chaves de Agendamento não entram.
export const myHoursMeta = {
  permissions: [
    'administrator',
    'agent',
    CRM_VIEW_PERMISSION,
    CRM_ADMIN_PERMISSION,
  ],
};

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

// "Meus números" mora no CRM: precisa também do CRM ligado na instalação.
export const ensureBookingResultsEnabled = async (to, from, next) => {
  if (window.globalConfig?.CRM_KANBAN_ENABLED !== 'true') {
    next({ name: 'home', params: to.params });
    return;
  }
  await ensureBookingEnabled(to, from, next);
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
        {
          // Painel de resultados (#1194, J7): a equipe para quem tem acesso.
          path: 'results',
          name: 'settings_booking_results',
          component: BookingResultsPage,
          props: { entry: 'settings' },
          meta,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/crm/my-booking-hours'),
      name: 'crm_my_booking_hours',
      meta: myHoursMeta,
      beforeEnter: ensureBookingEnabled,
      component: MyBookingHoursPage,
    },
    {
      path: frontendURL('accounts/:accountId/crm/booking-results'),
      name: 'crm_booking_results',
      meta: myHoursMeta,
      beforeEnter: ensureBookingResultsEnabled,
      component: BookingResultsPage,
      props: { entry: 'crm' },
    },
  ],
};
