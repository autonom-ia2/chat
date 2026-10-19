import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CardPessoaBasica from '../telas/CardPessoaBasica.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: { pt_BR: {} },
});
const montar = contato =>
  mount(CardPessoaBasica, {
    props: { contato },
    global: { plugins: [i18n], stubs: { Avatar: true } },
  });

describe('CardPessoaBasica (#1849)', () => {
  it('mostra só nome, telefone e e-mail da pessoa do card', () => {
    const wrapper = montar({
      id: 3,
      name: 'Juliana Prado',
      phone_number: '+5511987650042',
      email: 'juliana@example.test',
      custom_attributes: { cpf: '000' },
    });
    expect(wrapper.text()).toContain('Juliana Prado');
    expect(wrapper.find('a[href="tel:+5511987650042"]').exists()).toBe(true);
    expect(wrapper.find('a[href="mailto:juliana@example.test"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).not.toContain('000');
  });

  it('não mostra linha vazia', () => {
    const wrapper = montar({ id: 3, name: 'Sem e-mail', phone_number: '' });
    expect(wrapper.findAll('dd')).toHaveLength(0);
  });

  it('sem pessoa no card, diz que ainda não há ninguém', () => {
    expect(montar(null).find('[data-pessoa-basica]').exists()).toBe(false);
  });
});
