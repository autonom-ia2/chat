import { SCHEDULING_PERMISSIONS } from 'dashboard/constants/permissions.js';
import { BOOKING_V2_FEATURE } from './constants';

// Quem vê CRM › Agendamento (#1187): o calendário ligado na instalação
// (CRM_CALENDAR_MEETINGS_ENABLED) E a flag da conta (`crm_booking_v2`), como
// `Crm::Config.booking_v2_enabled?` no backend. Desligada, a tela some e a
// gaveta antiga do Kanban continua como hoje.
export const isBookingV2Available = account =>
  window.globalConfig?.CRM_CALENDAR_MEETINGS_ENABLED === 'true' &&
  account?.features?.[BOOKING_V2_FEATURE] === true;

// Administrador ou função com agendamento_view/_manage. Agente sem função não
// vê (J8-A3): o roteador corta pela permissão da rota, e aqui o item nem nasce.
// A mesma regra abre o botão Agendamento do Calendário (#1212).
export const canSeeBookingSettings = ({ isAdministrator, permissions }) =>
  isAdministrator ||
  SCHEDULING_PERMISSIONS.some(key => permissions.includes(key));

// CRM › Agendamento › Páginas e links (#1212, #1264): a lista de páginas,
// com a aba Resultados.
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
      name: 'CRM Booking',
      label: t('BOOKING.PAGE.MENU'),
      to: accountScopedRoute('settings_booking'),
      activeOn: ['settings_booking', 'settings_booking_results'],
    },
  ];
};

// CRM › Agendamento › Meus números (#1194, J8-A12): fica no subgrupo Agendamento do CRM e só entra
// para quem vê o CRM (bookingSidebarGroup); aqui só a flag do agendamento novo.
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

// CRM › Agendamento › Meus horários (#1195, J8-A11): fica no subgrupo Agendamento do CRM,
// só para quem já vê o CRM (bookingSidebarGroup). Não pede as
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

// CRM › Agendamento (#1264): subgrupo com Páginas e links, Meus horários e
// Meus números. Cada filho segue a regra que já tinha: Páginas e links pede
// admin ou função com Agendamento; Meus horários e Meus números pedem ver o
// CRM. Sem filho nenhum, o subgrupo não nasce.
export const bookingSidebarGroup = ({ canViewCrm, ...args }) => {
  const children = [
    ...bookingSidebarItems(args),
    ...(canViewCrm
      ? [
          ...myBookingHoursSidebarItems(args),
          ...bookingResultsSidebarItems(args),
        ]
      : []),
  ];
  if (children.length === 0) return [];

  return [
    {
      name: 'CRM Scheduling',
      label: args.t('SIDEBAR.BOOKING'),
      icon: 'i-lucide-calendar-clock',
      children,
    },
  ];
};
