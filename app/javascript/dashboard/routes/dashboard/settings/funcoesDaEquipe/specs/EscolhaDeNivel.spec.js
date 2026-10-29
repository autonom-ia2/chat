import { mount } from '@vue/test-utils';
import EscolhaDeNivel from '../guiada/EscolhaDeNivel.vue';

// #2308, especificação 14 › Acessibilidade: radiogroup com tabindex móvel; a travada não é escolhível.
const OPCOES = [
  { valor: 'none', titulo: 'Não vê' },
  { valor: 'view', titulo: 'Só olha', dentro: true },
  {
    valor: 'manage',
    titulo: 'Pode mexer',
    trava: 'Só o administrador dá isto.',
  },
];

let wrapper;

const montar = modelValue =>
  mount(EscolhaDeNivel, {
    attachTo: document.body,
    props: {
      opcoes: OPCOES,
      rotulo: 'Anúncios',
      modelValue,
      'onUpdate:modelValue': valor => wrapper.setProps({ modelValue: valor }),
    },
  });

describe('EscolhaDeNivel', () => {
  afterEach(() => wrapper.unmount());

  it('só a escolhida entra no Tab; a travada fica aria-disabled', () => {
    wrapper = montar('none');
    const radios = wrapper.findAll('[role="radio"]');
    expect(wrapper.find('[role="radiogroup"]').attributes('aria-label')).toBe(
      'Anúncios'
    );
    expect(radios.map(r => r.attributes('tabindex'))).toEqual([
      '0',
      '-1',
      '-1',
    ]);
    expect(radios[2].attributes('aria-disabled')).toBe('true');
    expect(radios[2].text()).toContain('Só o administrador dá isto.');
  });

  it('as setas trocam a escolha, pulam a travada e levam o foco', async () => {
    wrapper = montar('none');
    await wrapper
      .find('[data-nivel="none"]')
      .trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['view']);
    expect(document.activeElement).toBe(
      wrapper.find('[data-nivel="view"]').element
    );

    await wrapper
      .find('[data-nivel="view"]')
      .trigger('keydown', { key: 'ArrowDown' });
    expect(wrapper.emitted('update:modelValue')[1]).toEqual(['none']);
  });

  it('tocar na travada não muda nada', async () => {
    wrapper = montar('view');
    await wrapper.find('[data-nivel="manage"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('o radiogroup é dono só dos botões (aria-owns), e o que fica dentro da escolhida fica fora dele', () => {
    wrapper = mount(EscolhaDeNivel, {
      attachTo: document.body,
      props: { opcoes: OPCOES, rotulo: 'Anúncios', modelValue: 'view' },
      slots: { dentro: '<button role="switch" data-dentro>Extra</button>' },
    });
    const grupo = wrapper.find('[role="radiogroup"]');
    const ids = wrapper.findAll('[role="radio"]').map(r => r.attributes('id'));
    expect(grupo.attributes('aria-owns')).toBe(ids.join(' '));
    expect(new Set(ids).size).toBe(3);
    expect(wrapper.find('[data-dentro]').exists()).toBe(true);
    expect(grupo.element.contains(wrapper.find('[data-dentro]').element)).toBe(
      false
    );
  });
});
