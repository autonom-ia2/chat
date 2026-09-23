// Um ícone por capítulo: quem se guia mais pela imagem do que pelo texto acha o assunto pelo desenho.
const ICONES = {
  '00': 'i-lucide-flag',
  '01': 'i-lucide-map',
  '02': 'i-lucide-user-cog',
  '03': 'i-lucide-building-2',
  '04': 'i-lucide-users',
  '05': 'i-lucide-network',
  '06': 'i-lucide-plug',
  '07': 'i-lucide-inbox',
  '08': 'i-lucide-messages-square',
  '09': 'i-lucide-contact-round',
  10: 'i-lucide-kanban',
  11: 'i-lucide-bot',
  12: 'i-lucide-workflow',
  13: 'i-lucide-megaphone',
  14: 'i-lucide-chart-column',
  15: 'i-lucide-shield-check',
  16: 'i-lucide-radar',
  17: 'i-lucide-receipt',
  18: 'i-lucide-lightbulb',
};

export const CAPITULO_INICIAL = '00';

export const iconeDoCapitulo = id => ICONES[id] || 'i-lucide-book-open';
