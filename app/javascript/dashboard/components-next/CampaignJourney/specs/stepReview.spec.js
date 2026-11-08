import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import StepReview from '../StepReview.vue';

// #1387 (L15): "Quando começa" sem erro antes de a pessoa escolher a data e sem
// o "·" sobrando ao lado do canal.
const montar = (draft, extra = {}) =>
  mount(StepReview, {
    props: {
      ...extra,
      draft,
      blocks: [],
      channelLabel: 'WhatsApp',
      onChannelLabel: 'On WhatsApp',
      crmTag: 'Campaign',
      timeZone: 'America/Sao_Paulo',
      reach: 3,
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { Dialog: true },
    },
  });

const resumo = wrapper =>
  wrapper
    .find('[data-test="receivers"]')
    .element.nextElementSibling.textContent.split('\n')
    .map(linha => linha.trim())
    .filter(Boolean)
    .join(' ');

describe('StepReview schedule (#1387)', () => {
  it('no past-date error and no dangling dot before a date is chosen', () => {
    const wrapper = montar({ when: 'later', scheduledAt: '' });
    expect(wrapper.text()).not.toContain(
      en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.PAST
    );
    expect(resumo(wrapper)).toBe('WhatsApp');
    expect(wrapper.text()).toContain(
      en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.PICK_DATE
    );
  });

  it('says the date is in the past once one was typed', () => {
    const wrapper = montar({ when: 'later', scheduledAt: '2020-01-01T09:00' });
    expect(wrapper.text()).toContain(
      en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.PAST
    );
  });

  it('keeps "channel · now" when sending now', () => {
    const wrapper = montar({ when: 'now', scheduledAt: '' });
    expect(resumo(wrapper)).toBe(
      `WhatsApp · ${en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.NOW}`
    );
  });

  // Regra do Rodrigo (#1456): o fuso da conta como a plataforma o mostra em
  // Configurações, nunca o nome longo do navegador ("Horário Padrão de Brasília").
  it('labels the date with the account time zone as the settings show it', () => {
    const wrapper = montar({ when: 'later', scheduledAt: '2026-10-20T18:00' });
    const rotulo = wrapper
      .findAll('label')
      .map(label => label.text())
      .find(texto => texto.startsWith('Date and time'));
    expect(rotulo).toBe('Date and time (account time zone: America/Sao Paulo)');
    expect(wrapper.text()).not.toContain('Standard Time');
  });
});

// #1898: who builds without campaign_send leaves the campaign ready; who sends sees who left it.
describe('StepReview ready to send (#1898)', () => {
  const PRONTA = en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.REVIEW.PRONTA;

  it('who only builds marks it ready, without the send confirmation', async () => {
    const wrapper = montar({ when: 'now' }, { soDeixaPronta: true });
    const button = wrapper.find('[data-test="open-confirmation"]');

    expect(button.text()).toContain(PRONTA.DEIXAR);
    expect(wrapper.find('[data-test="aviso-pronta"]').text()).toContain(
      PRONTA.QUEM_MONTA
    );
    await button.trigger('click');
    expect(wrapper.emitted('submit')).toHaveLength(1);
  });

  it('who sends sees who left it ready', () => {
    const wrapper = montar({ when: 'now' }, { montadaPor: 'Carla' });

    expect(wrapper.find('[data-test="aviso-pronta"]').text()).toContain(
      'Carla built it and marked it ready.'
    );
    expect(
      wrapper.find('[data-test="open-confirmation"]').text()
    ).not.toContain(PRONTA.DEIXAR);
  });
});
