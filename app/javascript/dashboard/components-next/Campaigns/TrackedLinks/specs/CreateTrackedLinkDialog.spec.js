import { mount } from '@vue/test-utils';
import CreateTrackedLinkDialog from '../CreateTrackedLinkDialog.vue';

const inboxes = [{ id: 38, name: 'WhatsApp Vendas' }];

const mountDialog = () =>
  mount(CreateTrackedLinkDialog, {
    props: { inboxes },
    attachTo: document.body,
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        ChoiceSelect: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<button type="button" role="combobox" class="choice" @click="$emit(\'update:modelValue\', 38)" />',
        },
      },
    },
  });

const fillCommon = async wrapper => {
  await wrapper.get('input[type="text"]').setValue('LP Seguro Viagem');
  await wrapper.get('.choice').trigger('click');
};

describe('CreateTrackedLinkDialog', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  it('opens on QR or direct link and creates exactly as before', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    expect(wrapper.get('input[value="direct"]').element.checked).toBe(true);

    await fillCommon(wrapper);
    await wrapper.get('#tracked-link-message').setValue(' Olá! ');
    await wrapper.get('form').trigger('submit');

    expect(wrapper.emitted('create')[0][0]).toEqual({
      name: 'LP Seguro Viagem',
      inbox_id: 38,
      usage: 'direct',
      prefilled_text: 'Olá!',
    });
    wrapper.unmount();
  });

  it('switches to website: no prefilled message, allowed pages instead', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('input[value="website"]').setValue(true);

    expect(wrapper.find('#tracked-link-message').exists()).toBe(false);
    expect(wrapper.find('#tracked-link-origins').exists()).toBe(true);
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.WEBSITE_PREVIEW_BUTTON'
    );
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.QR_AFTER_CREATE'
    );
    wrapper.unmount();
  });

  it('keeps the Create button in reach on phones: the site preview hides below md', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();

    expect(wrapper.get('aside').classes()).not.toContain('hidden');

    await wrapper.get('input[value="website"]').setValue(true);

    expect(wrapper.get('aside').classes()).toEqual(
      expect.arrayContaining(['hidden', 'md:block'])
    );
    wrapper.unmount();
  });

  it('blocks creation until the site address is readable', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('input[value="website"]').setValue(true);
    await fillCommon(wrapper);
    const submit = () => wrapper.get('button[type="submit"]');

    expect(submit().attributes('disabled')).toBeDefined();

    const origins = wrapper.get('#tracked-link-origins');
    await origins.setValue('minha página');
    await origins.trigger('blur');
    expect(submit().attributes('disabled')).toBeDefined();
    expect(origins.attributes('aria-invalid')).toBe('true');
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.ORIGINS_INVALID'
    );

    await origins.setValue(
      Array.from({ length: 6 }, (_, i) => `https://s${i}.com.br`).join('\n')
    );
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.ORIGINS_TOO_MANY'
    );
    expect(submit().attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });

  it('emits the website payload with normalized origins', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('input[value="website"]').setValue(true);
    await fillCommon(wrapper);
    await wrapper
      .get('#tracked-link-origins')
      .setValue('https://Placement.com.br/seguro-viagem\nplacement.com.br');
    await wrapper.get('form').trigger('submit');

    expect(wrapper.emitted('create')[0][0]).toEqual({
      name: 'LP Seguro Viagem',
      inbox_id: 38,
      usage: 'website',
      allowed_origins: ['https://placement.com.br'],
    });
    wrapper.unmount();
  });

  it('tells what is missing next to the disabled Create button', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('input[value="website"]').setValue(true);
    const hint = () =>
      wrapper.find('[data-testid="tracked-link-create-missing"]');
    const submit = () => wrapper.get('button[type="submit"]');

    expect(submit().attributes('disabled')).toBeDefined();
    expect(hint().text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.CREATE_MISSING'
    );
    expect(submit().attributes('aria-describedby')).toBe(
      'tracked-link-create-missing'
    );

    await fillCommon(wrapper);
    expect(hint().exists()).toBe(true);

    await wrapper.get('#tracked-link-origins').setValue('placement.com.br');
    expect(hint().exists()).toBe(false);
    expect(submit().attributes('disabled')).toBeUndefined();
    expect(submit().attributes('aria-describedby')).toBeUndefined();
    wrapper.unmount();
  });

  it('marks the chosen usage with a check and keeps focus as a separate ring', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    const card = id => wrapper.get(`[data-testid="tracked-link-usage-${id}"]`);
    const hasCheck = id =>
      card(id)
        .find('[data-testid="tracked-link-usage-check"] .i-lucide-check')
        .exists();

    expect(hasCheck('direct')).toBe(true);
    expect(hasCheck('website')).toBe(false);
    expect(card('direct').classes()).toEqual(
      expect.arrayContaining(['outline-2', 'outline-n-blue-9', 'bg-n-blue-2'])
    );
    expect(card('website').classes()).toEqual(
      expect.arrayContaining([
        'ring-offset-2',
        'has-[:focus-visible]:ring-2',
        'outline-1',
      ])
    );

    await wrapper.get('input[value="website"]').setValue(true);
    expect(hasCheck('website')).toBe(true);
    expect(hasCheck('direct')).toBe(false);
    wrapper.unmount();
  });

  it('moves focus to the WhatsApp choice when its label is clicked', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('#tracked-link-inbox-label').trigger('click');

    expect(document.activeElement).toBe(wrapper.get('.choice').element);
    wrapper.unmount();
  });

  it('resets back to QR mode every time it opens', async () => {
    const wrapper = mountDialog();
    await wrapper.vm.open();
    await wrapper.get('input[value="website"]').setValue(true);
    await wrapper.vm.open();

    expect(wrapper.get('input[value="direct"]').element.checked).toBe(true);
    expect(wrapper.find('#tracked-link-origins').exists()).toBe(false);
    wrapper.unmount();
  });
});
