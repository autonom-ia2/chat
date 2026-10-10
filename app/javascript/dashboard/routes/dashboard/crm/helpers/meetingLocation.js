// Onde a reunião acontece, para o calendário e a ficha da reunião (#1188).
//
// Reunião com provedor (Google/Microsoft) segue como sempre: ícone e botão da
// marca. Reunião interna (`provider: 'internal'`, criada pela página de
// agendamento) não tem provedor: o local vem de `online_meeting_type`
// (ou `location_type`) e nunca mostra "Meet" nem "Teams".

const INTERNAL_PROVIDER = 'internal';
const WEB_PROTOCOLS = ['http:', 'https:'];

const LOCATION_META = {
  whatsapp_video: {
    labelKey: 'CRM_KANBAN.CALENDAR.MEETING_LOCATION.WHATSAPP_VIDEO',
    icon: 'i-lucide-video',
  },
  whatsapp_voice: {
    labelKey: 'CRM_KANBAN.CALENDAR.MEETING_LOCATION.WHATSAPP_VOICE',
    icon: 'i-lucide-phone',
  },
  custom_link: {
    labelKey: 'CRM_KANBAN.CALENDAR.MEETING_LOCATION.CUSTOM_LINK',
    icon: 'i-lucide-link',
  },
  in_person: {
    labelKey: 'CRM_KANBAN.CALENDAR.MEETING_LOCATION.IN_PERSON',
    icon: 'i-lucide-map-pin',
  },
  no_online: {
    labelKey: 'CRM_KANBAN.CALENDAR.MEETING_LOCATION.NO_ONLINE',
    icon: 'i-lucide-calendar-clock',
  },
};

// Tipos que só existem em reunião interna.
const INTERNAL_ONLY_TYPES = [
  'whatsapp_video',
  'whatsapp_voice',
  'custom_link',
  'in_person',
];

// Só http/https vira link. `javascript:`, `data:` e texto solto voltam vazios.
export const safeWebUrl = value => {
  if (typeof value !== 'string') return '';
  try {
    const url = new URL(value.trim());
    return WEB_PROTOCOLS.includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
};

const locationTypeOf = meeting =>
  meeting?.online_meeting_type || meeting?.location_type || '';

export const isInternalMeeting = meeting =>
  meeting?.provider === INTERNAL_PROVIDER ||
  INTERNAL_ONLY_TYPES.includes(locationTypeOf(meeting));

// `isInternal: false` devolve só o link como veio, para o código de Google e
// Microsoft continuar exatamente como estava.
export const resolveMeetingLocation = meeting => {
  if (!isInternalMeeting(meeting)) {
    return {
      isInternal: false,
      type: locationTypeOf(meeting),
      labelKey: '',
      icon: '',
      joinUrl: meeting?.online_meeting_url || '',
    };
  }

  const type = locationTypeOf(meeting);
  const meta = LOCATION_META[type] || LOCATION_META.no_online;
  return {
    isInternal: true,
    type,
    labelKey: meta.labelKey,
    icon: meta.icon,
    // Só o "link do agente" tem endereço para abrir, e só se for web.
    joinUrl:
      type === 'custom_link' ? safeWebUrl(meeting.online_meeting_url) : '',
  };
};
