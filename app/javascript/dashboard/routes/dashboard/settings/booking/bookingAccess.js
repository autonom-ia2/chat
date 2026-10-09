import { SCHEDULING_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { BOOKING_V2_FEATURE } from './constants';

// Quem vê Configurações › Agendamento (#1187): o calendário ligado na instalação
// (CRM_CALENDAR_MEETINGS_ENABLED) E a flag da conta (`crm_booking_v2`), como
// `Crm::Config.booking_v2_enabled?` no backend. Desligada, a tela some e a
// gaveta antiga do Kanban continua como hoje.
export const isBookingV2Available = account =>
  window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true' &&
  account?.features?.[BOOKING_V2_FEATURE] === true;

// Administrador ou função com agendamento_view/_manage. Agente sem função não
// vê (J8-A3): o roteador corta pela permissão da rota, e aqui o item nem nasce.
export const canSeeBookingSettings = ({ isAdministrator, permissions }) =>
  isAdministrator ||
  SCHEDULING_PERMISSIONS.some(key => permissions.includes(key));

export const bookingSidebarItems = ({
  account,
  isAdministrator,
  permissions,
  t,
  accountScopedRoute,
}) => {
  const visible =
    isBookingV2Available(account) &&
    canSeeBookingSettings({ isAdministrator, permissions });
  if (!visible) return [];

  return [
    {
      name: 'Settings Booking',
      label: t('SIDEBAR.BOOKING'),
      icon: 'i-lucide-calendar-check',
      to: accountScopedRoute('settings_booking'),
      activeOn: ['settings_booking', 'settings_booking_results'],
    },
  ];
};

// CRM › Meus números (#1194, J8-A12): entra nos filhos do CRM, que já só
// aparece para quem vê o CRM; aqui só a flag do agendamento novo.
export const bookingResultsSidebarItems = ({
  account,
  t,
  accountScopedRoute,
}) => {
  if (!isBookingV2Available(account)) return [];

  return [
    {
      name: 'CRM Booking Results',
      label: t('BOOKING.RESULTS.MENU'),
      to: accountScopedRoute('crm_booking_results'),
      activeOn: ['crm_booking_results'],
    },
  ];
};
