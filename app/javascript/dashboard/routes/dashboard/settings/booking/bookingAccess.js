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
    },
  ];
};

// Meus horários (#1195, J8-A11): fica no grupo CRM, ao lado do Calendário,
// para quem já vê o CRM (o grupo só nasce para essas pessoas). Não pede as
// chaves de Agendamento: o agente comum ajusta a própria agenda.
export const myBookingHoursSidebarItems = ({
  account,
  t,
  accountScopedRoute,
}) =>
  isBookingV2Available(account)
    ? [
        {
          name: 'CRM My Booking Hours',
          label: t('BOOKING.MY_HOURS.MENU'),
          to: accountScopedRoute('crm_my_booking_hours'),
          activeOn: ['crm_my_booking_hours'],
        },
      ]
    : [];
