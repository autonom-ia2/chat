import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CampoIdioma from '../campos/CampoIdioma.vue';
import { IDIOMAS_WHATSAPP, nomeDoIdioma } from '../campos/idiomasWhatsApp';

// #1423 (RT-10) — o idioma da mensagem pronta aceita qualquer código, como a
// gaveta antiga: a lista do WhatsApp inteira e "Outro idioma" com campo livre.
let wrapperAtual;
const montar = modelValue =>
  mount(CampoIdioma, {
    props: {
      rotulo: 'Idioma',
      modelValue,
      'onUpdate:modelValue': valor => {
        wrapperAtual.setProps({ modelValue: valor });
      },
    },
  });
const escolhaDe = wrapper => wrapper.findComponent({ name: 'ChoiceSelect' });
const valores = wrapper =>
  escolhaDe(wrapper)
    .props('groups')
    .flatMap(grupo => grupo.options.map(opcao => opcao.value));

describe('CampoIdioma (#1423, RT-10)', () => {
  it('a lista traz todos os idiomas do WhatsApp, pelo nome, e "Outro idioma" no fim', () => {
    wrapperAtual = montar('pt_BR');
    const lista = valores(wrapperAtual);
    IDIOMAS_WHATSAPP.forEach(codigo => expect(lista).toContain(codigo));
    expect(lista.at(-1)).toBe('__outro__');
    const fr = escolhaDe(wrapperAtual)
      .props('groups')
      .flatMap(grupo => grupo.options)
      .find(opcao => opcao.value === 'fr');
    expect(fr.label).toBe('French');
    expect(wrapperAtual.find('input[data-campo-idioma-outro]').exists()).toBe(
      false
    );
  });

  it('um código fora da lista abre no campo livre, com o valor atual', () => {
    wrapperAtual = montar('pt');
    expect(escolhaDe(wrapperAtual).props('modelValue')).toBe('__outro__');
    expect(
      wrapperAtual.find('input[data-campo-idioma-outro]').element.value
    ).toBe('pt');
  });

  it('"Outro idioma" deixa digitar qualquer código e guarda o que foi digitado', async () => {
    wrapperAtual = montar('pt_BR');
    escolhaDe(wrapperAtual).vm.$emit('update:modelValue', '__outro__');
    await wrapperAtual.vm.$nextTick();
    const campo = wrapperAtual.find('input[data-campo-idioma-outro]');
    expect(campo.exists()).toBe(true);
    await campo.setValue('yue_HK');
    expect(wrapperAtual.emitted('update:modelValue').at(-1)).toEqual([
      'yue_HK',
    ]);
    escolhaDe(wrapperAtual).vm.$emit('update:modelValue', 'es_MX');
    await wrapperAtual.vm.$nextTick();
    expect(wrapperAtual.emitted('update:modelValue').at(-1)).toEqual(['es_MX']);
    expect(wrapperAtual.find('input[data-campo-idioma-outro]').exists()).toBe(
      false
    );
  });

  it('o nome do idioma sai do navegador; código desconhecido fica sem nome', () => {
    expect(nomeDoIdioma('pt_BR', 'pt_BR')).toBe('Português (Brasil)');
    expect(nomeDoIdioma('en_GB', 'en')).toBe('British English');
    expect(nomeDoIdioma('xx', 'en')).toBe('');
    expect(nomeDoIdioma('', 'en')).toBe('');
  });

  it('com a tela em pt_BR, a lista sai em português e em ordem, sem erro', () => {
    const i18n = createI18n({ legacy: false, locale: 'pt_BR', messages: {} });
    const wrapper = mount(CampoIdioma, {
      props: { rotulo: 'Idioma', modelValue: 'pt_BR' },
      global: { plugins: [i18n] },
    });
    const todos = escolhaDe(wrapper).props('groups')[1].options;
    const nomes = todos.map(opcao => opcao.label);
    expect(nomes).toContain('Francês');
    expect([...nomes].sort((a, b) => a.localeCompare(b, 'pt-BR'))).toEqual(
      nomes
    );
  });
});
