import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import JanelaDeEmojis from '../JanelaDeEmojis.vue';

// #1895 — a janela de emojis do painel, agora comum a todos os canais: com o painel
// em português, "coracao" (sem acento) acha o ❤️ pelo nome em português.
const idioma = vi.hoisted(() => ({ atual: 'pt_BR' }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave, locale: ref(idioma.atual) }),
}));

const montar = () =>
  mount(JanelaDeEmojis, {
    global: {
      stubs: { Icon: true, TeleportWithDirection: { template: '<slot />' } },
    },
  });

const emojisNaGrade = wrapper =>
  wrapper.findAll('[data-janela-de-emojis] .grid button').map(b => b.text());

describe('JanelaDeEmojis', () => {
  beforeEach(() => {
    idioma.atual = 'pt_BR';
  });

  it('em português, "coracao" acha o ❤️', async () => {
    const wrapper = montar();
    await wrapper.find('[data-buscar-emoji]').setValue('coracao');

    // Os nomes em português chegam por import() dinâmico, só no locale pt.
    await vi.waitFor(() => expect(emojisNaGrade(wrapper)).toContain('❤️'), {
      timeout: 5000,
    });
  });

  it('Enter escolhe o primeiro achado', async () => {
    idioma.atual = 'en';
    const wrapper = montar();
    await flushPromises();
    const campo = wrapper.find('[data-buscar-emoji]');
    await campo.setValue('heart');
    const [primeiro] = emojisNaGrade(wrapper);
    await campo.trigger('keydown.enter');

    expect(wrapper.emitted('escolher')).toEqual([[primeiro]]);
  });

  it('fora do português, "coracao" não acha nada', async () => {
    idioma.atual = 'en';
    const wrapper = montar();
    await flushPromises();
    await wrapper.find('[data-buscar-emoji]').setValue('coracao');

    expect(emojisNaGrade(wrapper)).toEqual([]);
    expect(wrapper.text()).toContain('CONVERSA_CANAL.EMAIL.EMOJIS.NADA');
  });

  it('acompanha a âncora quando a página rola', async () => {
    idioma.atual = 'en';
    const ancora = document.createElement('div');
    document.body.appendChild(ancora);
    let topo = 600;
    ancora.getBoundingClientRect = () => ({
      left: 100,
      top: topo,
      bottom: topo + 40,
      right: 500,
      width: 400,
      height: 40,
      x: 100,
      y: topo,
    });
    const wrapper = mount(JanelaDeEmojis, {
      props: { ancora },
      global: {
        stubs: { Icon: true, TeleportWithDirection: { template: '<slot />' } },
      },
    });
    await flushPromises();
    const fundo = () =>
      wrapper.find('[data-janela-de-emojis]').element.style.bottom;
    const antes = fundo();

    topo = 500;
    window.dispatchEvent(new Event('scroll'));
    await flushPromises();

    expect(Number.parseFloat(fundo())).toBe(Number.parseFloat(antes) + 100);
    wrapper.unmount();
    ancora.remove();
  });

  describe('posição na tela (#2113: a âncora pode ser um balão no meio da lista)', () => {
    let alturaAntes;
    let larguraAntes;
    beforeEach(() => {
      idioma.atual = 'en';
      alturaAntes = window.innerHeight;
      larguraAntes = window.innerWidth;
      window.innerHeight = 650;
      window.innerWidth = 1200;
    });
    afterEach(() => {
      window.innerHeight = alturaAntes;
      window.innerWidth = larguraAntes;
    });

    const comAncora = async (caixa, props = {}) => {
      const ancora = document.createElement('div');
      document.body.appendChild(ancora);
      ancora.getBoundingClientRect = () => ({
        ...caixa,
        width: caixa.right - caixa.left,
        height: caixa.bottom - caixa.top,
        x: caixa.left,
        y: caixa.top,
      });
      const wrapper = mount(JanelaDeEmojis, {
        props: { ancora, ...props },
        global: {
          stubs: {
            Icon: true,
            TeleportWithDirection: { template: '<slot />' },
          },
        },
      });
      await flushPromises();
      const estilo = wrapper.find('[data-janela-de-emojis]').element.style;
      return { wrapper, ancora, estilo };
    };

    it('com o balão no meio de uma tela baixa, abre do lado com mais espaço e cabe inteira', async () => {
      const { wrapper, ancora, estilo } = await comAncora({
        left: 100,
        right: 140,
        top: 300,
        bottom: 340,
      });

      // Em cima há 280 px livres e embaixo 290: abre embaixo, com a altura que cabe.
      const topo = Number.parseFloat(estilo.top);
      const altura = Number.parseFloat(estilo.height);
      expect(topo).toBe(348);
      expect(topo + altura).toBeLessThanOrEqual(650 - 12);
      wrapper.unmount();
      ancora.remove();
    });

    it('com espaço em cima, mantém a altura cheia (caixa de resposta)', async () => {
      const { wrapper, ancora, estilo } = await comAncora({
        left: 100,
        right: 500,
        top: 600,
        bottom: 640,
      });

      expect(estilo.height).toBe('420px');
      expect(estilo.bottom).toBe('58px');
      wrapper.unmount();
      ancora.remove();
    });

    it('alinhada ao fim, termina na borda direita da âncora (mensagem enviada)', async () => {
      const { wrapper, ancora, estilo } = await comAncora(
        { left: 900, right: 940, top: 600, bottom: 640 },
        { alinhar: 'fim' }
      );

      expect(
        Number.parseFloat(estilo.left) + Number.parseFloat(estilo.width)
      ).toBe(940);
      wrapper.unmount();
      ancora.remove();
    });

    it('sem focar a busca, o foco fica na própria janela (celular)', async () => {
      const { wrapper, ancora } = await comAncora(
        { left: 100, right: 140, top: 600, bottom: 640 },
        { focarBusca: false }
      );

      expect(document.activeElement).not.toBe(
        wrapper.find('[data-buscar-emoji]').element
      );
      wrapper.unmount();
      ancora.remove();
    });
  });
});
