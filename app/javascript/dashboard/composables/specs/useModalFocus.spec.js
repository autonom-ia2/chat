import { mount } from '@vue/test-utils';
import { defineComponent, ref } from 'vue';
import { focusableIn, useModalFocus } from '../useModalFocus';

const FocusHarness = defineComponent({
  setup() {
    const container = ref(null);
    const controls = useModalFocus({ container });

    return { container, ...controls };
  },
  template: `
    <section ref="container" data-test="container" tabindex="-1">
      <button data-test="first">First</button>
      <a data-test="link" href="/next">Link</a>
      <button data-test="last">Last</button>
    </section>
  `,
});

describe('useModalFocus (D9/F0)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('exposes focusableIn and traps Tab and Shift+Tab only after activation', () => {
    const wrapper = mount(FocusHarness, { attachTo: document.body });
    const container = wrapper.get('[data-test="container"]').element;
    const first = wrapper.get('[data-test="first"]').element;
    const last = wrapper.get('[data-test="last"]').element;
    const outside = document.createElement('button');
    document.body.appendChild(outside);

    expect(focusableIn(container)).toEqual([
      first,
      wrapper.get('[data-test="link"]').element,
      last,
    ]);

    outside.focus();
    wrapper.vm.activate();
    expect(document.activeElement).toBe(outside);

    last.focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Tab', bubbles: true })
    );
    expect(document.activeElement).toBe(first);

    first.focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey: true,
        bubbles: true,
      })
    );
    expect(document.activeElement).toBe(last);

    wrapper.vm.deactivate();
    wrapper.unmount();
    outside.remove();
  });
});
