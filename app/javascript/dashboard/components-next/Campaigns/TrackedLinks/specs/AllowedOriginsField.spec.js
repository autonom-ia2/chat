import { mount } from '@vue/test-utils';
import AllowedOriginsField from '../AllowedOriginsField.vue';

const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const mountField = (props = {}) =>
  mount(AllowedOriginsField, {
    props: { id: 'origins', modelValue: '', ...props },
  });

describe('AllowedOriginsField', () => {
  it('explains what to paste, why it is asked, and how to add more sites', () => {
    const wrapper = mountField();

    expect(wrapper.get('label[for="origins"]').text()).toBe(
      `${NS}.ORIGINS_LABEL`
    );
    expect(wrapper.text()).toContain(`${NS}.ORIGINS_HINT`);
    expect(wrapper.text()).toContain(`${NS}.ORIGINS_MULTI`);
    expect(wrapper.get('details summary').text()).toContain(
      `${NS}.ORIGINS_WHY_TITLE`
    );
    expect(wrapper.get('details').text()).toContain(`${NS}.ORIGINS_WHY`);
    expect(wrapper.get('textarea').attributes('aria-describedby')).toBe(
      'origins-hint'
    );
  });

  it('accepts the full page link and previews only the site that will be accepted', () => {
    const wrapper = mountField({
      modelValue:
        'https://placement.com.br/seguro-viagem?utm_source=meta\nplacement.com.br/outra-pagina\nlp.placement.com.br',
    });
    const preview = wrapper.get('[data-testid="allowed-origins-preview"]');

    expect(preview.text()).toContain(`${NS}.ORIGINS_PREVIEW`);
    const hosts = preview.findAll('span.rounded-full').map(chip => chip.text());
    expect(hosts).toEqual(['placement.com.br', 'lp.placement.com.br']);
  });

  it('shows each accepted site once, even when two lines point to it', () => {
    const wrapper = mountField({
      modelValue: 'http://localhost:3000\nhttps://localhost:3000',
    });
    const hosts = wrapper
      .get('[data-testid="allowed-origins-preview"]')
      .findAll('span.rounded-full')
      .map(chip => chip.text());

    expect(hosts).toEqual(['localhost:3000']);
  });

  it('shows no preview while the field is empty', () => {
    const wrapper = mountField();

    expect(
      wrapper.find('[data-testid="allowed-origins-preview"]').exists()
    ).toBe(false);
  });

  it('keeps errors quiet until the person leaves the field', () => {
    const untouched = mountField({ modelValue: 'minha página' });
    const touched = mountField({
      modelValue: 'minha página',
      touched: true,
    });

    expect(untouched.find('[role="alert"]').exists()).toBe(false);
    expect(untouched.get('textarea').attributes('aria-invalid')).toBe('false');
    expect(touched.get('[role="alert"]').text()).toContain(
      `${NS}.ORIGINS_INVALID`
    );
    expect(touched.get('textarea').attributes('aria-invalid')).toBe('true');
  });

  it('asks for an address when touched and empty', () => {
    const wrapper = mountField({ touched: true });

    expect(wrapper.get('[role="alert"]').text()).toBe(`${NS}.ORIGINS_REQUIRED`);
  });

  it('updates the model and reports blur', async () => {
    const wrapper = mountField();
    const textarea = wrapper.get('textarea');

    await textarea.setValue('placement.com.br');
    await textarea.trigger('blur');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      'placement.com.br',
    ]);
    expect(wrapper.emitted('blur')).toHaveLength(1);
  });

  it('can hide the label visually while keeping it for screen readers', () => {
    const wrapper = mountField({ hideLabel: true });

    expect(wrapper.get('label').classes()).toContain('sr-only');
  });
});
