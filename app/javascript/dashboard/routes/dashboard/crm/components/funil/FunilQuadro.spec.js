import { flushPromises, mount } from '@vue/test-utils';
import FunilQuadro from './FunilQuadro.vue';

// jsdom não tem layout. Simula o quadro do navegador: 450 px de largura,
// colunas de 100 px (quatro e meia à vista) e o scrollLeft preso entre o
// início e o fim, como no navegador. Em RTL a primeira coluna fica à direita
// e o scrollLeft vai de 0 a negativo.
const LARGURA = 450;
const COLUNA = 100;
const caixa = (left, width) => ({
  left,
  right: left + width,
  width,
  top: 0,
  bottom: 100,
  height: 100,
});

let rtl = false;
let retangulo;
let rolagem;
const original = window.getComputedStyle;

beforeEach(() => {
  rtl = false;
  retangulo = Object.getOwnPropertyDescriptor(
    Element.prototype,
    'getBoundingClientRect'
  );
  rolagem = Object.getOwnPropertyDescriptor(Element.prototype, 'scrollLeft');
  Object.defineProperty(Element.prototype, 'scrollLeft', {
    configurable: true,
    get() {
      return this.posicao || 0;
    },
    set(valor) {
      const sobra = Math.max(this.children.length * COLUNA - LARGURA, 0);
      const [minimo, maximo] = rtl ? [-sobra, 0] : [0, sobra];
      this.posicao = Math.min(Math.max(valor, minimo), maximo);
    },
  });
  Element.prototype.getBoundingClientRect = function medida() {
    if (this.hasAttribute('data-funil-quadro-trilho')) {
      return caixa(0, LARGURA);
    }
    if (this.hasAttribute('data-coluna')) {
      const indice = [...this.parentElement.children].indexOf(this);
      const rolado = this.parentElement.scrollLeft;
      const left = rtl
        ? LARGURA - (indice + 1) * COLUNA - rolado
        : indice * COLUNA - rolado;
      return caixa(left, COLUNA);
    }
    return caixa(0, 0);
  };
  window.getComputedStyle = (el, ...resto) =>
    el.hasAttribute?.('data-funil-quadro-trilho')
      ? { direction: rtl ? 'rtl' : 'ltr' }
      : original(el, ...resto);
});
afterEach(() => {
  Object.defineProperty(Element.prototype, 'getBoundingClientRect', retangulo);
  if (rolagem) Object.defineProperty(Element.prototype, 'scrollLeft', rolagem);
  else delete Element.prototype.scrollLeft;
  window.getComputedStyle = original;
});

const etapas = n =>
  Array.from({ length: n }, (_, i) => ({
    chave: `e${i}`,
    nome: `Etapa ${i + 1}`,
    cor: '#2563eb',
    total: null,
  }));

const montar = props =>
  mount(FunilQuadro, {
    props: { nome: 'Imobiliária', etapas: etapas(8), ...props },
    attachTo: document.body,
  });

const trilho = wrapper => wrapper.get('[data-funil-quadro-trilho]');
const rolagemFeita = async wrapper => {
  await trilho(wrapper).trigger('scroll');
  await flushPromises();
};

describe('FunilQuadro', () => {
  it('keeps four stages that fit as plain columns, with no arrows or hint', async () => {
    const wrapper = montar({ etapas: etapas(4) });
    await flushPromises();
    expect(wrapper.findAll('[data-coluna]')).toHaveLength(4);
    expect(wrapper.find('[data-funil-quadro-depois]').exists()).toBe(false);
    expect(wrapper.find('[data-funil-quadro-antes]').exists()).toBe(false);
    expect(wrapper.find('[data-funil-quadro-aviso]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('shows eight stages as columns, with the next arrow and the hint', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findAll('[data-coluna]')).toHaveLength(8);
    expect(wrapper.find('[data-funil-quadro-antes]').exists()).toBe(false);
    expect(
      wrapper.get('[data-funil-quadro-depois]').attributes('aria-label')
    ).toBe('CRM_FUNIL.PREVIA.VER_DEPOIS');
    expect(wrapper.get('[data-funil-quadro-aviso]').text()).toContain(
      'CRM_FUNIL.PREVIA.MAIS_DEPOIS'
    );
    wrapper.unmount();
  });

  it('pages keeping the last whole column as reference', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.get('[data-funil-quadro-depois]').trigger('click');
    // Coluna 4 (a última inteira) vai para a borda esquerda.
    expect(trilho(wrapper).element.scrollLeft).toBe(3 * COLUNA);

    await rolagemFeita(wrapper);
    expect(wrapper.find('[data-funil-quadro-antes]').exists()).toBe(true);
    expect(wrapper.find('[data-funil-quadro-depois]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('moves focus to the other arrow when the focused one reaches the end', async () => {
    const wrapper = montar();
    await flushPromises();
    const depois = wrapper.get('[data-funil-quadro-depois]');
    depois.element.focus();
    await depois.trigger('click');
    await rolagemFeita(wrapper);
    await wrapper.get('[data-funil-quadro-depois]').trigger('click');
    await rolagemFeita(wrapper);

    expect(wrapper.find('[data-funil-quadro-depois]').exists()).toBe(false);
    expect(document.activeElement).toBe(
      wrapper.get('[data-funil-quadro-antes]').element
    );
    wrapper.unmount();
  });

  it('pages the right way in RTL, where the board starts on the right', async () => {
    rtl = true;
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-funil-quadro-depois]').exists()).toBe(true);
    await wrapper.get('[data-funil-quadro-depois]').trigger('click');
    // Coluna 4 vai para a borda direita: o quadro anda 300 px para a esquerda.
    expect(trilho(wrapper).element.scrollLeft).toBe(-3 * COLUNA);
    wrapper.unmount();
  });

  it('scrolls the highlighted stage into view so it is never hidden', async () => {
    const wrapper = montar({ acesa: 6 });
    await flushPromises();
    // O meio pediria 425; o quadro para no fim (350), com a coluna 7 inteira.
    expect(trilho(wrapper).element.scrollLeft).toBe(350);
    expect(wrapper.get('[aria-current="true"]').text()).toContain('Etapa 7');
    wrapper.unmount();
  });

  it('follows the stage where the new conversation lands', async () => {
    const wrapper = montar();
    await flushPromises();
    await wrapper.setProps({ chegando: 5 });
    await flushPromises();
    // Centro da coluna 6 (550) no meio do quadro (225).
    expect(trilho(wrapper).element.scrollLeft).toBe(325);
    wrapper.unmount();
  });
});
