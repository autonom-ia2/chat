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

  it('digitar + e o código à mão troca o país e segue no número nacional', async () => {
    montar();
    const campo = numero();
    // Uma tecla por vez, como quem digita.
    await [...'+5511987654321'].reduce(
      (anterior, tecla) =>
        anterior.then(() => campo.setValue(campo.element.value + tecla)),
      Promise.resolve()
    );
    expect(pais().text()).toBe('🇧🇷 +55');
    expect(campo.element.value).toBe('(11) 98765-4321');
    expect(wrapper.props('modelValue')).toBe('+5511987654321');
  });

  it('+ sem país claro fica como está e não vale como número', async () => {
    montar();
    await numero().setValue('+800 1234 5678');
    expect(numero().element.value).toBe('+800 1234 5678');
    expect(wrapper.props('modelValue')).toBe('');
  });

  it('apagar logo depois do separador apaga o dígito de antes', async () => {
    montar('+5511987654321');
    const campo = numero().element;
    // "(11) 98765-|4321" → o navegador apaga o "-" e o cursor fica no mesmo lugar.
    campo.value = '(11) 987654321';
    campo.setSelectionRange(10, 10);
    campo.dispatchEvent(
      new InputEvent('input', { inputType: 'deleteContentBackward' })
    );
    await wrapper.vm.$nextTick();
    // Sai o "5" de antes do separador; o número segue sendo formatado como celular.
    expect(campo.value).toBe('(11) 98764-321');
    expect(campo.selectionStart).toBe(9);
  });

  it('erro ligado ao campo para o leitor de tela', async () => {
    montar();
    await wrapper.setProps({ erro: 'Digite um telefone' });
    const campo = numero();
    const mensagem = wrapper.get(`#${campo.attributes('aria-describedby')}`);
    expect(mensagem.text()).toBe('Digite um telefone');
    expect(campo.attributes('aria-invalid')).toBe('true');
  });
});
