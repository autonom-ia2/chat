import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaign.json';
import TestSendForm from '../TestSendForm.vue';

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const mountForm = (props = {}) =>
  mount(TestSendForm, {
    props: { defaultEmail: 'gestora@empresa.com.br', ...props },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

// #1093 (decision of 07/10/2026): the test goes to any typed address, up to 5.
describe('TestSendForm', () => {
  it('starts with the logged-in user address, editable, and says the rule in one line', () => {
    const wrapper = mountForm();
    const field = wrapper.find('textarea');

    expect(field.element.value).toBe('gestora@empresa.com.br');
    expect(field.attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).toContain('Up to 5 e-mails, one per line.');
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('sends to every typed address', async () => {
    const wrapper = mountForm();
    await wrapper
      .find('textarea')
      .setValue(
        'gestora@empresa.com.br\nsocio@outra.com.br, cliente@gmail.com'
      );
    await wrapper.find('[data-test="test-send-submit"]').trigger('click');

    expect(wrapper.emitted('send')).toEqual([
      [['gestora@empresa.com.br', 'socio@outra.com.br', 'cliente@gmail.com']],
    ]);
  });

  it('says which address is wrong and does not send', async () => {
    const wrapper = mountForm();
    await wrapper.find('textarea').setValue('certo@empresa.com.br errado@');
    await wrapper.find('[data-test="test-send-submit"]').trigger('click');

    expect(wrapper.text()).toContain(
      "This doesn't look like an e-mail: errado@"
    );
    expect(wrapper.emitted('send')).toBeUndefined();
  });

  it('refuses more than 5 addresses', async () => {
    const wrapper = mountForm();
    await wrapper
      .find('textarea')
      .setValue(
        [1, 2, 3, 4, 5, 6].map(n => `pessoa${n}@empresa.com.br`).join('\n')
      );
    await wrapper.find('[data-test="test-send-submit"]').trigger('click');

    expect(wrapper.text()).toContain('Up to 5 e-mails per test.');
    expect(wrapper.emitted('send')).toBeUndefined();
  });

  it('without a user e-mail the field starts empty and asks for one instead of doing nothing', async () => {
    const wrapper = mountForm({ defaultEmail: '' });
    expect(wrapper.find('textarea').element.value).toBe('');

    await wrapper.find('[data-test="test-send-submit"]').trigger('click');

    expect(wrapper.text()).toContain('Write at least one e-mail.');
    expect(wrapper.emitted('send')).toBeUndefined();
  });

  it('shows the server refusal next to the field and has 44px buttons', async () => {
    const wrapper = mountForm({
      errorMessage:
        'saiu@empresa.com.br does not receive e-mails from this account. Use another address.',
    });

    expect(wrapper.find('[data-test="test-send-error"]').text()).toContain(
      'saiu@empresa.com.br does not receive'
    );
    wrapper
      .findAll('button')
      .forEach(button => expect(button.classes()).toContain('!min-h-11'));
    await wrapper.find('[data-test="test-send-cancel"]').trigger('click');
    expect(wrapper.emitted('cancel')).toHaveLength(1);
  });
});
