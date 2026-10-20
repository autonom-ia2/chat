import { mount } from '@vue/test-utils';
import CitacaoDaResposta from '../email/CitacaoDaResposta.vue';

// #1869 — o que vai junto (histórico ou encaminhada) nasce fechado; e o corpo em texto
// puro (Mail do iPhone) chega ao leitor como texto, linha a linha, não como uma linha só.
const LetterFalso = {
  name: 'Letter',
  props: ['html', 'text'],
  template: '<div data-letter :data-html="html" :data-text="text" />',
};
const IPHONE =
  'RV\n\n> Em 19 de out. de 2026, à(s) 07:51, Admin escreveu:\n> Que legal!';
const montar = (tipo, email) =>
  mount(CitacaoDaResposta, {
    props: {
      tipo,
      mensagem: {
        content: IPHONE,
        sender: { name: 'Rodrigo' },
        content_attributes: { email },
      },
    },
    global: { stubs: { Icon: true, Letter: LetterFalso } },
  });

describe('CitacaoDaResposta', () => {
  it.each(['encaminhado', 'historico'])(
    '%s nasce fechado e "Ver" abre',
    async tipo => {
      const wrapper = montar(tipo, {});
      expect(wrapper.find('[data-original-citado]').exists()).toBe(false);
      await wrapper.get('[data-ver-citacao]').trigger('click');
      expect(wrapper.find('[data-original-citado]').exists()).toBe(true);
    }
  );

  it('texto puro vai como texto; HTML de verdade, como HTML', async () => {
    const semHtml = montar('encaminhado', {});
    await semHtml.get('[data-ver-citacao]').trigger('click');
    const letter = semHtml.get('[data-letter]');
    expect(letter.attributes('data-html')).toBe('');
    expect(letter.attributes('data-text')).toBe(IPHONE);

    // Endereço entre "<>" no texto puro não é HTML: segue como texto.
    const comEndereco = mount(CitacaoDaResposta, {
      props: {
        tipo: 'encaminhado',
        mensagem: {
          content: 'De: Ana <ana@x.com>\nOi',
          sender: { name: 'Ana' },
          content_attributes: { email: {} },
        },
      },
      global: { stubs: { Icon: true, Letter: LetterFalso } },
    });
    await comEndereco.get('[data-ver-citacao]').trigger('click');
    const letra = comEndereco.get('[data-letter]');
    expect(letra.attributes('data-html')).toBe('');
    expect(letra.attributes('data-text')).toBe('De: Ana <ana@x.com>\nOi');

    const comHtml = montar('encaminhado', {
      html_content: { full: '<p>Oi</p>' },
    });
    await comHtml.get('[data-ver-citacao]').trigger('click');
    // O HTML passa pelo htmlComCssSeguro (documento inteiro) antes do vue-letter.
    expect(comHtml.get('[data-letter]').attributes('data-html')).toContain(
      '<body><p>Oi</p></body>'
    );
  });

  it('texto puro com imagem embutida pelo Chatwoot: a imagem vai como HTML (#1942)', async () => {
    const src =
      'https://painel.test/rails/active_storage/blobs/redirect/abc/image0.jpeg';
    const wrapper = montar('historico', {
      text_content: {
        full: `Esse é um teste\n\n<img src="${src}" alt="image0.jpeg">`,
      },
    });
    await wrapper.get('[data-ver-citacao]').trigger('click');
    const html = wrapper.get('[data-letter]').attributes('data-html');
    expect(html).toContain(`<img src="${src}" alt="image0.jpeg">`);
    expect(html).toContain('Esse é um teste');
  });
});
