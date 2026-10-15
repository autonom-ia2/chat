import { createI18n } from 'vue-i18n';
import * as Sentry from '@sentry/vue';
import {
  buildDashboardI18nMessages,
  definirPacoteDoPainel,
  setDashboardLocale,
} from '../localeLoader';

// #1550 — o download do pacote falha (rede, deploy trocando arquivos).
vi.mock('../pacotes/seguros/pt_BR.json', () => {
  throw new Error('Failed to fetch dynamically imported module');
});

vi.mock('@sentry/vue', () => ({ captureException: vi.fn() }));

describe('when the account translation pack fails to download', () => {
  const reload = vi.fn();
  const originalLocation = window.location;

  beforeEach(() => {
    window.sessionStorage.clear();
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: { ...originalLocation, reload },
    });
  });

  afterEach(() => {
    definirPacoteDoPainel(null);
    Object.defineProperty(window, 'location', {
      configurable: true,
      value: originalLocation,
    });
  });

  it('keeps the general words, without reloading the page or failing', async () => {
    definirPacoteDoPainel('seguros.corretora');
    const i18n = createI18n({
      legacy: false,
      ...(await buildDashboardI18nMessages('pt_BR')),
    });

    await expect(
      setDashboardLocale(i18n.global, 'pt_BR')
    ).resolves.toBeUndefined();

    expect(i18n.global.locale.value).toBe('pt_BR');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Ganho');
    expect(reload).not.toHaveBeenCalled();
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
  });
});
