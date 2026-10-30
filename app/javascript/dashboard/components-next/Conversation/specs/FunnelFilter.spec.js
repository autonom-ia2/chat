import { flushPromises, mount } from '@vue/test-utils';
import FunnelFilter from '../FunnelFilter.vue';

const api = vi.hoisted(() => ({ getPipelines: vi.fn() }));
vi.mock('dashboard/api/crmKanban', () => ({ default: api }));

const funis = quantos =>
  Array.from({ length: quantos }, (_, index) => ({
    id: index + 1,
    name: `Funil ${index + 1}`,
  }));

const montar = async ({ pipelines, modelValue = '', listaNova, slots }) => {
  api.getPipelines.mockResolvedValue({ data: { payload: pipelines } });
  const wrapper = mount(FunnelFilter, {
    slots,
    props: {
      modelValue,
      listaNova,
      'onUpdate:modelValue': value => wrapper.setProps({ modelValue: value }),
    },
  });
  await flushPromises();
  return wrapper;
};

describe('FunnelFilter (#1150)', () => {
  it('até 4 funis: botões, com "Todos" e "Sem assunto"', async () => {
    const wrapper = await montar({ pipelines: funis(4) });

    const botoes = wrapper.findAll('[data-funnel-chip]');
    expect(botoes).toHaveLength(6);
    expect(botoes[0].text()).toBe('CONVERSATION_FUNNEL_FILTER.ALL');
    expect(botoes[5].text()).toBe('CONVERSATION_FUNNEL_FILTER.NONE');
    expect(botoes[0].attributes('aria-pressed')).toBe('true');
    expect(wrapper.find('[role="combobox"]').exists()).toBe(false);
  });

  it('um toque no botão troca o funil', async () => {
    const wrapper = await montar({ pipelines: funis(2) });

    await wrapper.findAll('[data-funnel-chip]')[1].trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['1']);
    expect(
      wrapper.findAll('[data-funnel-chip]')[1].attributes('aria-pressed')
    ).toBe('true');
  });

  it('mais de 4 funis: campo de escolha, sem select nativo', async () => {
    const wrapper = await montar({ pipelines: funis(5) });

    expect(wrapper.find('[role="combobox"]').exists()).toBe(true);
    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.findAll('[data-funnel-chip]')).toHaveLength(0);
    expect(wrapper.findAll('[role="option"]')).toHaveLength(7);
  });

  it('funil guardado que não está mais visível volta para todos', async () => {
    const wrapper = await montar({ pipelines: funis(2), modelValue: '9' });

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
  });

  it('funil guardado visível e "Sem assunto" ficam como estão', async () => {
    const visivel = await montar({ pipelines: funis(2), modelValue: '2' });
    const triagem = await montar({ pipelines: funis(2), modelValue: 'none' });

    expect(visivel.emitted('update:modelValue')).toBeUndefined();
    expect(triagem.emitted('update:modelValue')).toBeUndefined();
    expect(triagem.find('[data-funnel-none-hint]').exists()).toBe(true);
  });

  it('sem funil nenhum: não aparece e a lista volta para todos', async () => {
    const wrapper = await montar({ pipelines: [], modelValue: 'none' });

    expect(wrapper.find('[data-funnel-filter]').exists()).toBe(false);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['']);
  });

  it('falha ao ler os funis: só esconde o filtro, sem mexer na escolha guardada', async () => {
    api.getPipelines.mockRejectedValue(new Error('rede'));
    const wrapper = mount(FunnelFilter, { props: { modelValue: '3' } });
    await flushPromises();

    expect(wrapper.find('[data-funnel-filter]').exists()).toBe(false);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });
});

describe('FunnelFilter na lista nova (#2202, chave lista_quem_espera)', () => {
  it('sem a lista nova: a fileira de sempre, que quebra linha', async () => {
    const wrapper = await montar({ pipelines: funis(2) });

    expect(wrapper.find('[role="group"]').attributes('class')).toBe(
      'flex flex-wrap gap-2'
    );
    expect(wrapper.find('[data-funnel-filter]').attributes('class')).toBe(
      'px-3 pb-2'
    );
  });

  it('com a lista nova: "Todos", uma linha só que rola de lado e o chip antes', async () => {
    const wrapper = await montar({
      pipelines: funis(2),
      listaNova: true,
      slots: { antes: '<span data-chip-antes>Adiadas</span>' },
    });

    const fileira = wrapper.find('[role="group"]');
    expect(fileira.classes()).toEqual(
      expect.arrayContaining(['flex-nowrap', 'overflow-x-auto'])
    );
    expect(fileira.classes()).not.toContain('flex-wrap');
    expect(
      fileira.element.firstElementChild.hasAttribute('data-chip-antes')
    ).toBe(true);
    expect(wrapper.findAll('[data-funnel-chip]')[0].text()).toBe(
      'LISTA_DE_CONVERSAS.FUNIS.TODOS'
    );
  });

  it('com a lista nova, o erro aparece com "Tentar de novo", que pede de novo', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    const wrapper = mount(FunnelFilter, { props: { listaNova: true } });
    await flushPromises();

    expect(wrapper.find('[data-funnel-erro]').exists()).toBe(true);
    api.getPipelines.mockResolvedValue({ data: { payload: funis(2) } });
    await wrapper.find('[data-funnel-erro] button').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-funnel-erro]').exists()).toBe(false);
    expect(wrapper.findAll('[data-funnel-chip]')).toHaveLength(4);
  });

  it('sem a lista nova, o erro some como antes', async () => {
    api.getPipelines.mockRejectedValueOnce(new Error('rede'));
    const wrapper = mount(FunnelFilter);
    await flushPromises();

    expect(wrapper.find('[data-funnel-filter]').exists()).toBe(false);
  });
});
