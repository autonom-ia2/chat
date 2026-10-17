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
      stubs: { Icon: true },
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

  it('o "+" abre o seletor completo com o foco dentro dele', async () => {
    const wrapper = montar();
    await wrapper.find('button[aria-haspopup]').trigger('click');
    await nextTick();
    await barra(wrapper).findAll('button')[6].trigger('click');

    // Enquanto o seletor carrega, o foco espera no botão de reagir, não no body.
    expect(barra(wrapper).exists()).toBe(false);
    expect(document.activeElement).toBe(
      wrapper.find('button[aria-haspopup]').element
    );
    // Montado o seletor, o foco vai para a busca dele.
    await vi.waitFor(
      () => expect(document.activeElement.tagName).toBe('INPUT'),
      { timeout: 5000 }
    );
    expect(wrapper.element.contains(document.activeElement)).toBe(true);
    wrapper.unmount();
  });
});
