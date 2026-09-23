import { mount } from '@vue/test-utils';
import ConteudoDoArtigo from '../components/ConteudoDoArtigo.vue';

const push = vi.fn();
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));

const montar = conteudo =>
  mount(ConteudoDoArtigo, {
    props: { conteudo, classeDaLetra: 'prose-xl' },
    global: {
      directives: {
        dompurifyHtml: (el, binding) => {
          el.innerHTML = binding.value;
        },
      },
    },
  });

describe('ConteudoDoArtigo', () => {
  beforeEach(() => push.mockClear());

  it('abre o link para outro artigo dentro da Central', async () => {
    const wrapper = montar('Veja [Sua assinatura](plataforma-02-04).');

    await wrapper.find('a').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'central_de_ajuda_artigo',
      params: { ref: '02-04' },
    });
  });

  it('deixa o link de fora seguir o próprio caminho', async () => {
    const wrapper = montar('Veja [o site](https://exemplo.com).');

    await wrapper.find('a').trigger('click');

    expect(push).not.toHaveBeenCalled();
  });

  it('aplica o tamanho de letra escolhido', () => {
    expect(montar('Texto').find('article').classes()).toContain('prose-xl');
  });
});
