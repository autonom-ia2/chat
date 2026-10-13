import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import StepReview from '../StepReview.vue';

// #1387 (L15): "Quando começa" sem erro antes de a pessoa escolher a data e sem
// o "·" sobrando ao lado do canal.
const montar = draft =>
  mount(StepReview, {
    props: {
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

  it('labels the date with the zone name, not the IANA id', () => {
    const wrapper = montar({ when: 'later', scheduledAt: '' });
    const rotulo = wrapper
      .findAll('label')
      .map(label => label.text())
      .find(texto => texto.startsWith('Date and time'));
    expect(rotulo).toBeTruthy();
    expect(rotulo).not.toContain('America/Sao_Paulo');
  });
});
