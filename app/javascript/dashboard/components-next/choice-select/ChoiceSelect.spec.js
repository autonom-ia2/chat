import { defineComponent } from 'vue';
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
    expect(wrapper.get('[role="combobox"]').text()).toBe('Escolha');
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

  it('largura mínima estável fora do compacto, como o select nativo', async () => {
    wrapper = mountSelect();
    expect(wrapper.classes()).toContain('min-w-40');
    await wrapper.setProps({ compact: true });
    expect(wrapper.classes()).not.toContain('min-w-40');
  });

  it('altura padrão de 40 px como os campos, área de toque de 44 px', () => {
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.classes()).toContain('h-10');
    expect(trigger.classes()).toContain('before:-inset-y-0.5');
    expect(trigger.classes()).not.toContain('min-h-11');
  });

  it('versão compacta de 32 px mantém área de toque de 44 px', () => {
    wrapper = mountSelect('pt_BR', { compact: true });
    const trigger = wrapper.get('[role="combobox"]');
    expect(trigger.classes()).toContain('h-8');
    expect(trigger.classes()).toContain('before:-inset-y-1.5');
    expect(trigger.classes()).not.toContain('h-10');
  });

  it('opções da lista continuam com 44 px', async () => {
    wrapper = mountSelect();
    await wrapper.get('[role="combobox"]').trigger('click');
    expect(wrapper.findAll('[role="option"]')[0].classes()).toContain(
      'min-h-11'
    );
  });

  describe('lista na camada do topo (Popover API)', () => {
    const { showPopover, hidePopover } = HTMLElement.prototype;

    beforeEach(() => {
      HTMLElement.prototype.showPopover = vi.fn();
      HTMLElement.prototype.hidePopover = vi.fn();
    });

    afterEach(() => {
      HTMLElement.prototype.showPopover = showPopover;
      HTMLElement.prototype.hidePopover = hidePopover;
    });

    it('mostra a lista como popover ao abrir e esconde ao fechar', async () => {
      wrapper = mountSelect();
      const list = wrapper.get('[role="listbox"]');
      expect(list.attributes('popover')).toBe('manual');

      await wrapper.get('[role="combobox"]').trigger('click');
      expect(HTMLElement.prototype.showPopover).toHaveBeenCalledTimes(1);
      expect(HTMLElement.prototype.showPopover.mock.contexts[0]).toBe(
        list.element
      );

      await wrapper
        .get('[role="combobox"]')
        .trigger('keydown', { key: 'Escape' });
      expect(HTMLElement.prototype.hidePopover).toHaveBeenCalledTimes(1);
      expect(HTMLElement.prototype.hidePopover.mock.contexts[0]).toBe(
        list.element
      );
    });

    it('posiciona a lista pelo botão, com a largura mínima dele', async () => {
      wrapper = mountSelect();
      const trigger = wrapper.get('[role="combobox"]');
      trigger.element.getBoundingClientRect = () => ({
        top: 100,
        bottom: 140,
        left: 30,
        right: 230,
        width: 200,
        height: 40,
      });
      await trigger.trigger('click');
      const { style } = wrapper.get('[role="listbox"]').element;
      expect(style.top).toBe('144px');
      expect(style.left).toBe('30px');
      expect(style.minWidth).toBe('200px');
      expect(style.maxHeight).toBe('320px');
    });

    describe('com a janela baixa', () => {
      const { innerHeight } = window;
      const manyOptions = Array.from({ length: 12 }, (_, index) => ({
        value: `v${index}`,
        label: `Opção ${index}`,
      }));
      const openAt = async (top, height) => {
        window.innerHeight = height;
        wrapper = mountSelect('v0', { options: manyOptions });
        const trigger = wrapper.get('[role="combobox"]');
        trigger.element.getBoundingClientRect = () => ({
          top,
          bottom: top + 40,
          left: 30,
          right: 230,
          width: 200,
          height: 40,
        });
        await trigger.trigger('click');
        return wrapper.get('[role="listbox"]').element.style;
      };

      afterEach(() => {
        window.innerHeight = innerHeight;
      });

      it('abre para cima e limita a altura ao espaço disponível', async () => {
        // 560 px de janela: 280 em cima, 240 embaixo; 12 opções não cabem.
        const style = await openAt(280, 560);
        expect(style.top).toBe('');
        expect(style.bottom).toBe('284px');
        expect(style.maxHeight).toBe('268px');
      });

      it('abre para baixo e limita a altura ao espaço disponível', async () => {
        // 560 px de janela: 320 embaixo, 200 em cima; fica embaixo, com a margem.
        const style = await openAt(200, 560);
        expect(style.bottom).toBe('');
        expect(style.top).toBe('244px');
        expect(style.maxHeight).toBe('308px');
      });
    });
  });

  it('sem Popover API, abre e fecha sem erro', async () => {
    expect(HTMLElement.prototype.showPopover).toBeUndefined();
    wrapper = mountSelect();
    await wrapper.get('[role="combobox"]').trigger('click');
    expect(wrapper.get('[role="listbox"]').isVisible()).toBe(true);
    await wrapper.findAll('[role="option"]')[2].trigger('click');
    expect(wrapper.get('[role="listbox"]').isVisible()).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toEqual([['es']]);
  });

  it('clique fora fecha; clique na lista não conta como fora', async () => {
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');
    await trigger.trigger('click');
    const list = wrapper.get('[role="listbox"]');
    await list.trigger('pointerdown');
    await list.trigger('click');
    expect(trigger.attributes('aria-expanded')).toBe('true');

    // O onClickOutside ignora cliques no mesmo ciclo do anterior.
    await new Promise(resolve => {
      setTimeout(resolve);
    });
    const outside = document.createElement('div');
    document.body.appendChild(outside);
    outside.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    outside.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await wrapper.vm.$nextTick();
    expect(trigger.attributes('aria-expanded')).toBe('false');
    outside.remove();
  });

  describe('dentro de <label>', () => {
    let host;
    const mountInLabel = () => {
      const Host = defineComponent({
        components: { ChoiceSelect },
        data: () => ({ value: 'pt_BR', options, rotulo: 'Idioma' }),
        template: `
          <label>
            <span class="rotulo">{{ rotulo }}</span>
            <ChoiceSelect v-model="value" :options="options" aria-label="Idioma" />
          </label>`,
      });
      host = mount(Host, { attachTo: document.body });
    };

    afterEach(() => host?.unmount());

    it('clicar numa opção seleciona e não reabre a lista', async () => {
      mountInLabel();
      const trigger = host.get('[role="combobox"]');
      await trigger.trigger('click');
      expect(trigger.attributes('aria-expanded')).toBe('true');
      // O Vue ignora um evento do mesmo milissegundo em que o handler foi
      // montado; espera o relógio andar, como num clique de verdade.
      await new Promise(resolve => {
        setTimeout(resolve, 2);
      });

      // O jsdom trata a lista (tabindex) como conteúdo interativo e não ativa o
      // label; o Chrome ativa. O contrato é o clique sair cancelado.
      const click = new MouseEvent('click', {
        bubbles: true,
        cancelable: true,
      });
      host.findAll('[role="option"]')[2].element.dispatchEvent(click);
      await host.vm.$nextTick();
      expect(click.defaultPrevented).toBe(true);
      expect(host.vm.value).toBe('es');
      expect(trigger.attributes('aria-expanded')).toBe('false');
    });

    it('clicar no texto do rótulo abre a lista, como no select', async () => {
      mountInLabel();
      await host.get('.rotulo').trigger('click');
      expect(host.get('[role="combobox"]').attributes('aria-expanded')).toBe(
        'true'
      );
    });
  });
});

describe('ChoiceSelect dentro de modal ou popover', () => {
  it('Escape com a lista aberta não chega ao document; com ela fechada, chega', async () => {
    const onDocumentKeydown = vi.fn();
    const escapesAtDocument = () =>
      onDocumentKeydown.mock.calls.filter(([event]) => event.key === 'Escape');
    document.addEventListener('keydown', onDocumentKeydown);
    wrapper = mountSelect();
    const trigger = wrapper.get('[role="combobox"]');

    await trigger.trigger('keydown', { key: 'ArrowDown' });
    await trigger.trigger('keydown', { key: 'Escape' });
    expect(trigger.attributes('aria-expanded')).toBe('false');
    expect(escapesAtDocument()).toHaveLength(0);

    await trigger.trigger('keydown', { key: 'Escape' });
    expect(escapesAtDocument()).toHaveLength(1);
    document.removeEventListener('keydown', onDocumentKeydown);
  });
});
