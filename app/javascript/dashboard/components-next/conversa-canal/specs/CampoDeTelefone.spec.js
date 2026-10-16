import { mount } from '@vue/test-utils';
import CampoDeTelefone from '../mais/CampoDeTelefone.vue';

let wrapper;
const montar = (modelValue = '') => {
  wrapper = mount(CampoDeTelefone, {
    props: {
      modelValue,
      label: 'Telefone',
      rotuloDoPais: 'País do telefone',
      'onUpdate:modelValue': valor => wrapper.setProps({ modelValue: valor }),
    },
    attachTo: document.body,
  });
  return wrapper;
};
const numero = () => wrapper.get('[data-numero-do-telefone] input');
const pais = () => wrapper.get('[role="combobox"]');

beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => wrapper?.unmount());

describe('CampoDeTelefone (#1702)', () => {
  it('começa no Brasil, formata ao digitar e devolve o número completo', async () => {
    montar();
    expect(pais().text()).toBe('🇧🇷 +55');
    await numero().setValue('11987654321');
    expect(numero().element.value).toBe('(11) 98765-4321');
    expect(wrapper.props('modelValue')).toBe('+5511987654321');
  });

  it('número incompleto ou letra: vazio, e a letra não fica no campo', async () => {
    montar();
    await numero().setValue('1198');
    expect(wrapper.props('modelValue')).toBe('');
    await numero().setValue('(11) 98a');
    expect(numero().element.value).toBe('(11) 98');
  });

  it('número colado com + troca o país', async () => {
    montar();
    await numero().setValue('+351 912 345 678');
    expect(pais().text()).toBe('🇵🇹 +351');
    expect(wrapper.props('modelValue')).toBe('+351912345678');
  });

  it('contato escolhido da base chega completo e preenche país e número', async () => {
    montar();
    await wrapper.setProps({ modelValue: '+12025550123' });
    expect(pais().text()).toBe('🇺🇸 +1');
    expect(numero().element.value).toBe('(202) 555-0123');
  });
});
