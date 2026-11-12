import { mount } from '@vue/test-utils';
import CampoDeTelefone from '../mais/CampoDeTelefone.vue';

let wrapper;
const montar = (modelValue = '', extra = {}) => {
  wrapper = mount(CampoDeTelefone, {
    props: {
      modelValue,
      label: 'Telefone',
      rotuloDoPais: 'País do telefone',
      ...extra,
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

// #2896 — o que a tela de quem usa pode pedir a mais. Sem pedir, nada muda.
describe('CampoDeTelefone: opções de quem usa (#2896)', () => {
  it('sem pedir nada: 40 px de altura, sem marca de erro', () => {
    montar();
    expect(numero().classes()).toContain('h-10');
    expect(numero().classes()).not.toContain('!h-11');
    expect(numero().attributes('aria-invalid')).toBeUndefined();
    expect(numero().attributes('aria-describedby')).toBeUndefined();
    expect(pais().attributes('aria-invalid')).toBeUndefined();
  });

  it('erroDescritoPor: o campo fica inválido e aponta para a frase de quem usa, sem repeti-la', async () => {
    montar('', { erroDescritoPor: 'frase-de-fora' });
    expect(numero().attributes('aria-invalid')).toBe('true');
    expect(numero().attributes('aria-describedby')).toBe('frase-de-fora');
    expect(numero().classes()).toContain('error');
    expect(wrapper.findAll('p')).toHaveLength(0);
    await wrapper.setProps({ erroDescritoPor: '' });
    expect(numero().attributes('aria-invalid')).toBeUndefined();
    expect(numero().attributes('aria-describedby')).toBeUndefined();
  });

  it('alto: o número e o país ficam com 44 px', () => {
    montar('', { alto: true });
    expect(numero().classes()).toContain('!h-11');
    expect(pais().element.parentElement.parentElement.className).toContain(
      '[&_[role=combobox]]:h-11'
    );
  });

  it('comoEscrito: o número que ainda não vale sai com o código do país e os dígitos', async () => {
    montar('', { comoEscrito: true });
    await numero().setValue('1198');
    expect(wrapper.props('modelValue')).toBe('+551198');
    await numero().setValue('11987654321');
    expect(wrapper.props('modelValue')).toBe('+5511987654321');
    await numero().setValue('');
    expect(wrapper.props('modelValue')).toBe('');
  });

  it('comoEscrito: o + sem país claro sai como a pessoa escreveu', async () => {
    montar('', { comoEscrito: true });
    await numero().setValue('+800 1234');
    expect(numero().element.value).toBe('+800 1234');
    expect(wrapper.props('modelValue')).toBe('+800 1234');
  });

  it('comoEscrito: o número que chega sem + fica no Brasil e não é reescrito sozinho', () => {
    montar('(31) 2345-678', { comoEscrito: true });
    expect(pais().text()).toBe('🇧🇷 +55');
    expect(numero().element.value).toBe('(31) 2345-678');
    expect(wrapper.props('modelValue')).toBe('(31) 2345-678');
  });
});
