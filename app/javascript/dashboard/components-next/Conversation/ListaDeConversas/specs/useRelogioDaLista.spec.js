import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { timersAtivos, useRelogioDaLista } from '../useRelogioDaLista';

const Card = defineComponent({
  setup() {
    const agora = useRelogioDaLista();
    return () => h('span', agora.value);
  },
});

describe('useRelogioDaLista (#2202)', () => {
  it('300 cards dividem 1 timer, e o último a sair o desliga', () => {
    const cards = Array.from({ length: 300 }, () => mount(Card));
    expect(timersAtivos()).toBe(1);
    cards.forEach(card => card.unmount());
    expect(timersAtivos()).toBe(0);
  });
});
