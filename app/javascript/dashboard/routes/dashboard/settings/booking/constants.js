// Configurações › Agendamento (#1187, F1-D). Opções prontas da tela: o
// administrador escolhe, não digita número. Os limites seguem o modelo do
// backend (Crm::AgentBookingProfile e Crm::BookingPageSettings).

export const BOOKING_V2_FEATURE = 'crm_booking_v2';

// Os passos do assistente, na ordem da jornada J3. Os avisos no WhatsApp
// (#1192) têm passo próprio antes da prévia: um assunto e uma ação por tela.
export const STEPS = [
  'MODELO',
  'CONTE',
  'ONDE',
  'QUANDO',
  'CARA',
  'AVISOS',
  'PREVIA',
];
export const STEP = {
  MODELO: 1,
  CONTE: 2,
  ONDE: 3,
  QUANDO: 4,
  CARA: 5,
  AVISOS: 6,
  PREVIA: 7,
};

// Os modelos que o backend conhece (Crm::BookingV2::PageTemplates).
export const TEMPLATES = [
  {
    key: 'sales_30',
    i18n: 'SALES',
    icon: 'i-lucide-handshake',
    tone: 'bg-n-blue-3 text-n-blue-11',
    popular: true,
  },
  {
    key: 'consult_45',
    i18n: 'CONSULT',
    icon: 'i-lucide-calendar-clock',
    tone: 'bg-n-teal-3 text-n-teal-11',
  },
  {
    key: 'visit_60',
    i18n: 'VISIT',
    icon: 'i-lucide-map-pin',
    tone: 'bg-n-amber-3 text-n-amber-11',
  },
  {
    key: 'blank',
    i18n: 'BLANK',
    icon: 'i-lucide-plus',
    tone: 'bg-n-slate-3 text-n-slate-11',
  },
];

// Locais sem caixa de e-mail: sempre aparecem.
export const BASIC_LOCATIONS = [
  { type: 'whatsapp_video', icon: 'i-lucide-video', recommended: true },
  { type: 'whatsapp_voice', icon: 'i-lucide-phone' },
  { type: 'custom_link', icon: 'i-lucide-link' },
  { type: 'in_person', icon: 'i-lucide-map-pin' },
];

// Locais que pedem uma caixa de e-mail com agenda já conectada.
export const CALENDAR_LOCATIONS = [
  { type: 'google_meet', icon: 'i-lucide-video', provider: 'google' },
  { type: 'teams', icon: 'i-lucide-video', provider: 'microsoft' },
];

export const MAX_LOCATIONS = 6;
export const MAX_TEXT = 500;

export const DURATION_OPTIONS = [15, 20, 30, 45, 60, 90, 120];
export const EXTRA_DURATION_OPTIONS = [15, 30, 45, 60, 90, 120];
export const MAX_EXTRA_DURATIONS = 5;

// Antecedência mínima, em minutos.
export const NOTICE_OPTIONS = [0, 30, 60, 120, 240, 1440, 2880];
// Intervalo entre conversas, em minutos.
export const BUFFER_OPTIONS = [0, 5, 10, 15, 30, 60];

// Dias na ordem da semana brasileira; o valor é o de Date#wday (0 = domingo).
export const WEEKDAYS = [1, 2, 3, 4, 5, 6, 0];

// Cores prontas da marca. A classe fica escrita aqui por inteiro para o
// Tailwind gerar (nada de `style=""` na tela).
export const BRAND_COLORS = [
  { key: 'BLUE', hex: '#0D2344', swatch: 'bg-[#0D2344]' },
  { key: 'GREEN', hex: '#0B7A5A', swatch: 'bg-[#0B7A5A]' },
  { key: 'RED', hex: '#B3263E', swatch: 'bg-[#B3263E]' },
  { key: 'AMBER', hex: '#8A5200', swatch: 'bg-[#8A5200]' },
  { key: 'PURPLE', hex: '#5B3FA8', swatch: 'bg-[#5B3FA8]' },
  { key: 'GRAPHITE', hex: '#2B2F36', swatch: 'bg-[#2B2F36]' },
];

// Logo e foto: o mesmo que o backend aceita (sem SVG, até 2 MB).
export const IMAGE_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
export const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

// Jogos de avisos prontos (Crm::BookingNoticeSettings::PRESETS, J5-A8): o
// administrador escolhe um, sem digitar horário. `kinds` na ordem em que saem.
export const NOTICE_PRESETS = [
  {
    key: 'standard',
    kinds: ['booked', 'day_before', 'hour_before'],
    recommended: true,
  },
  { key: 'light', kinds: ['booked', 'hour_before'] },
  { key: 'minimal', kinds: ['booked'] },
];
export const DEFAULT_NOTICE_PRESET = 'standard';
// O aviso de "horário mudou" sai quando o cliente remarca, em qualquer jogo.
export const RESCHEDULED_NOTICE = 'rescheduled';

// Até quando o cliente pode mudar ou cancelar, em minutos antes do horário.
export const CANCEL_UNTIL_OPTIONS = [60, 120, 1440];
export const DEFAULT_CANCEL_UNTIL = 120;

// O que a publicação pode pedir, e o passo que resolve cada falta. O funil se
// resolve na própria prévia, no "Alterar" de para onde vai quem marcar.
export const MISSING_STEP = {
  host: STEP.CONTE,
  location: STEP.ONDE,
  working_hours: STEP.QUANDO,
  pipeline: STEP.PREVIA,
};
