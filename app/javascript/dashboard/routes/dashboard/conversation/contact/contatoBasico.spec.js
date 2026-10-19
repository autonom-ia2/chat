import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ContatoBasico from './ContatoBasico.vue';

// #1849: sem ver contatos, o painel da conversa mostra nome, telefone e e-mail,
// com nova mensagem e ligar, e nada da ficha.
const montar = contact =>
  mount(ContatoBasico, {
    props: { contact, conversationId: 9 },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          missingWarn: false,
          fallbackWarn: false,
          messages: { pt_BR: {} },
        }),
      ],
      directives: { tooltip: {} },
      stubs: {
        Avatar: true,
        ContactInfoRow: {
          props: ['value', 'href'],
          template: '<a :href="href">{{ value }}</a>',
        },
        ComposeConversation: {
          template: '<div data-nova-mensagem><slot name="trigger" /></div>',
        },
        VoiceCallButton: { template: '<button data-ligar />' },
        NextButton: true,
      },
    },
  });

describe('ContatoBasico (#1849)', () => {
  it('mostra nome, telefone e e-mail, com nova mensagem e ligar', () => {
    const wrapper = montar({
      id: 4,
      name: 'Marcos Prado',
      phone_number: '+5511999990000',
      email: 'marcos@example.test',
      custom_attributes: { cpf: '123' },
      additional_attributes: { company_name: 'Prado Ltda' },
    });

    expect(wrapper.text()).toContain('Marcos Prado');
    expect(wrapper.find('a[href="tel:+5511999990000"]').exists()).toBe(true);
    expect(wrapper.find('a[href="mailto:marcos@example.test"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-nova-mensagem]').exists()).toBe(true);
    expect(wrapper.find('[data-ligar]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('123');
    expect(wrapper.text()).not.toContain('Prado Ltda');
  });
});
