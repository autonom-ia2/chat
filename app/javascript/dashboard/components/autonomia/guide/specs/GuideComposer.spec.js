import { mount } from '@vue/test-utils';
import GuideComposer from '../GuideComposer.vue';

// #857 — o clipe anexa arquivos que o Guia lê a cada pergunta.
const montar = props =>
  mount(GuideComposer, {
    props: { onSend: vi.fn(() => true), ...props },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
    },
  });

describe('GuideComposer — arquivos', () => {
  it('manda anexar cada arquivo escolhido e limpa a escolha', async () => {
    const wrapper = montar();
    const input = wrapper.find('input[type="file"]');
    const arquivo = new File(['nome,corretora'], 'leads.csv', {
      type: 'text/csv',
    });
    Object.defineProperty(input.element, 'files', { value: [arquivo] });

    await input.trigger('change');

    expect(wrapper.emitted('anexar')[0]).toEqual([arquivo]);
  });

  it('mostra os arquivos da conversa e deixa remover cada um', async () => {
    const wrapper = montar({
      arquivos: [
        { id: 1, nome: 'leads.csv', estado: 'pronto' },
        { id: 2, nome: 'apolice.pdf', estado: 'subindo' },
      ],
    });

    expect(wrapper.text()).toContain('leads.csv');
    expect(wrapper.text()).toContain('apolice.pdf');

    await wrapper
      .find('button[aria-label^="AUTONOMIA_GUIDE.FILE.REMOVE"]')
      .trigger('click');

    expect(wrapper.emitted('remover')[0]).toEqual([1]);
  });

  it('o clipe tem nome acessível e fica parado enquanto o Guia responde', () => {
    const wrapper = montar({ isBusy: true });
    const clipe = wrapper.find(
      'button[aria-label="AUTONOMIA_GUIDE.FILE.ATTACH"]'
    );

    expect(clipe.attributes('disabled')).toBeDefined();
  });
});
