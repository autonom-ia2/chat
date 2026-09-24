import { mount } from '@vue/test-utils';
import ChoiceSelect from './ChoiceSelect.vue';

const options = [
  { value: '', label: 'Usar padrão da conta' },
  { value: 'pt_BR', label: 'Português (Brasil)' },
  { value: 'es', label: 'Español' },
];

let wrapper;

const mountSelect = (modelValue = 'pt_BR', extra = {}) =>
  mount(ChoiceSelect, {
    props: {
      options,
      modelValue,
      ariaLabel: 'Idioma preferido',
      ...extra,
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

  it('emite change com o valor novo depois de atualizar o modelo', async () => {
    wrapper = mountSelect();
    await wrapper.get('[role="combobox"]').trigger('click');
    await wrapper.findAll('[role="option"]')[2].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([['es']]);
    expect(wrapper.emitted('change')).toEqual([['es']]);
  });

  it('não escolhe opção desabilitada e a anuncia como desabilitada', async () => {
    wrapper = mountSelect('pt_BR', {
      options: [
        { value: 'a', label: 'Alfa' },
        { value: 'b', label: 'Beta', disabled: true },
        { value: 'c', label: 'Gama' },
      ],
      modelValue: 'a',
    });
    const trigger = wrapper.get('[role="combobox"]');
    await trigger.trigger('click');
    const optionEls = wrapper.findAll('[role="option"]');
    expect(optionEls[1].attributes('aria-disabled')).toBe('true');
    await optionEls[1].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();

    await trigger.trigger('keydown', { key: 'ArrowDown' });
    expect(trigger.attributes('aria-activedescendant')).toMatch(/option-2$/);
  });

  it('aceita valor numérico, null e booleano como o select nativo', async () => {
    wrapper = mountSelect(null, {
      options: [
        { value: null, label: 'Ninguém' },
        { value: 7, label: 'Ana' },
      ],
    });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.text()).toBe('Ninguém');
    await trigger.trigger('click');
    await wrapper.findAll('[role="option"]')[1].trigger('click');
    expect(wrapper.emitted('update:modelValue')).toEqual([[7]]);

    await wrapper.setProps({ modelValue: '7' });
    expect(trigger.text()).toBe('Ana');

    await wrapper.setProps({
      options: [
        { value: true, label: 'Ligado' },
        { value: false, label: 'Desligado' },
      ],
      modelValue: false,
    });
    expect(trigger.text()).toBe('Desligado');
  });

  it('mostra o placeholder quando nenhuma opção corresponde', () => {
    wrapper = mountSelect('', {
      options: [{ value: 'x', label: 'Xis' }],
      placeholder: 'Escolha',
    });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.text()).toBe('Escolha');
    expect(trigger.get('span').classes()).toContain('text-n-slate-10');
  });

  // Dentro de <label>, o clique na lista não pode ser repassado ao botão:
  // o navegador reabriria a lista logo depois da escolha.
  it('cancela a ação padrão do clique na lista para não reabrir dentro de label', async () => {
    const label = document.createElement('label');
    document.body.appendChild(label);
    wrapper = mount(ChoiceSelect, {
      props: { options, modelValue: 'pt_BR', ariaLabel: 'Idioma preferido' },
      attachTo: label,
    });
    await wrapper.get('[role="combobox"]').trigger('click');

    const click = new MouseEvent('click', { bubbles: true, cancelable: true });
    wrapper.findAll('[role="option"]')[2].element.dispatchEvent(click);
    expect(click.defaultPrevented).toBe(true);
    expect(wrapper.emitted('change')).toEqual([['es']]);

    const listClick = new MouseEvent('click', {
      bubbles: true,
      cancelable: true,
    });
    wrapper.get('[role="listbox"]').element.dispatchEvent(listClick);
    expect(listClick.defaultPrevented).toBe(true);

    wrapper.unmount();
    wrapper = null;
    label.remove();
  });

  it('agrupa as opções com rótulo de grupo acessível', async () => {
    wrapper = mountSelect('09:00', {
      options: [],
      groups: [
        { label: 'Manhã', options: [{ value: '09:00', label: '09:00' }] },
        { label: 'Tarde', options: [{ value: '14:00', label: '14:00' }] },
      ],
    });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.text()).toBe('09:00');
    const groupEls = wrapper.findAll('[role="group"]');
    expect(groupEls).toHaveLength(2);
    const labelId = groupEls[1].attributes('aria-labelledby');
    expect(wrapper.get(`[id="${labelId}"]`).text()).toBe('Tarde');

    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await trigger.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('update:modelValue')).toEqual([['14:00']]);
  });

  it('marca inválido e desabilitado para leitor de tela', () => {
    wrapper = mountSelect('pt_BR', { invalid: true, disabled: true });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.attributes('aria-invalid')).toBe('true');
    expect(trigger.attributes('disabled')).toBeDefined();
  });

  it('versão compacta mantém área de toque de 44 px', () => {
    wrapper = mountSelect('pt_BR', { compact: true });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.classes()).toContain('min-h-8');
    expect(trigger.classes()).toContain('before:-inset-y-1.5');
  });
});
