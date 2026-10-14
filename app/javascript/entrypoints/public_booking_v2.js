import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import App from '../public_booking_v2/App.vue';
import i18nMessages from '../public_booking_v2/i18n';
import '../public_booking_v2/assets/tailwind.scss';

// "pt-BR" → pt_BR; "pt" → pt_BR; idioma que a página não tem → null.
const toLocale = tag => {
  const normalized = String(tag || '').replace('-', '_');
  if (i18nMessages[normalized]) return normalized;
  const base = normalized.split('_')[0];
  if (base === 'pt') return 'pt_BR';
  return i18nMessages[base] ? base : null;
};

// O servidor já escolhe o idioma (navegador, senão o da conta) e põe no `lang` do HTML; o navegador é só reserva.
const locale =
  toLocale(document.documentElement.lang) ||
  toLocale(window.navigator.language) ||
  'en';
document.documentElement.lang = locale.replace('_', '-');

const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: 'en',
  messages: i18nMessages,
});

// Script de módulo roda depois do HTML lido: monta já, sem esperar imagens e fontes (`window.onload`).
const app = createApp(App);
app.use(i18n);
app.mount('#app');
