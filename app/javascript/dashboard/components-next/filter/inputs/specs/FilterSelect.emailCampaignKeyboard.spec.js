import { mount, DOMWrapper } from '@vue/test-utils';
import { defineComponent, nextTick, reactive, ref } from 'vue';
import { createStore } from 'vuex';
import FilterSelect from '../FilterSelect.vue';
import FilterButton from 'next/button/Button.vue';
import { provideDropdownTeleport } from 'next/dropdown-menu/base/provider';
import { DROPDOWN_SEARCH_THRESHOLD } from '../../helper/filterHelper';

const options = [
  { label: 'Statuses', value: 'heading', disabled: true },
  { label: 'All', value: 'all' },
  { label: 'Active', value: 'active' },
  { label: 'Paused', value: 'paused' },
];

let wrapper;
const mountSelect = ({ teleport = false, custom = false, ...props } = {}) => {
  wrapper = mount(
    defineComponent({
      components: { FilterSelect, FilterButton },
      setup() {
        if (teleport) provideDropdownTeleport();
        return {
          props: reactive(props),
          custom,
          selected: ref(props.modelValue ?? 'active'),
        };
      },
      template: `
        <div>
          <button data-before>Before</button>
          <FilterSelect v-model="selected" v-bind="props" aria-label="Campaign status">
            <template v-if="custom" #trigger="{ toggle, keyboardAttrs, expanded }">
              <FilterButton v-bind="keyboardAttrs" type="button" :data-expanded="expanded" @click="toggle">
                Custom status
              </FilterButton>
            </template>
          </FilterSelect>
          <button data-after>After</button>
        </div>`,
    }),
    {
      attachTo: document.body,
      global: {
        plugins: [createStore({ getters: { 'accounts/isRTL': () => false } })],
      },
    }
  );
  return wrapper.findComponent(FilterSelect).get('button');
};

// jsdom does not synthesize native click/Tab defaults from keyboard events.
// Enter/Space exercise the component's explicit handlers; Tab checks cancellation
// and the focus origin, with the browser's eventual traversal left to parent QA.
const press = async (key, modifiers = {}) => {
  const event = new KeyboardEvent('keydown', {
    key,
    bubbles: true,
    cancelable: true,
    ...modifiers,
  });
  document.activeElement.dispatchEvent(event);
  await nextTick();
  return event;
};

afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
});

