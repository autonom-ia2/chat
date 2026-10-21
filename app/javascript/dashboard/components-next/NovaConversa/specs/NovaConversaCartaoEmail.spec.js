import { mount } from '@vue/test-utils';
import NovaConversaCartaoEmail from '../NovaConversaCartaoEmail.vue';

// #1942 — na prévia da gaveta, o e-mail citado com imagem embutida no texto puro mostra
// a imagem (pelo Letter, que sanitiza), não a tag crua.
const LetterFalso = {
  name: 'Letter',
  props: ['html'],
  template: '<div data-letter :data-html="html" />',
};
const URL_DA_IMAGEM = `${window.location.origin}/rails/active_storage/blobs/redirect/abc/image0.jpeg`;
const montar = (textoFull, stubs = { Letter: LetterFalso }) =>
  mount(NovaConversaCartaoEmail, {
    props: {
      remetente: 'Comercial',
      assunto: 'Re: Teste',
      historico: {
        content: 'Esse é um teste',
        sender: { name: 'Rodrigo' },
        content_attributes: { email: { text_content: { full: textoFull } } },
      },
    },
    global: {
      mocks: { $t: chave => chave },
      stubs,
    },
  });

describe('NovaConversaCartaoEmail: histórico citado', () => {
  it('imagem embutida pelo Chatwoot vai pelo Letter como imagem, sem tag crua no texto', () => {
    const wrapper = montar(
      `Esse é um teste\n\n<img src="${URL_DA_IMAGEM}" alt="image0.jpeg">`
    );
    const bloco = wrapper.get('[data-previa-do-historico]');
    expect(bloco.text()).not.toContain('<img');
    const html = wrapper.get('[data-letter]').attributes('data-html');
    expect(html).toContain(`<img src="${URL_DA_IMAGEM}" alt="image0.jpeg">`);
    expect(html).toContain('Esse é um teste');
  });

  it('texto puro sem imagem continua texto, como antes', () => {
    const wrapper = montar('De: Ana <ana@x.com>\nOi');
    expect(wrapper.find('[data-letter]').exists()).toBe(false);
    expect(wrapper.get('[data-previa-do-historico]').text()).toContain(
      'De: Ana <ana@x.com>'
    );
  });

  it('com o Letter de verdade (sanitizado), a imagem chega ao DOM e nenhuma tag crua', async () => {
    const wrapper = montar(
      `Esse é um teste\n\n<img src="${URL_DA_IMAGEM}" alt="image0.jpeg">`,
      {}
    );
    await wrapper.vm.$nextTick();
    const bloco = wrapper.get('[data-previa-do-historico-com-imagem]');
    expect(bloco.find('img').attributes('src')).toBe(URL_DA_IMAGEM);
    expect(bloco.text()).toContain('Esse é um teste');
    expect(bloco.text()).not.toContain('<img');
  });
});
