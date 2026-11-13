import { mount } from '@vue/test-utils';
import ListaDoRamo from '../../components/criar/ListaDoRamo.vue';

// #2881 — uma lista do agente pronto por ramo (perguntas da cotação ou documentos): tirar e voltar, editar e incluir.
// A lista é a do servidor; cada mudança sai como a lista inteira nova, e quem chama grava. O campo de editar e o de
// incluir só fecham quando quem grava avisa que o servidor guardou (o segundo valor do `mudar`).
const ITENS = [
  { id: 'p1', texto: 'Qual o CNPJ da empresa?', tirada: false },
  { id: 'p2', texto: 'Qual o valor da garantia?', tirada: false },
  { id: 'p3', texto: 'Quem cuida disso?', tirada: true },
];

const montadas = [];
const montar = (props = {}) => {
  const wrapper = mount(ListaDoRamo, {
    props: {
      itens: ITENS,
      rotuloIncluir: 'Incluir pergunta',
      podeMudar: true,
      ...props,
    },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};
const item = (wrapper, id) => wrapper.get(`[data-item="${id}"]`);

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('ListaDoRamo', () => {
  it('shows every item in order, and strikes the one the owner removed', () => {
    const wrapper = montar();

    expect(
      wrapper.findAll('[data-texto-do-item]').map(texto => texto.text())
    ).toEqual(ITENS.map(({ texto }) => texto));
    expect(item(wrapper, 'p3').get('[data-texto-do-item]').classes()).toContain(
      'line-through'
    );
    expect(
      item(wrapper, 'p1').get('[data-texto-do-item]').classes()
    ).not.toContain('line-through');
  });

  it('"Remove" sends the whole list with that item removed, and never changes the list it got', async () => {
    const wrapper = montar();

    await item(wrapper, 'p1').get('[data-tirar-item]').trigger('click');

    expect(wrapper.emitted('mudar')).toEqual([
      [[{ ...ITENS[0], tirada: true }, ITENS[1], ITENS[2]]],
    ]);
    expect(ITENS[0].tirada).toBe(false);
  });

  it('a removed item offers only "Put back", which sends the whole list with it back', async () => {
    const wrapper = montar();
    const tirado = item(wrapper, 'p3');

    expect(tirado.find('[data-editar-item]').exists()).toBe(false);
    expect(tirado.get('[data-tirar-item]').attributes('aria-label')).toBe(
      'AGENTS.JORNADA.RAMOS.CONFIRA.VOLTAR_SR'
    );
    await tirado.get('[data-tirar-item]').trigger('click');

    expect(wrapper.emitted('mudar')).toEqual([
      [[ITENS[0], ITENS[1], { ...ITENS[2], tirada: false }]],
    ]);
  });

  it('"Edit" opens the text of the item, and saving sends the whole list with the new text and the same id', async () => {
    const wrapper = montar();

    await item(wrapper, 'p2').get('[data-editar-item]').trigger('click');
    const campo = wrapper.get('[data-editando] textarea');
    expect(campo.element.value).toBe('Qual o valor da garantia?');
    await campo.setValue('  Qual o valor do contrato?  ');
    await wrapper.get('[data-salvar-item]').trigger('click');

    expect(wrapper.emitted('mudar')).toHaveLength(1);
    const [lista, aoGravar] = wrapper.emitted('mudar')[0];
    expect(lista).toEqual([
      ITENS[0],
      { ...ITENS[1], texto: 'Qual o valor do contrato?' },
      ITENS[2],
    ]);
    // O campo só fecha quando quem grava avisa que o servidor guardou.
    expect(wrapper.find('[data-editando]').exists()).toBe(true);
    aoGravar();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-editando]').exists()).toBe(false);
  });

  it('when the save fails, the edit field stays open with what the owner typed', async () => {
    const wrapper = montar();

    await item(wrapper, 'p2').get('[data-editar-item]').trigger('click');
    await wrapper
      .get('[data-editando] textarea')
      .setValue('Qual o valor do contrato?');
    await wrapper.get('[data-salvar-item]').trigger('click');
    // O servidor recusou (ou a rede caiu): o pedido termina e ninguém avisa que gravou.
    await wrapper.setProps({ gravando: true });
    await wrapper.setProps({ gravando: false });

    expect(wrapper.get('[data-editando] textarea').element.value).toBe(
      'Qual o valor do contrato?'
    );
    expect(
      wrapper.get('[data-salvar-item]').attributes('aria-disabled')
    ).toBeUndefined();
  });

  it('does not save an empty text', async () => {
    const wrapper = montar();

    await item(wrapper, 'p1').get('[data-editar-item]').trigger('click');
    await wrapper.get('[data-editando] textarea').setValue('   ');
    await wrapper.get('[data-salvar-item]').trigger('click');

    expect(wrapper.emitted('mudar')).toBeUndefined();
    expect(wrapper.find('[data-editando]').exists()).toBe(true);
  });

  it('"Add" sends the whole list plus the new item, without an id (the server gives it)', async () => {
    const wrapper = montar({ exemplo: 'Escreva a pergunta' });

    await wrapper.get('[data-incluir-item]').trigger('click');
    const campo = wrapper.get('[data-incluindo] textarea');
    expect(campo.attributes('placeholder')).toBe('Escreva a pergunta');
    await campo.setValue('Já tem seguro hoje?');
    await wrapper.get('[data-confirmar-inclusao]').trigger('click');

    expect(wrapper.emitted('mudar')).toHaveLength(1);
    const [lista, aoGravar] = wrapper.emitted('mudar')[0];
    expect(lista).toEqual([
      ...ITENS,
      { texto: 'Já tem seguro hoje?', tirada: false },
    ]);
    // O campo só fecha quando quem grava avisa que o servidor guardou.
    expect(wrapper.find('[data-incluindo]').exists()).toBe(true);
    aoGravar();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('[data-incluindo]').exists()).toBe(false);
  });

  it('when the save fails, the new item field stays open with what the owner typed', async () => {
    const wrapper = montar();

    await wrapper.get('[data-incluir-item]').trigger('click');
    await wrapper
      .get('[data-incluindo] textarea')
      .setValue('Já tem seguro hoje?');
    await wrapper.get('[data-confirmar-inclusao]').trigger('click');
    // O servidor recusou (ou a rede caiu): o pedido termina e ninguém avisa que gravou.
    await wrapper.setProps({ gravando: true });
    await wrapper.setProps({ gravando: false });

    expect(wrapper.get('[data-incluindo] textarea').element.value).toBe(
      'Já tem seguro hoje?'
    );
    expect(wrapper.findAll('[data-texto-do-item]')).toHaveLength(3);
  });

  it('while a change is being saved, the buttons wait and nothing else is sent', async () => {
    const wrapper = montar({ gravando: true });
    const tirar = item(wrapper, 'p1').get('[data-tirar-item]');

    expect(tirar.attributes('aria-disabled')).toBe('true');
    expect(wrapper.get('[data-itens-do-ramo]').attributes('aria-busy')).toBe(
      'true'
    );
    await tirar.trigger('click');
    await item(wrapper, 'p1').get('[data-editar-item]').trigger('click');
    await wrapper.get('[data-incluir-item]').trigger('click');

    expect(wrapper.emitted('mudar')).toBeUndefined();
    expect(wrapper.find('[data-editando]').exists()).toBe(false);
    expect(wrapper.find('[data-incluindo]').exists()).toBe(false);
  });

  it('who cannot change only reads the list', () => {
    const wrapper = montar({ podeMudar: false });

    expect(wrapper.findAll('[data-texto-do-item]')).toHaveLength(3);
    expect(wrapper.find('[data-tirar-item]').exists()).toBe(false);
    expect(wrapper.find('[data-editar-item]').exists()).toBe(false);
    expect(wrapper.find('[data-incluir-item]').exists()).toBe(false);
  });

  it('at the limit of 20 items, says so instead of offering "Add"', () => {
    const cheia = Array.from({ length: 20 }, (_, indice) => ({
      id: `p${indice + 1}`,
      texto: `Pergunta ${indice + 1}`,
      tirada: false,
    }));
    const wrapper = montar({ itens: cheia });

    expect(wrapper.find('[data-incluir-item]').exists()).toBe(false);
    expect(wrapper.get('[data-lista-cheia]').text()).toBe(
      'AGENTS.JORNADA.RAMOS.CONFIRA.LISTA_CHEIA'
    );
  });

  it('never renders a native select', () => {
    expect(montar().find('select').exists()).toBe(false);
  });
});
