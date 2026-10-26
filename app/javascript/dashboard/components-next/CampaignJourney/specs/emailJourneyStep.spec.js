import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import EmailJourneyStep from '../EmailJourneyStep.vue';

// #2237: the verified domain is offered as the domain, not as the person whose address was
// saved when the domain was registered; the sender address stays editable and says where
// replies go when no reply inbox is chosen.
const identity = {
  id: 4,
  domain: 'empresa.com.br',
  from_email: 'lucas@empresa.com.br',
  status: 'verified',
};

const replies = {
  id: 48,
  name: 'Comunicação',
  channel_type: 'Channel::Email',
  email: 'comunicacao@empresa.com.br',
};

const montar = (draft = {}, identityExtra = {}) =>
  mount(EmailJourneyStep, {
    props: {
      draft: { title: '', emailSender: '', fromEmail: '', ...draft },
      identities: [{ ...identity, ...identityExtra }],
      inboxes: [replies],
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { BrandIdentityLine: true },
    },
  });

describe('EmailJourneyStep sender (#2237)', () => {
  it('lists the verified domain by its domain, not by the saved address', () => {
    const options = montar()
      .findComponent({ name: 'ChoiceSelect' })
      .props('options');

    expect(options).toEqual([
      { value: 'identity:4', label: '@empresa.com.br · verified domain' },
    ]);
  });

  it('keeps the sender address editable and says any address of the domain works', () => {
    const wrapper = montar({
      emailSender: 'identity:4',
      fromEmail: 'lucas@empresa.com.br',
    });

    expect(wrapper.find('[data-test="email-from"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Any @empresa.com.br address works.');
  });

  const replyChoice = wrapper =>
    wrapper
      .findAllComponents({ name: 'ChoiceSelect' })
      .find(choice => choice.attributes('data-test') === 'email-reply-choice');

  it('names the empty reply option after where replies really go', () => {
    const plain = montar({ emailSender: 'identity:4' });
    expect(replyChoice(plain).props('options')[0].label).toBe(
      'Same as the sender'
    );

    const withDefault = montar(
      { emailSender: 'identity:4' },
      { reply_to_inbox_id: 48 }
    );
    expect(replyChoice(withDefault).props('options')[0].label).toBe(
      'Domain default · Comunicação'
    );
  });
});
