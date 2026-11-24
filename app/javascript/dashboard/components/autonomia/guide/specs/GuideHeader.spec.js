import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import GuideHeader from '../GuideHeader.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

// #3184 — o cabeçalho do Guia: "Novo assunto" e o menu "Mais" próprio, com
// itens de 44 px, setas, Esc e o foco de volta a quem abriu.
const montar = (props = {}) =>
  mount(GuideHeader, {
    attachTo: document.body,
    props: { title: 'Guia', canReset: true, ...props },
    global: {
      mocks: { $t: key => key },
      directives: { onClickaway: {} },
    },
  });

const abrirMenu = async wrapper => {
  await wrapper.get('[data-mais]').trigger('click');
  await nextTick();
};

const itens = wrapper => wrapper.findAll('[role="menuitem"]');

describe('GuideHeader (#3184)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('"Novo assunto" vem escrito e emite reset', async () => {
    const wrapper = montar();
    const botao = wrapper.get('[data-novo-assunto]');

    expect(botao.text()).toContain('AUTONOMIA_GUIDE.HEADER.NEW_TOPIC');
    await botao.trigger('click');
    expect(wrapper.emitted('reset')).toHaveLength(1);
  });

  it('o menu traz os três itens com nome e foca o primeiro', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);

    expect(itens(wrapper).map(item => item.text())).toEqual([
      'AUTONOMIA_GUIDE.HISTORY.TITLE',
      'AUTONOMIA_GUIDE.HEADER.CHANGES',
      'AUTONOMIA_GUIDE.MEMORY.TITLE',
    ]);
    expect(wrapper.get('[data-mais]').attributes('aria-expanded')).toBe('true');
    expect(document.activeElement).toBe(itens(wrapper)[0].element);
  });

  it('cada item emite o seu evento e fecha o menu', async () => {
    const wrapper = montar();
    const eventos = { historico: 0, feitos: 1, memoria: 2 };

    await Object.entries(eventos).reduce(async (anterior, [evento, i]) => {
      await anterior;
      await abrirMenu(wrapper);
      await itens(wrapper)[i].trigger('click');
      expect(wrapper.emitted(evento)).toHaveLength(1);
      expect(wrapper.find('[role="menu"]').exists()).toBe(false);
    }, Promise.resolve());
  });

  it('setas andam pelos itens, dando a volta', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);

    await itens(wrapper)[0].trigger('keydown', { key: 'ArrowUp' });
    expect(document.activeElement).toBe(itens(wrapper)[2].element);

    await itens(wrapper)[2].trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(itens(wrapper)[0].element);
  });

  it('Esc fecha e devolve o foco ao "Mais"', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);

    await itens(wrapper)[1].trigger('keydown', { key: 'Escape' });
    await nextTick();
    await nextTick();

    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(wrapper.get('[data-mais]').element);
  });

  // #3195 — o painel fecha com Esc por um ouvinte no documento. Com o menu
  // aberto, o Esc é do menu: não pode chegar lá e fechar o Guia inteiro.
  it('Esc com o menu aberto não fecha o Guia', async () => {
    const noDocumento = vi.fn();
    document.addEventListener('keydown', noDocumento);
    const wrapper = montar();
    await abrirMenu(wrapper);

    await itens(wrapper)[0].trigger('keydown', { key: 'Escape' });

    expect(noDocumento).not.toHaveBeenCalled();
    document.removeEventListener('keydown', noDocumento);
  });

  it('Esc com o menu fechado segue para o painel fechar o Guia', async () => {
    const noDocumento = vi.fn();
    document.addEventListener('keydown', noDocumento);
    const wrapper = montar();

    await wrapper.get('[data-mais]').trigger('keydown', { key: 'Escape' });

    expect(noDocumento).toHaveBeenCalledTimes(1);
    document.removeEventListener('keydown', noDocumento);
  });

  it('Tab sai do menu e fecha', async () => {
    const wrapper = montar();
    await abrirMenu(wrapper);

    await itens(wrapper)[0].trigger('keydown', { key: 'Tab' });

    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
  });

  it('numa lista, o topo vira "Voltar" e devolve à conversa', async () => {
    const wrapper = montar({
      vendoMemoria: true,
      title: 'O que o Guia anotou',
    });

    expect(wrapper.find('[data-mais]').exists()).toBe(false);
    await wrapper.get('[data-voltar-a-conversa]').trigger('click');
    expect(wrapper.emitted('memoria')).toHaveLength(1);
  });
});
