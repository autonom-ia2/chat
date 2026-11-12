import { shallowMount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import MacroProperties from '../MacroProperties.vue';

withFullI18n();

const mountComponent = props =>
  shallowMount(MacroProperties, {
    props: {
      macroName: 'Close conversation',
      macroVisibility: 'personal',
      ...props,
    },
    global: {
      provide: {
        v$: {
          macro: {
            name: {
              $error: false,
            },
          },
        },
      },
      stubs: {
        WootInput: true,
        NextButton: true,
        Icon: true,
      },
    },
  });

const saveButton = wrapper => wrapper.findComponent({ name: 'NextButton' });

describe('MacroProperties.vue', () => {
  it('allows administrators to select public visibility', async () => {
    const wrapper = mountComponent({ canManagePublicMacros: true });
    const publicButton = wrapper.findAll('button')[0];

    await publicButton.trigger('click');

    expect(publicButton.attributes('disabled')).toBeUndefined();
    expect(wrapper.emitted('update:visibility')?.[0]).toEqual(['global']);
  });

  it('disables public visibility for agents with helper copy', async () => {
    const wrapper = mountComponent({ canManagePublicMacros: false });
    const publicButton = wrapper.findAll('button')[0];

    await publicButton.trigger('click');

    expect(publicButton.attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('update:visibility')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'Only administrators can create public macros.'
    );
  });

  it('keeps existing public macros visibly selected when public is disabled', () => {
    const wrapper = mountComponent({
      canManagePublicMacros: false,
      macroVisibility: 'global',
    });

    expect(wrapper.findComponent({ name: 'Icon' }).exists()).toBe(true);
  });

  // #2451: a macro com webhook, sem integration_manage, não salva e a tela diz por quê.
  it('locks saving and shows the reason when given one', () => {
    const wrapper = mountComponent({ lockedReason: 'Precisa de Integrações' });

    expect(wrapper.text()).toContain('Precisa de Integrações');
    expect(saveButton(wrapper).vm.$attrs.disabled).toBe(true);
  });

  it('saves normally without a lock reason', () => {
    const wrapper = mountComponent();

    expect(saveButton(wrapper).vm.$attrs.disabled).toBe(false);
  });

  it('shows existing public macros as read-only for agents', async () => {
    const wrapper = mountComponent({
      canManagePublicMacros: false,
      macroVisibility: 'global',
      readOnly: true,
    });
    const [publicButton, privateButton] = wrapper.findAll('button');

    await privateButton.trigger('click');

    expect(publicButton.attributes('disabled')).toBeDefined();
    expect(privateButton.attributes('disabled')).toBeDefined();
    expect(wrapper.emitted('update:visibility')).toBeUndefined();
    expect(wrapper.text()).toContain(
      'Only administrators can edit public macros.'
    );
  });
});
