import { mount } from '@vue/test-utils';
import CelularConversa from '../components/CelularConversa.vue';
import CompositorAA from '../components/CompositorAA.vue';

describe('CelularConversa', () => {
  const mensagens = [
    { de: 'cliente', texto: 'Vocês abrem no sábado?', hora: '10:02' },
    {
      de: 'agente',
      texto: 'Abrimos sim, das 9h às 13h.',
      hora: '10:02',
      usou: ['tabela.pdf'],
    },
  ];

  it('shows client and agent bubbles in order, each named for screen readers', () => {
    const wrapper = mount(CelularConversa, { props: { mensagens } });
    const baloes = wrapper.findAll('[data-balao]');

    expect(baloes.map(b => b.attributes('data-balao'))).toEqual([
      'cliente',
      'agente',
    ]);
    // Quem fala ("Cliente:" / "Agente:") é conferido com a cópia real no copia.spec.js.
    expect(baloes[0].get('.sr-only').text()).toBe(
      'AGENTS.JORNADA.COMUM.QUEM_DISSE'
    );
    expect(baloes[0].text()).toContain('Vocês abrem no sábado?');
  });

  it('says which file the agent used, never a percentage', () => {
    const wrapper = mount(CelularConversa, {
      props: {
        mensagens: [{ ...mensagens[1], confianca: 0.87, usou: ['tabela.pdf'] }],
      },
    });
    expect(wrapper.get('[data-usou]').text()).toBe('AGENTS.JORNADA.COMUM.USOU');
    expect(wrapper.text()).not.toContain('%');
    expect(wrapper.text()).not.toContain('0.87');
  });

  it('shows the typing bubble while the agent writes', () => {
    const wrapper = mount(CelularConversa, {
      props: { mensagens: [], digitando: true },
    });
    expect(wrapper.find('[data-digitando]').exists()).toBe(true);
    expect(wrapper.text()).toContain('AGENTS.JORNADA.COMUM.ESCREVENDO');
  });

  it('marks the example phone as an example for everyone', () => {
    const wrapper = mount(CelularConversa, {
      props: {
        mensagens,
        tamanho: 'mini',
        selo: 'Exemplo',
        rotuloSr: 'Exemplo de conversa, não é um agente de verdade',
      },
    });
    expect(wrapper.get('[data-selo]').text()).toBe('Exemplo');
    // Selo âmbar no canto do celular, como o .phone-badge do protótipo.
    expect(wrapper.get('[data-selo]').classes()).toContain('bg-n-amber-9');
    expect(wrapper.get('.sr-only').text()).toBe(
      'Exemplo de conversa, não é um agente de verdade'
    );
    expect(wrapper.find('[aria-live]').exists()).toBe(false);
  });

  it('announces new answers on the full size phone', () => {
    const wrapper = mount(CelularConversa, {
      props: { mensagens, nome: 'Duda', estado: 'online' },
    });
    expect(wrapper.get('[aria-live]').attributes('aria-live')).toBe('polite');
    expect(wrapper.text()).toContain('Duda');
  });
});

describe('CompositorAA', () => {
  const montar = props =>
    mount(CompositorAA, {
      props: { modelValue: '', ...props },
    });

  it('sends the text on Enter and keeps Shift+Enter for a new line', async () => {
    const wrapper = montar({ modelValue: 'Oi' });
    const campo = wrapper.get('textarea');

    await campo.trigger('keydown', { key: 'Enter', shiftKey: true });
    expect(wrapper.emitted('enviar')).toBeUndefined();

    await campo.trigger('keydown', { key: 'Enter' });
    expect(wrapper.emitted('enviar')).toEqual([[{ texto: 'Oi', anexos: [] }]]);
  });

  it('does not send an empty message', async () => {
    const wrapper = montar({ modelValue: '   ' });
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('enviar')).toBeUndefined();
    expect(wrapper.get('[data-enviar]').attributes('aria-disabled')).toBe(
      'true'
    );
  });

  it('labels the field and updates the model', async () => {
    const wrapper = montar();
    const campo = wrapper.get('textarea');
    expect(wrapper.get(`label[for="${campo.attributes('id')}"]`).text()).toBe(
      'AGENTS.JORNADA.COMPOSITOR.ESCREVA'
    );
    await campo.setValue('Quanto custa?');
    expect(wrapper.emitted('update:modelValue')).toEqual([['Quanto custa?']]);
  });

  it('keeps files optional and sends them along when chosen', async () => {
    const wrapper = montar({ modelValue: '', anexar: true });
    const arquivo = new File(['x'], 'tabela.pdf', { type: 'application/pdf' });
    const seletor = wrapper.get('input[type="file"]');
    Object.defineProperty(seletor.element, 'files', { value: [arquivo] });
    await seletor.trigger('change');

    expect(wrapper.text()).toContain('tabela.pdf');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.emitted('enviar')).toEqual([
      [{ texto: '', anexos: [arquivo] }],
    ]);
  });

  it('accepts only images in test mode', async () => {
    const wrapper = montar({ anexar: true, soImagens: true });
    const seletor = wrapper.get('input[type="file"]');
    expect(seletor.attributes('accept')).toBe('image/*');

    const documento = new File(['x'], 'tabela.pdf', {
      type: 'application/pdf',
    });
    Object.defineProperty(seletor.element, 'files', { value: [documento] });
    await seletor.trigger('change');
    expect(wrapper.text()).not.toContain('tabela.pdf');
  });

  it('has no clip button unless asked', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-anexar]').exists()).toBe(false);
  });
});
