import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import BotaoDeReagir from '../BotaoDeReagir.vue';
import { ABRIR_REACOES } from '../reacaoDoAtendente';
import { emitter } from 'shared/helpers/mitt';
import en from '../../../i18n/locale/en/conversaCanal.json';

const i18n = createI18n({ legacy: false, locale: 'en', messages: { en } });

const montar = (props = {}) =>
  mount(BotaoDeReagir, {
    props: { mensagemId: 7, ...props },
    attachTo: document.body,
    global: {
      plugins: [i18n],
      // A janela de emojis vai para o body, como no painel (fora do botão de reagir).
      stubs: {
        Icon: true,
        TeleportWithDirection: {
          template: '<Teleport to="body"><slot /></Teleport>',
        },
      },
    },
  });

const barra = wrapper => wrapper.find('[role=toolbar]');

describe('BotaoDeReagir', () => {
  it('abre a barra com os 6 rápidos e o "+", e põe o foco no 1º', async () => {
    const wrapper = montar();
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();

    const botoes = barra(wrapper).findAll('button');
    expect(botoes).toHaveLength(7);
    expect(document.activeElement).toBe(botoes[0].element);
    wrapper.unmount();
  });

  it('escolher um emoji emite e fecha a barra', async () => {
    const wrapper = montar({ atual: '👍' });
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await barra(wrapper).findAll('button')[1].trigger('click');

    expect(wrapper.emitted('reagir')).toEqual([['❤️']]);
    expect(barra(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('marca o emoji atual como pressionado (clicar de novo tira)', async () => {
    const wrapper = montar({ atual: '👍' });
    await wrapper.find('button[aria-haspopup]').trigger('click');

    const primeiro = barra(wrapper).findAll('button')[0];
    expect(primeiro.attributes('aria-pressed')).toBe('true');
    expect(primeiro.attributes('aria-label')).toBe('Remove reaction 👍');
    wrapper.unmount();
  });

  it('bloqueado (fora das 24 h): não abre', async () => {
    const wrapper = montar({ bloqueado: true });
    await wrapper.find('button[aria-haspopup]').trigger('click');

    expect(barra(wrapper).exists()).toBe(false);
    expect(
      wrapper.find('button[aria-haspopup]').attributes('aria-disabled')
    ).toBe('true');
    wrapper.unmount();
  });

  it('abre pelo "Reagir" do menu só na mensagem pedida; Esc fecha', async () => {
    const wrapper = montar();
    emitter.emit(ABRIR_REACOES, { messageId: 99 });
    await nextTick();
    expect(barra(wrapper).exists()).toBe(false);

    emitter.emit(ABRIR_REACOES, { messageId: 7 });
    await nextTick();
    expect(barra(wrapper).exists()).toBe(true);

    await barra(wrapper).trigger('keydown', { key: 'Escape' });
    expect(barra(wrapper).exists()).toBe(false);
    wrapper.unmount();
  });

  it('setas andam entre os botões da barra', async () => {
    const wrapper = montar();
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();
    const botoes = barra(wrapper).findAll('button');

    await barra(wrapper).trigger('keydown', { key: 'ArrowLeft' });
    expect(document.activeElement).toBe(botoes[6].element);
    wrapper.unmount();
  });

  const abrirJanela = async wrapper => {
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();
    await barra(wrapper).findAll('button')[6].trigger('click');
    await nextTick();
  };
  const janela = () => document.body.querySelector('[data-janela-de-emojis]');

  it('o "+" abre a janela de emojis da caixa de resposta, com o foco na busca', async () => {
    const wrapper = montar();
    await abrirJanela(wrapper);

    expect(barra(wrapper).exists()).toBe(false);
    expect(janela()).not.toBeNull();
    expect(document.activeElement.matches('[data-buscar-emoji]')).toBe(true);
    wrapper.unmount();
  });

  it('escolher na janela reage com o emoji e fecha', async () => {
    const wrapper = montar();
    await abrirJanela(wrapper);

    const emoji = [...janela().querySelectorAll('button')].find(
      b => b.textContent.trim() === '😀'
    );
    emoji.click();
    await nextTick();

    expect(wrapper.emitted('reagir')).toEqual([['😀']]);
    expect(janela()).toBeNull();
    wrapper.unmount();
  });

  it('Esc fecha a janela e o foco volta para o botão de reagir', async () => {
    const wrapper = montar();
    await abrirJanela(wrapper);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await nextTick();

    expect(janela()).toBeNull();
    expect(document.activeElement).toBe(
      wrapper.find('button[aria-haspopup]').element
    );
    wrapper.unmount();
  });

  // Clique de verdade: pointerdown e depois click, como o onClickOutside trata.
  const clicar = async elemento => {
    elemento.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    elemento.dispatchEvent(
      new MouseEvent('click', { bubbles: true, detail: 1 })
    );
    await nextTick();
    await new Promise(resolve => {
      setTimeout(resolve, 5);
    });
  };
  const abrirJanelaClicando = async wrapper => {
    await clicar(wrapper.find('button[aria-haspopup]').element);
    await clicar(barra(wrapper).findAll('button')[6].element);
  };
  const janelas = () =>
    document.body.querySelectorAll('[data-janela-de-emojis]');

  it('clique de verdade num emoji da janela reage', async () => {
    const wrapper = montar();
    await abrirJanelaClicando(wrapper);
    const emoji = [...janelas()[0].querySelectorAll('button')].find(
      b => b.textContent.trim() === '😀'
    );
    await clicar(emoji);

    expect(wrapper.emitted('reagir')).toEqual([['😀']]);
    expect(janelas()).toHaveLength(0);
    wrapper.unmount();
  });

  it('clique fora fecha a janela', async () => {
    const wrapper = montar();
    await abrirJanelaClicando(wrapper);
    const fora = document.createElement('div');
    document.body.appendChild(fora);
    await clicar(fora);

    expect(janelas()).toHaveLength(0);
    expect(
      wrapper.find('button[aria-haspopup]').attributes('aria-expanded')
    ).toBe('false');
    wrapper.unmount();
    fora.remove();
  });

  it('dois balões: abrir no segundo fecha a janela do primeiro', async () => {
    const primeiro = montar({ mensagemId: 1 });
    const segundo = montar({ mensagemId: 2 });
    await abrirJanelaClicando(primeiro);
    await clicar(segundo.find('button[aria-haspopup]').element);

    expect(janelas()).toHaveLength(0);
    expect(barra(segundo).exists()).toBe(true);
    primeiro.unmount();
    segundo.unmount();
  });

  it('no celular, a barra que passaria da borda da tela anda para dentro (#2113)', async () => {
    const larguraAntes = window.innerWidth;
    window.innerWidth = 390;
    const medida = vi
      .spyOn(HTMLElement.prototype, 'getBoundingClientRect')
      .mockReturnValue({ left: 298, right: 620, top: 0, bottom: 0 });
    const wrapper = montar();
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();

    expect(barra(wrapper).attributes('style')).toContain('translateX(-238px)');
    medida.mockRestore();
    window.innerWidth = larguraAntes;
    wrapper.unmount();
  });

  it('a barra que cabe na tela fica onde está', async () => {
    const medida = vi
      .spyOn(HTMLElement.prototype, 'getBoundingClientRect')
      .mockReturnValue({ left: 100, right: 420, top: 0, bottom: 0 });
    const wrapper = montar();
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();

    expect(barra(wrapper).attributes('style')).toBeUndefined();
    medida.mockRestore();
    wrapper.unmount();
  });
});
