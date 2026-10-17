/* eslint-disable vue/one-component-per-file */
import { defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import { provideMessageContext } from '../../message/provider.js';
import OpcoesDoWhatsapp from '../OpcoesDoWhatsapp.vue';

vi.mock('next/message/bubbles/Base.vue', () => ({
  default: { template: '<div data-balao><slot /></div>' },
}));
vi.mock('next/message/MessageMeta.vue', () => ({
  default: { template: '<span data-hora />' },
}));
vi.mock('next/message/bubbles/Text/FormattedContent.vue', () => ({
  default: { props: ['content'], template: '<p>{{ content }}</p>' },
}));

// Teste do Rodrigo em 17/10 (conta 16): a lista abria embaixo do balão, fora do
// padrão do WhatsApp. No app, "Ver opções" abre uma janela com as opções em rádio.
const OPCOES = ['2', '5', '8', '12'].map((title, i) => ({
  id: `opcao_${i + 1}`,
  title,
  description: '',
}));

const montar = sections => {
  const painel = document.createElement('div');
  painel.innerHTML =
    '<div class="conversation-panel"><div id="lugar"></div></div>';
  document.body.append(painel);
  return mount(
    defineComponent({
      setup() {
        provideMessageContext({ content: ref('Aparece um ponto') });
        return () =>
          h(OpcoesDoWhatsapp, {
            header: 'pense',
            isList: true,
            listButton: 'Ver opções',
            options: OPCOES,
            sections,
          });
      },
    }),
    {
      attachTo: painel.querySelector('#lugar'),
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en },
            missingWarn: false,
            fallbackWarn: false,
          }),
        ],
      },
    }
  );
};

describe('opções em lista na conversa do WhatsApp (#1702)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('o balão só tem o botão "Ver opções"; a lista não aparece embaixo dele', () => {
    const balao = montar([{ title: 'Ver opções', options: OPCOES }]);

    expect(balao.find('[data-abrir-lista]').text()).toContain('Ver opções');
    expect(document.querySelector('[data-option-row]')).toBeNull();
  });

  it('tocar em "Ver opções" abre a janela com as opções em rádio, sem repetir o título da seção', async () => {
    const balao = montar([{ title: 'Ver opções', options: OPCOES }]);

    await balao.find('[data-abrir-lista]').trigger('click');

    const janela = document.querySelector('[data-janela-da-lista]');
    expect(janela).not.toBeNull();
    expect(balao.element.contains(janela)).toBe(false);
    const linhas = [...janela.querySelectorAll('[data-option-row]')];
    expect(linhas.map(linha => linha.textContent.trim())).toEqual([
      '2',
      '5',
      '8',
      '12',
    ]);
    expect(janela.textContent.match(/Ver opções/g)).toHaveLength(1);
  });

  it('com mais de uma seção, cada uma mostra o próprio título', async () => {
    const balao = montar([
      { title: 'Manhã', options: OPCOES.slice(0, 2) },
      { title: 'Tarde', options: OPCOES.slice(2) },
    ]);

    await balao.find('[data-abrir-lista]').trigger('click');

    const texto = document.querySelector('[data-janela-da-lista]').textContent;
    expect(texto).toContain('Manhã');
    expect(texto).toContain('Tarde');
  });

  it('Esc fecha a janela', async () => {
    const balao = montar([{ title: 'Ver opções', options: OPCOES }]);
    await balao.find('[data-abrir-lista]').trigger('click');

    document
      .querySelector('[data-janela-da-lista]')
      .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await balao.vm.$nextTick();

    expect(document.querySelector('[data-janela-da-lista]')).toBeNull();
  });
});
