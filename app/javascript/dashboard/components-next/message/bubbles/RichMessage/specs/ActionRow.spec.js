import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ActionRow from '../ActionRow.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

describe('ActionRow', () => {
  it('sem endereço é só a imagem do botão, com o rótulo', () => {
    const wrapper = mount(ActionRow, { props: { label: 'De manhã' } });

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toBe('De manhã');
  });

  it('com endereço é link que abre em outra aba', () => {
    const link = mount(ActionRow, {
      props: { label: 'Abrir', href: 'https://exemplo.com.br/' },
    }).get('a');

    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
    expect(link.classes()).toContain('min-h-11');
  });

  it('aceita conteúdo próprio no lugar do rótulo e uma peça à direita', () => {
    const wrapper = mount(ActionRow, {
      props: { label: 'Remarcar horário' },
      slots: {
        default: '<strong>Remarcar</strong><small>Trocar o dia</small>',
        trailing: '<i data-marca="escolhida" />',
      },
    });

    expect(wrapper.find('strong').text()).toBe('Remarcar');
    expect(wrapper.find('small').text()).toBe('Trocar o dia');
    expect(wrapper.find('[data-marca="escolhida"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Remarcar horário');
  });
});
