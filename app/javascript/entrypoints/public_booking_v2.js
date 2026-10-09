import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import App from '../public_booking_v2/App.vue';
import i18nMessages from '../public_booking_v2/i18n';
import '../public_booking_v2/assets/tailwind.scss';

// Idioma do navegador: pt-BR → pt_BR; pt → pt_BR; o resto cai em en.
const resolveLocale = () => {
  const browserLocale = (window.navigator.language || 'en').replace('-', '_');
  if (i18nMessages[browserLocale]) return browserLocale;
  const base = browserLocale.split('_')[0];
  if (base === 'pt') return 'pt_BR';
  return i18nMessages[base] ? base : 'en';
};

const locale = resolveLocale();
document.documentElement.lang = locale.replace('_', '-');

const i18n = createI18n({
  legacy: false,
  locale,
  fallbackLocale: 'en',
  messages: i18nMessages,
});

const app = createApp(App);
app.use(i18n);

window.onload = () => {
  app.mount('#app');
};
