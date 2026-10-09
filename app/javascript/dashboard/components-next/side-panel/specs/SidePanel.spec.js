import { flushPromises, mount } from '@vue/test-utils';
import {
  Comment,
  h,
  nextTick,
  onBeforeUnmount,
  onMounted,
  onUpdated,
} from 'vue';
import SidePanel from '../SidePanel.vue';

const ButtonStub = {
  inheritAttrs: false,
  props: { label: { type: [String, Number], default: '' } },
  emits: ['click'],
  template:
    '<button v-bind="$attrs" type="button" @click="$emit(\'click\')">{{ label }}<slot /></button>',
};

const callTransitionHook = hook => {
  if (Array.isArray(hook)) {
    hook.forEach(callback => callback());
    return;
  }
  if (typeof hook === 'function') hook();
};

const hasRenderableContent = slots =>
  (slots.default?.() || []).some(vnode => vnode.type !== Comment);

// Keep the lifecycle hooks observable in jsdom. The real CSS transition has no duration there,
// which can restore focus before the assertion reaches the next tick.
const LifecycleTransitionStub = {
  inheritAttrs: false,
  setup(_, { attrs, slots }) {
    let isVisible = false;
    let leaveTimer;

    const emitEnter = () => callTransitionHook(attrs.onAfterEnter);
    const emitLeave = () => {
      leaveTimer = setTimeout(() => callTransitionHook(attrs.onAfterLeave), 0);
    };

    onMounted(() => {
      isVisible = hasRenderableContent(slots);
      if (isVisible) emitEnter();
    });

    onUpdated(() => {
      const nextVisible = hasRenderableContent(slots);
      if (isVisible && !nextVisible) {
        isVisible = false;
        emitLeave();
      } else if (!isVisible && nextVisible) {
        isVisible = true;
        emitEnter();
      }
    });

    onBeforeUnmount(() => clearTimeout(leaveTimer));

    return () => h('div', slots.default?.());
  },
};

const mountSidePanel = () =>
  mount(SidePanel, {
    attachTo: document.body,
    props: { title: 'Painel de teste' },
    slots: {
      default: `
        <div>
          <button data-test="first" data-autofocus>First</button>
          <button data-test="last">Last</button>
        </div>
      `,
    },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: ButtonStub,
        TeleportWithDirection: { template: '<div><slot /></div>' },
        Transition: LifecycleTransitionStub,
      },
    },
  });

const openSidePanel = async wrapper => {
  wrapper.vm.open();
  await flushPromises();
  await vi.waitFor(() => {
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
  });
  await vi.waitFor(() => {
    expect(document.activeElement).toBe(
      wrapper.get('[data-autofocus]').element
    );
  });
};

describe('SidePanel focus lifecycle (D9/F0)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('focuses data-autofocus after enter and locks page scroll', async () => {
    const wrapper = mountSidePanel();
    await openSidePanel(wrapper);

    await vi.waitFor(() => {
      expect(document.activeElement).toBe(
        wrapper.get('[data-test="first"]').element
      );
    });
    expect(document.body.style.overflow).toBe('hidden');
    wrapper.unmount();
  });

  it('keeps Tab and Shift+Tab inside the open panel', async () => {
    const wrapper = mountSidePanel();
    await openSidePanel(wrapper);
    const close = wrapper.get('[role="dialog"] header button').element;
    const last = wrapper.get('[data-test="last"]').element;

    last.focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Tab', bubbles: true })
    );
    expect(document.activeElement).toBe(close);

    close.focus();
    document.dispatchEvent(
      new KeyboardEvent('keydown', {
        key: 'Tab',
        shiftKey: true,
        bubbles: true,
      })
    );
    expect(document.activeElement).toBe(last);
    wrapper.unmount();
  });

  it('restores the opener only after afterLeave and emits close once', async () => {
    const opener = document.createElement('button');
    document.body.appendChild(opener);
    opener.focus();
    const wrapper = mountSidePanel();
    await openSidePanel(wrapper);

    wrapper.vm.close();
    await nextTick();

    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(document.activeElement).not.toBe(opener);

    await vi.waitFor(() => {
      expect(wrapper.emitted('afterLeave')).toHaveLength(1);
    });
    expect(document.activeElement).toBe(opener);

    wrapper.unmount();
    opener.remove();
  });

  it('closes from Escape and unlocks scroll without a second close', async () => {
    const wrapper = mountSidePanel();
    await openSidePanel(wrapper);

    document.dispatchEvent(
      new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
    );
    expect(wrapper.emitted('close')).toHaveLength(1);

    await vi.waitFor(() => {
      expect(wrapper.emitted('afterLeave')).toHaveLength(1);
    });
    expect(document.body.style.overflow).not.toBe('hidden');
    wrapper.unmount();
  });
});
