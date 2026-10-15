import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import BotConfiguration from '../BotConfiguration.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import QuemAtendeAPI from 'dashboard/api/autonomia/quemAtende';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/agents.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/agents.json';

// #1648 — a aba "Agente de IA" da caixa: quem atende primeiro (da plataforma ou
// de outro sistema, sem diferença na tela), quem também recebe quando alguém
// passa e a troca completa, com confirmação em linha e o motivo da recusa.
const jornada = { ativa: true };
const podeTrocar = { valor: true };

vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => podeTrocar.valor) };
});
vi.mock(
  'dashboard/routes/dashboard/autonomia/agentes/composables/useJornadaAtiva',
  () => ({ useJornadaAtiva: () => jornada.ativa })
);
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomia/quemAtende', () => ({
  default: { daCaixa: vi.fn(), trocar: vi.fn() },
}));

const SOFIA = { tipo: 'plataforma', id: 3, name: 'Sofia', papel: 'porta' };
const BIA = { tipo: 'plataforma', id: 7, name: 'Bia', papel: 'area' };
const AUTOMACAO = {
  tipo: 'webhook',
  id: 31,
  name: 'Automação Vendas',
  papel: 'porta',
};
const opcao = (agente, recusa = null) => ({
  tipo: agente.tipo,
  id: agente.id,
  name: agente.name,
  recusa,
});
const LEO = { tipo: 'plataforma', id: 4, name: 'Leo' };

const leitura = (agentes, opcoes) => ({
  agentes,
  primeiro: agentes.find(agente => agente.papel === 'porta') || null,
  opcoes,
});

