import { mount } from '@vue/test-utils';
import ListaAbas from '../ListaAbas.vue';
import { criarI18n } from './apoio';

// #2202 — teclado do padrão WAI-ARIA de abas: setas, Home e End, tabindex móvel e aria-controls.
const ITENS = [
  { key: 'me', name: 'Minhas', count: 4 },
  { key: 'unassigned', name: 'Não atribuídas', count: 12 },
  { key: 'all', name: 'Todos', count: 24 },
];

const montar = (activeTab = 'me') => {
  const wrapper = mount(ListaAbas, {
    props: {
      items: ITENS,
      activeTab,
      painelId: 'painel-teste',
      onChatTabChange: key => wrapper.setProps({ activeTab: key }),
    },
    global: { plugins: [criarI18n()] },
    attachTo: document.body,
  });
  return wrapper;
};
const abas = wrapper => wrapper.findAll('[role="tab"]');

describe('ListaAbas (#2202)', () => {
  it('só a aba escolhida entra no Tab; todas apontam o painel', () => {
    const wrapper = montar('unassigned');
    expect(abas(wrapper).map(aba => aba.attributes('tabindex'))).toEqual([
      '-1',
      '0',
      '-1',
    ]);
    abas(wrapper).forEach(aba =>
      expect(aba.attributes('aria-controls')).toBe('painel-teste')
    );
    expect(abas(wrapper)[1].attributes('id')).toBe('lista-aba-unassigned');
    wrapper.unmount();
  });

  it('seta para a direita vai à próxima aba, escolhe e leva o foco; na última, volta à primeira', async () => {
    const wrapper = montar('me');
    await abas(wrapper)[0].trigger('keydown', { key: 'ArrowRight' });
    expect(wrapper.emitted('chatTabChange').at(-1)).toEqual(['unassigned']);
    expect(document.activeElement).toBe(abas(wrapper)[1].element);
    expect(abas(wrapper)[1].attributes('tabindex')).toBe('0');

    await abas(wrapper)[1].trigger('keydown', { key: 'ArrowRight' });
    await abas(wrapper)[2].trigger('keydown', { key: 'ArrowRight' });
    expect(wrapper.emitted('chatTabChange').at(-1)).toEqual(['me']);
    expect(document.activeElement).toBe(abas(wrapper)[0].element);
    wrapper.unmount();
  });

  it('seta para a esquerda na primeira vai à última', async () => {
    const wrapper = montar('me');
    await abas(wrapper)[0].trigger('keydown', { key: 'ArrowLeft' });
    expect(wrapper.emitted('chatTabChange').at(-1)).toEqual(['all']);
    expect(document.activeElement).toBe(abas(wrapper)[2].element);
    wrapper.unmount();
  });

  it('Home e End vão à primeira e à última', async () => {
    const wrapper = montar('unassigned');
    await abas(wrapper)[1].trigger('keydown', { key: 'End' });
    expect(wrapper.emitted('chatTabChange').at(-1)).toEqual(['all']);
    await abas(wrapper)[2].trigger('keydown', { key: 'Home' });
    expect(wrapper.emitted('chatTabChange').at(-1)).toEqual(['me']);
    expect(document.activeElement).toBe(abas(wrapper)[0].element);
    wrapper.unmount();
  });

  it('outra tecla não troca de aba', async () => {
    const wrapper = montar('me');
    await abas(wrapper)[0].trigger('keydown', { key: 'a' });
    expect(wrapper.emitted('chatTabChange')).toBeUndefined();
    wrapper.unmount();
  });

  it('aba escolhida fora das visíveis: a primeira fica no Tab', () => {
    const wrapper = montar('mention');
    expect(abas(wrapper)[0].attributes('tabindex')).toBe('0');
    wrapper.unmount();
  });
});
