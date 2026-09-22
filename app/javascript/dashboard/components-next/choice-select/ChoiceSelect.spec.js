import { mount } from '@vue/test-utils';
import ChoiceSelect from './ChoiceSelect.vue';

const options = [
  { value: '', label: 'Usar padrão da conta' },
  { value: 'pt_BR', label: 'Português (Brasil)' },
  { value: 'es', label: 'Español' },
];

let wrapper;

const mountSelect = (modelValue = 'pt_BR') =>
  mount(ChoiceSelect, {
    props: {
      options,
      modelValue,
      ariaLabel: 'Idioma preferido',
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
    attachTo: document.body,
  });

// O jsdom não implementa rolagem; no navegador o componente rola até a opção ativa.
beforeAll(() => {
  Element.prototype.scrollIntoView = vi.fn();
});

afterEach(() => wrapper?.unmount());

describe('ChoiceSelect', () => {
  it('não usa select nativo e mostra a opção escolhida', () => {
    wrapper = mountSelect();
    expect(wrapper.find('select').exists()).toBe(false);
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.text()).toBe('Português (Brasil)');
    expect(trigger.attributes('aria-expanded')).toBe('false');
    expect(trigger.attributes('aria-label')).toBe('Idioma preferido');
  });

  it('abre com seta para baixo na opção escolhida e confirma com Enter', async () => {
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');
    await trigger.trigger('keydown', { key: 'ArrowDown' });
    expect(trigger.attributes('aria-expanded')).toBe('true');
    expect(trigger.attributes('aria-activedescendant')).toMatch(/option-1$/);

    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await trigger.trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('update:modelValue')).toEqual([['es']]);
    expect(trigger.attributes('aria-expanded')).toBe('false');
  });

  it('escolhe a opção vazia sem desmarcar ao clicar de novo na mesma', async () => {
    wrapper = mountSelect('');
    await wrapper.get('[role="combobox"]').trigger('click');
    await wrapper.findAll('[role="option"]')[0].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();

    await wrapper.get('[role="combobox"]').trigger('click');
    await wrapper.findAll('[role="option"]')[1].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['pt_BR']]);
  });

  it('fecha com Escape sem mudar a escolha', async () => {
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');
    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await trigger.trigger('keydown', { key: 'Escape' });
    expect(trigger.attributes('aria-expanded')).toBe('false');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('acha a opção digitando o começo, sem acento', async () => {
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');
    await trigger.trigger('keydown', { key: 'e' });
    expect(trigger.attributes('aria-activedescendant')).toMatch(/option-2$/);
  });
});
