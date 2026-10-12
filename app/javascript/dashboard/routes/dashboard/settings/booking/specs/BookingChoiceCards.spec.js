import { mount } from '@vue/test-utils';
import BookingChoiceCards from '../components/BookingChoiceCards.vue';

// #1370 — o slot `option` troca só o conteúdo do cartão: o rádio de verdade, o rótulo que é o alvo
// de toque e o v-model continuam no componente. Sem o slot, o cartão é o de sempre.
const OPTIONS = [
  { value: 'a', label: 'Alfa', hint: 'Primeira', badge: 'Novo' },
  { value: 'b', label: 'Beta' },
];

const montar = (slots = {}) =>
  mount(BookingChoiceCards, {
    props: { legend: 'Escolha', options: OPTIONS, modelValue: 'a' },
    slots,
  });

describe('BookingChoiceCards', () => {
  it('without the slot renders label, badge and hint as before', () => {
    const wrapper = montar();
    const alfa = wrapper.get('[data-choice="a"]');
    expect(alfa.text()).toContain('Alfa');
    expect(alfa.text()).toContain('Novo');
    expect(alfa.text()).toContain('Primeira');
    expect(alfa.get('input').element.checked).toBe(true);
  });

  it('the option slot replaces only the card content, keeping the radio and the choice', async () => {
    const wrapper = montar({
      option: `<template #option="{ option }"><b data-proprio>{{ option.label }}!</b></template>`,
    });
    const beta = wrapper.get('[data-choice="b"]');
    expect(beta.get('[data-proprio]').text()).toBe('Beta!');
    expect(beta.text()).not.toContain('Novo');
    const radio = beta.get('input[type="radio"]');
    await radio.setValue(true);
    expect(wrapper.emitted('update:modelValue')).toEqual([['b']]);
  });
});
