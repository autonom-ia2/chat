import { createI18n } from 'vue-i18n';
import {
  buildDashboardI18nMessages,
  definirPacoteDoPainel,
  setDashboardLocale,
} from '../localeLoader';

const novoI18n = async bootstrap =>
  createI18n({
    legacy: false,
    ...(await buildDashboardI18nMessages(bootstrap)),
  });

describe('dashboard locale with the account translation pack (#1550)', () => {
  afterEach(() => {
    definirPacoteDoPainel(null);
  });

  it('shows the health plan words in pt_BR, with the insurance layer underneath', async () => {
    definirPacoteDoPainel('seguros.saude_beneficios');
    const i18n = await novoI18n('pt_BR');
    await setDashboardLocale(i18n.global, 'pt_BR');

    expect(i18n.global.locale.value).toBe('pt_BR');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Implantado');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_LOST')).toBe('Não fechou');
    expect(i18n.global.t('CRM_CARD.DESFECHO.GANHOU')).toBe('Implantado');
    // Texto fora do pacote segue o geral.
    expect(i18n.global.t('CANNED_MGMT.SEARCH_PLACEHOLDER')).toBe(
      'Pesquisar respostas prontas...'
    );
  });

  it('shows the pack in English too', async () => {
    definirPacoteDoPainel('seguros.saude_beneficios');
    const i18n = await novoI18n('en');
    await setDashboardLocale(i18n.global, 'en');

    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Implemented');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_LOST')).toBe('Not closed');
  });

  it('goes back to the general words when the pack is removed', async () => {
    definirPacoteDoPainel('seguros.corretora');
    const i18n = await novoI18n('pt_BR');
    await setDashboardLocale(i18n.global, 'pt_BR');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Seguro ativo');

    definirPacoteDoPainel(null);
    await setDashboardLocale(i18n.global, 'pt_BR');
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Ganho');
  });

  it('gives the other language back its general words after a switch', async () => {
    definirPacoteDoPainel('seguros.corretora');
    const i18n = await novoI18n('pt_BR');
    await setDashboardLocale(i18n.global, 'pt_BR');
    await setDashboardLocale(i18n.global, 'en');

    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Active policy');
    expect(
      i18n.global.getLocaleMessage('pt_BR').CRM_KANBAN.DRAWER.STATUS_WON
    ).toBe('Ganho');
  });

  it('leaves a language without a pack on its own catalogue', async () => {
    const semPacote = await novoI18n('en');
    await setDashboardLocale(semPacote.global, 'es');
    const espanholGeral = semPacote.global.getLocaleMessage('es');
    const ganhoGeral = semPacote.global.t('CRM_KANBAN.DRAWER.STATUS_WON');

    definirPacoteDoPainel('seguros.corretora');
    const i18n = await novoI18n('en');
    await setDashboardLocale(i18n.global, 'es');

    expect(i18n.global.locale.value).toBe('es');
    expect(i18n.global.getLocaleMessage('es')).toEqual(espanholGeral);
    expect(i18n.global.t('CRM_KANBAN.DRAWER.STATUS_WON')).toBe(ganhoGeral);
  });
});
