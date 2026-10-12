import { mount } from '@vue/test-utils';
import BookingThemeToggle from '../components/BookingThemeToggle.vue';
import BookingChoiceCards from '../components/BookingChoiceCards.vue';
import PublicChoiceCards from '../../../../../../public_booking_v2/components/ChoiceCards.vue';

// #1310: rádio escondido (`sr-only` = position absolute) sem ancestral
// posicionado fica preso ao documento, fora da área que rola no painel. Ao
// receber o foco, o navegador rola a JANELA inteira para mostrá-lo e o painel
// "quebra" (sobe e deixa uma faixa branca). O rótulo de cada opção tem de ser
// o ancestral posicionado (`relative`). O jsdom não carrega o Tailwind, então
// este teste é trava de regressão da classe; o efeito foi reproduzido e
// conferido no navegador.

const OPTIONS = [
  { value: 'a', label: 'A' },
  { value: 'b', label: 'B' },
];

const cases = [
  ['BookingThemeToggle', BookingThemeToggle, { modelValue: 'light' }],
  [
    'BookingChoiceCards',
    BookingChoiceCards,
    { modelValue: 'a', options: OPTIONS, legend: 'L' },
  ],
  [
    'ChoiceCards (página pública, também montada na prévia)',
    PublicChoiceCards,
    { modelValue: 'a', options: OPTIONS, legend: 'L', name: 'n' },
  ],
];

describe('rádio escondido preso ao próprio rótulo', () => {
  it.each(cases)('%s', (_name, component, props) => {
    const wrapper = mount(component, { props });
    const hidden = wrapper.findAll('input.sr-only');

    expect(hidden.length).toBeGreaterThan(0);
    hidden.forEach(input => {
      const label = input.element.closest('label');
      expect(label).not.toBeNull();
      expect(label.classList.contains('relative')).toBe(true);
    });
  });
});