describe.each([false, true])(
  'keyboardNavigation with teleport=%s',
  teleport => {
    it.each([false, true])(
      'opens once and restores focus, custom=%s',
      async custom => {
        const trigger = mountSelect({
          options,
          keyboardNavigation: true,
          teleport,
          custom,
        });
        trigger.element.focus();
        expect(trigger.attributes('aria-expanded')).toBe('false');
        expect(trigger.attributes('aria-label')).toBe('Campaign status');
        expect((await press('Enter')).defaultPrevented).toBe(true);
        const menu = document.querySelector('[role="listbox"]');
        expect(menu).not.toBeNull();
        expect(wrapper.element.contains(menu)).toBe(!teleport);
        expect(menu.getAttribute('aria-label')).toBe('Campaign status');
        expect(trigger.attributes('aria-controls')).toBe(menu.id);
        expect(trigger.attributes('aria-expanded')).toBe('true');
        if (custom) expect(trigger.attributes('data-expanded')).toBe('true');
        expect(document.activeElement.textContent).toBe('Active');
        expect(document.activeElement.tagName).toBe('BUTTON');
        expect(document.activeElement.getAttribute('aria-selected')).toBe(
          'true'
        );
        expect(document.querySelectorAll('[role="option"]')).toHaveLength(3);
        await press('Escape');
        expect(document.querySelector('[role="listbox"]')).toBeNull();
        expect(document.activeElement).toBe(trigger.element);
        expect(trigger.attributes('aria-expanded')).toBe('false');
        await press(' ');
        expect(document.activeElement.textContent).toBe('Active');
      }
    );

    it.each(['Enter', ' '])('navigates and selects once with %s', async key => {
      const trigger = mountSelect({
        options,
        keyboardNavigation: true,
        teleport,
      });
      trigger.element.focus();
      await press('ArrowDown');
      await press('ArrowDown');
      expect(document.activeElement.textContent).toBe('Paused');
      await press('ArrowDown');
      expect(document.activeElement.textContent).toBe('All');
      await press('ArrowUp');
      expect(document.activeElement.textContent).toBe('Paused');
      await press('Home');
      expect(document.activeElement.textContent).toBe('All');
      await press('End');
      expect(document.activeElement.textContent).toBe('Paused');
      await press(key);
      expect(
        wrapper.findComponent(FilterSelect).emitted('update:modelValue')
      ).toEqual([['paused']]);
      expect(document.querySelector('[role="listbox"]')).toBeNull();
      expect(document.activeElement).toBe(trigger.element);
      await press('ArrowUp');
      expect(document.activeElement.textContent).toBe('Paused');
    });

    it.each([false, true])(
      'leaves Tab unprevented, shift=%s',
      async shiftKey => {
        const trigger = mountSelect({
          options,
          keyboardNavigation: true,
          teleport,
        });
        trigger.element.focus();
        await press('Enter');
        expect((await press('Tab', { shiftKey })).defaultPrevented).toBe(false);
        expect(document.querySelector('[role="listbox"]')).toBeNull();
        expect(document.activeElement).toBe(trigger.element);
        const destination = wrapper.get(
          shiftKey ? '[data-before]' : '[data-after]'
        );
        destination.element.focus();
        expect(document.activeElement).toBe(destination.element);
      }
    );

    it('keeps long-list search editable and navigates filtered results', async () => {
      const longOptions = [
        ...options,
        ...Array.from({ length: DROPDOWN_SEARCH_THRESHOLD }, (_, index) => ({
          label: `Campaign ${index}`,
          value: index,
        })),
      ];
      const trigger = mountSelect({
        options: longOptions,
        keyboardNavigation: true,
        teleport,
      });
      trigger.element.focus();
      await press('Enter');
      await press('Home');
      await press('ArrowUp');
      const search = new DOMWrapper(document.querySelector('input'));
      expect(document.activeElement).toBe(search.element);
      expect(search.attributes('aria-label')).toBe(
        'COMBOBOX.SEARCH_PLACEHOLDER'
      );
      expect((await press('Home')).defaultPrevented).toBe(false);
      expect((await press('End')).defaultPrevented).toBe(false);
      expect((await press(' ')).defaultPrevented).toBe(false);
      expect((await press('Enter')).defaultPrevented).toBe(true);
      await search.setValue('Paused');
      expect(document.querySelectorAll('[role="option"]')).toHaveLength(1);
      expect(document.activeElement).toBe(search.element);
      await press('ArrowDown');
      expect(document.activeElement.textContent).toBe('Paused');
      await press('ArrowUp');
      await search.setValue('no-matching-result');
      expect(document.querySelectorAll('[role="option"]')).toHaveLength(0);
      await press('ArrowDown');
      expect(document.activeElement).toBe(search.element);
      await search.setValue('   ');
      expect(document.querySelectorAll('[role="option"]')).toHaveLength(
        longOptions.length - 1
      );
      await press('ArrowUp');
      expect(document.activeElement.textContent).toBe(
        `Campaign ${DROPDOWN_SEARCH_THRESHOLD - 1}`
      );
      await press('Escape');
      expect(document.activeElement).toBe(trigger.element);
    });

    it('focuses the first available option and preserves custom pointer toggle', async () => {
      const trigger = mountSelect({
        options,
        modelValue: 'missing',
        keyboardNavigation: true,
        teleport,
        custom: true,
      });
      await trigger.trigger('click');
      expect(document.activeElement.textContent).toBe('All');
      await new DOMWrapper(document.activeElement).trigger('click');
      expect(document.activeElement).toBe(trigger.element);
      expect(
        wrapper.findComponent(FilterSelect).emitted('update:modelValue')
      ).toEqual([['all']]);
      await trigger.trigger('click');
      await trigger.trigger('click');
      expect(document.querySelector('[role="listbox"]')).toBeNull();
    });
    it('keeps an empty list escapable without selectable placeholders', async () => {
      const trigger = mountSelect({
        options: [],
        keyboardNavigation: true,
        teleport,
      });
      trigger.element.focus();
      await press('Enter');
      expect(document.activeElement.getAttribute('role')).toBe('listbox');
      expect(document.querySelector('[role="option"]')).toBeNull();
      await press('ArrowDown');
      await press('Escape');
      expect(document.activeElement).toBe(trigger.element);
      expect(document.querySelector('[role="listbox"]')).toBeNull();
    });
  }
);

describe('default behavior stays unchanged', () => {
  it('retains non-button options, sections, pointer selection and no keyboard opt-in', async () => {
    const trigger = mountSelect({ options });
    trigger.element.focus();
    expect((await press('ArrowDown')).defaultPrevented).toBe(false);
    expect(trigger.attributes('aria-expanded')).toBeUndefined();
    expect(wrapper.find('.n-dropdown-body').exists()).toBe(false);
    await trigger.trigger('click');
    expect(wrapper.find('.n-dropdown-section').text()).toContain('Statuses');
    expect(wrapper.findAll('.n-dropdown-item > div')).toHaveLength(3);
    expect(document.querySelector('[data-dropdown-menu]')).toBeNull();
    await wrapper.findAll('.n-dropdown-item > div')[2].trigger('click');
    expect(
      wrapper.findComponent(FilterSelect).emitted('update:modelValue')
    ).toEqual([['paused']]);
    expect(wrapper.find('.n-dropdown-body').exists()).toBe(false);
  });

  it('retains threshold, search autofocus, whitespace and disabled-header handling', async () => {
    const longOptions = Array.from(
      { length: DROPDOWN_SEARCH_THRESHOLD },
      (_, index) => ({
        label: `Campaign ${index}`,
        value: index,
      })
    );
    const trigger = mountSelect({ options: longOptions });
    await trigger.trigger('click');
    expect(wrapper.find('input').exists()).toBe(false);
    await trigger.trigger('click');
    wrapper.vm.props.options = [...options, ...longOptions];
    await nextTick();
    await trigger.trigger('click');
    const search = wrapper.get('input');
    expect(document.activeElement).toBe(search.element);
    await search.setValue('   ');
    expect(wrapper.find('.n-dropdown-section').text()).toContain('Statuses');
    await search.setValue('Statuses');
    expect(wrapper.find('li.select-none').exists()).toBe(false);
    expect(wrapper.findAll('.n-dropdown-item')).toHaveLength(1);
    expect(wrapper.find('.n-dropdown-item [disabled]').exists()).toBe(true);
  });
});
