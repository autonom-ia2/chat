import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import CrmKanbanZoom from './CrmKanbanZoom.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${params.value}` : key),
  }),
}));

describe('CrmKanbanZoom', () => {
  let wrapper;
  const mountControl = (value = 100) => {
    wrapper = mount(CrmKanbanZoom, {
      props: { modelValue: value },
      attachTo: document.body,
      global: { stubs: { teleport: true } },
    });
    return wrapper;
  };
  const trigger = () => wrapper.get('button[aria-haspopup="dialog"]');
  const open = async () => {
    await trigger().trigger('click');
    await flushPromises();
  };
  const minus = () => wrapper.get('[aria-label="CRM_KANBAN.ZOOM.DECREASE"]');
  const plus = () => wrapper.get('[aria-label="CRM_KANBAN.ZOOM.INCREASE"]');

  afterEach(() => {
    wrapper?.unmount();
    document.body.innerHTML = '';
  });

  it('starts compact with the exact percentage and no hidden focusable controls', () => {
    mountControl(87);
    expect(trigger().text()).toBe('87%');
    expect(trigger().attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(1);
  });

  it('opens the approved panel with five presets and announces its current value', async () => {
    mountControl();
    await open();
    expect(trigger().attributes('aria-expanded')).toBe('true');
    expect(wrapper.get('[role="dialog"]').attributes('id')).toBe(
      trigger().attributes('aria-controls')
    );
    expect(wrapper.get('output').text()).toBe('100%');
    expect(wrapper.get('output').attributes('aria-live')).toBe('polite');
    expect(
      wrapper.findAll('button[aria-pressed]').map(button => button.text())
    ).toEqual(['80%', '90%', '100%', '110%', '120%']);
    expect(document.activeElement).toBe(wrapper.get('[role="dialog"]').element);
  });

  it('changes by one percentage point, not by the nearest preset', async () => {
    mountControl(93);
    await open();
    await minus().trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([92]);
    await wrapper.setProps({ modelValue: 92 });
    await plus().trigger('click');
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([93]);
  });

  it.each([
    [70, true, false],
    [130, false, true],
  ])(
    'disables only the bounded control at %i',
    async (value, minusDisabled, plusDisabled) => {
      mountControl(value);
      await open();
      expect(minus().element.disabled).toBe(minusDisabled);
      expect(plus().element.disabled).toBe(plusDisabled);
      await (minusDisabled ? minus() : plus()).trigger('click');
      expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    }
  );

  it.each([80, 90, 100, 110, 120])(
    'selects the %i preset directly',
    async value => {
      mountControl(87);
      await open();
      await wrapper
        .findAll('button[aria-pressed]')
        .find(button => button.text() === `${value}%`)
        .trigger('click');
      expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([value]);
    }
  );

  it('highlights only an exact preset and keeps intermediate values unselected', async () => {
    mountControl(93);
    await open();
    expect(wrapper.findAll('button[aria-pressed="true"]')).toHaveLength(0);
    await wrapper.setProps({ modelValue: 90 });
    expect(wrapper.findAll('button[aria-pressed="true"]')).toHaveLength(1);
    expect(wrapper.get('button[aria-pressed="true"]').text()).toBe('90%');
  });

  it('closes on Escape and returns focus to its trigger', async () => {
    mountControl();
    await open();
    plus().element.focus();
    await plus().trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger().element);
  });

  it('closes on an outside click without stealing focus from the clicked control', async () => {
    mountControl();
    await open();
    const outside = document.createElement('button');
    document.body.appendChild(outside);
    outside.focus();
    outside.click();
    await flushPromises();
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(document.activeElement).toBe(outside);
  });

  it('provides a keyboard exit from the last preset', async () => {
    mountControl();
    await open();
    const last = wrapper.findAll('button[aria-pressed]').at(-1);
    last.element.focus();
    await last.trigger('keydown', { key: 'Tab' });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger().element);
  });

  it('provides a reverse keyboard exit from the panel', async () => {
    mountControl();
    await open();
    await wrapper
      .get('[role="dialog"]')
      .trigger('keydown', { key: 'Tab', shiftKey: true });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(document.activeElement).toBe(trigger().element);
  });

  it('reports persistence failure instead of displaying a false saved confirmation', async () => {
    mountControl();
    await open();
    await wrapper.setProps({ persistenceFailed: true });
    expect(wrapper.get('p[role="status"]').text()).toBe(
      'CRM_KANBAN.ZOOM.SAVE_FAILED'
    );
  });
});