const render = async dados => {
  QuemAtendeAPI.daCaixa.mockResolvedValue({ data: dados });
  const wrapper = mount(BotConfiguration, {
    props: { inbox: { id: 10, name: 'WhatsApp Vendas' } },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          fallbackLocale: false,
          messages: { en: { ...en }, pt_BR: { ...pt_BR } },
        }),
      ],
      stubs: {
        'router-link': {
          props: ['to'],
          template: '<a :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const escolher = async (wrapper, valor) => {
  wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', valor);
  await flushPromises();
};

const COM_SOFIA = leitura(
  [SOFIA, BIA],
  [
    opcao(AUTOMACAO),
    opcao(BIA, 'agente_ja_e_da_equipe'),
    opcao(LEO),
    opcao(SOFIA),
  ]
);

describe('BotConfiguration', () => {
  beforeEach(() => {
    vi.useRealTimers();
    jornada.ativa = true;
    podeTrocar.valor = true;
    QuemAtendeAPI.daCaixa.mockReset();
    QuemAtendeAPI.trocar.mockReset();
    useAlert.mockReset();
  });

  it('shows who answers first, the team agents and opens the platform agent page', async () => {
    const wrapper = await render(COM_SOFIA);

    expect(QuemAtendeAPI.daCaixa).toHaveBeenCalledWith(10);
    expect(wrapper.text()).toContain('Atende primeiro');
    expect(wrapper.text()).toContain('Sofia');
    expect(wrapper.find('[data-tambem-recebem]').text()).toBe(
      'Também recebem quando alguém passar: Bia'
    );
    expect(
      JSON.parse(wrapper.find('[data-abrir-agente]').attributes('data-to'))
    ).toEqual({ name: 'autonomia_agent_panel', params: { agentId: 3 } });
  });

  it('offers every AI agent from the server, plus nobody, without telling where each comes from', async () => {
    const wrapper = await render(COM_SOFIA);

    expect(
      wrapper
        .findComponent(ChoiceSelect)
        .props('options')
        .map(o => o.label)
    ).toEqual([
      'Ninguém, só pessoas',
      'Automação Vendas',
      'Bia',
      'Leo',
      'Sofia',
    ]);
    expect(wrapper.text()).not.toMatch(/externo|robô|n8n|webhook/i);
  });

  it('asks for confirmation inline and swaps platform agent for platform agent', async () => {
    const wrapper = await render(COM_SOFIA);
    const depois = leitura([{ ...LEO, papel: 'porta' }, BIA], COM_SOFIA.opcoes);
    QuemAtendeAPI.trocar.mockResolvedValue({ data: depois });

    await escolher(wrapper, 'plataforma:4');
    expect(wrapper.find('[data-troca]').text()).toBe(
      'Sofia deixa de atender primeiro neste canal. Leo passa a atender.'
    );
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.trocar).toHaveBeenCalledWith(10, {
      tipo: 'plataforma',
      id: 4,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Leo atende primeiro neste canal.'
    );
    expect(wrapper.find('[data-confirmacao]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Leo');
  });

  it('cancel puts the current agent back without calling the server', async () => {
    const wrapper = await render(COM_SOFIA);

    await escolher(wrapper, 'plataforma:4');
    await wrapper.find('[data-cancelar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-troca]').exists()).toBe(false);
    expect(wrapper.findComponent(ChoiceSelect).props('modelValue')).toBe(
      'plataforma:3'
    );
    expect(QuemAtendeAPI.trocar).not.toHaveBeenCalled();
  });

  it('shows the reason before asking when the server already refuses the option', async () => {
    const wrapper = await render(COM_SOFIA);

    await escolher(wrapper, 'plataforma:7');

    expect(wrapper.find('[data-recusa]').attributes('role')).toBe('alert');
    expect(wrapper.find('[data-recusa]').text()).toContain(
      'Bia já recebe quando alguém passa neste canal.'
    );
    expect(wrapper.find('[data-trocar]').exists()).toBe(false);
    expect(wrapper.find('[data-cancelar]').exists()).toBe(true);
  });

  it('swaps to an agent from another system and keeps the team agents', async () => {
    const wrapper = await render(COM_SOFIA);
    QuemAtendeAPI.trocar.mockResolvedValue({
      data: leitura([AUTOMACAO, BIA], COM_SOFIA.opcoes),
    });

    await escolher(wrapper, 'webhook:31');
    expect(wrapper.find('[data-recusa]').exists()).toBe(false);
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.trocar).toHaveBeenCalledWith(10, {
      tipo: 'webhook',
      id: 31,
    });
    expect(wrapper.find('[data-tambem-recebem]').text()).toContain('Bia');
  });

  it('takes the agent out with nobody and sends nenhum', async () => {
    const wrapper = await render(COM_SOFIA);
    QuemAtendeAPI.trocar.mockResolvedValue({
      data: leitura([BIA], COM_SOFIA.opcoes),
    });

    await escolher(wrapper, 'ninguem');
    expect(wrapper.find('[data-troca]').text()).toContain(
      'As conversas novas vão direto para as pessoas.'
    );
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.trocar).toHaveBeenCalledWith(10, null);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. Ninguém atende primeiro neste canal.'
    );
    expect(wrapper.find('[data-ninguem]').exists()).toBe(true);
  });

  it('shows an agent from another system like any other and opens its page', async () => {
    const wrapper = await render(
      leitura([AUTOMACAO], [opcao(AUTOMACAO), opcao(LEO)])
    );

    expect(wrapper.text()).toContain('Automação Vendas');
    expect(
      JSON.parse(wrapper.find('[data-abrir-agente]').attributes('data-to'))
    ).toEqual({
      name: 'autonomia_agent_panel',
      params: { agentId: 31 },
      query: { origem: 'webhook' },
    });
  });

  it('without the new Agents journey, the agent from another system opens the bots settings', async () => {
    jornada.ativa = false;
    const wrapper = await render(leitura([AUTOMACAO], [opcao(AUTOMACAO)]));

    expect(
      JSON.parse(wrapper.find('[data-abrir-agente]').attributes('data-to'))
    ).toEqual({ name: 'agent_bots' });
  });

  it('nobody answers first: no "nobody" option and Confirm instead of Swap', async () => {
    const wrapper = await render(
      leitura([BIA], [opcao(AUTOMACAO), opcao(LEO)])
    );
    QuemAtendeAPI.trocar.mockResolvedValue({
      data: leitura([AUTOMACAO, BIA], [opcao(AUTOMACAO), opcao(LEO)]),
    });

    expect(wrapper.find('[data-ninguem]').exists()).toBe(true);
    expect(
      wrapper
        .findComponent(ChoiceSelect)
        .props('options')
        .map(o => o.value)
    ).toEqual(['webhook:31', 'plataforma:4']);

    await escolher(wrapper, 'webhook:31');
    expect(wrapper.find('[data-troca]').text()).toBe(
      'Automação Vendas passa a atender primeiro neste canal.'
    );
    expect(wrapper.find('[data-trocar]').text()).toBe('Confirmar');
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.trocar).toHaveBeenCalledWith(10, {
      tipo: 'webhook',
      id: 31,
    });
  });

  it('shows the server refusal inline and keeps the choice', async () => {
    const wrapper = await render(COM_SOFIA);
    QuemAtendeAPI.trocar.mockRejectedValue({
      response: { data: { code: 'agente_parado', error: 'x' } },
    });

    await escolher(wrapper, 'plataforma:4');
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-recusa]').text()).toContain(
      'Este agente está parado.'
    );
    expect(useAlert).not.toHaveBeenCalled();
    expect(wrapper.findComponent(ChoiceSelect).props('modelValue')).toBe(
      'plataforma:4'
    );
  });

  it('reloads when someone else changed the channel just now', async () => {
    const wrapper = await render(COM_SOFIA);
    QuemAtendeAPI.trocar.mockRejectedValue({
      response: { data: { code: 'mudou_agora' } },
    });

    await escolher(wrapper, 'plataforma:4');
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(QuemAtendeAPI.daCaixa).toHaveBeenCalledTimes(2);
  });

  it('an unexpected failure warns, changes nothing and puts the current agent back', async () => {
    const wrapper = await render(COM_SOFIA);
    QuemAtendeAPI.trocar.mockRejectedValue(new Error('rede'));

    await escolher(wrapper, 'plataforma:4');
    await wrapper.find('[data-trocar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para trocar agora. Nada mudou neste canal.'
    );
    expect(wrapper.findComponent(ChoiceSelect).props('modelValue')).toBe(
      'plataforma:3'
    );
  });

  it('never shows a read error: stays loading and tries again', async () => {
    vi.useFakeTimers();
    QuemAtendeAPI.daCaixa
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce({ data: COM_SOFIA });
    const wrapper = mount(BotConfiguration, {
      props: { inbox: { id: 10 } },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'pt_BR',
            messages: { pt_BR: { ...pt_BR } },
          }),
        ],
        stubs: { 'router-link': true },
      },
    });
    await flushPromises();

    expect(wrapper.find('[data-esqueleto]').exists()).toBe(true);
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);

    await vi.advanceTimersByTimeAsync(3000);
    await flushPromises();

    expect(QuemAtendeAPI.daCaixa).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-quem-atende]').exists()).toBe(true);
  });

  it('who cannot manage the inbox sees who answers but not the choice', async () => {
    podeTrocar.valor = false;
    const wrapper = await render(COM_SOFIA);

    expect(wrapper.text()).toContain('Sofia');
    expect(wrapper.findComponent(ChoiceSelect).exists()).toBe(false);
  });
});
