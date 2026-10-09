import { enableAutoUnmount, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgentTestPhone from './AgentTestPhone.vue';

withFullI18n('pt_BR');
enableAutoUnmount(afterEach);

const agent = {
  id: 42,
  name: 'Clara',
  type: 'support',
  actuation: 'external',
  greeting: 'Oi! Como posso ajudar?',
};

const mountPhone = (props = {}) =>
  mount(AgentTestPhone, {
    props: { agentId: 42, agent, ...props },
    global: {
      stubs: { ChatBubble: true },
    },
  });

describe('AgentTestPhone', () => {
  it('preserva o modo de criação por padrão, incluindo apresentação e rodapé', () => {
    const wrapper = mountPhone();

    expect(wrapper.get('[data-testid="agent-creation-test"]').exists()).toBe(
      true
    );
    expect(wrapper.get('[data-testid="presentation-name"]').element.value).toBe(
      'Clara'
    );
    expect(wrapper.get('[data-action="creation-save-exit"]').exists()).toBe(
      true
    );
    expect(wrapper.get('[data-action="creation-continue"]').exists()).toBe(
      true
    );
  });

  it('no painel remove apresentação, saída e controles do rodapé', () => {
    const wrapper = mountPhone({ mode: 'panel', canManage: true });

    expect(wrapper.get('[data-testid="agent-panel-test-phone"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="presentation-name"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-action="creation-save-exit"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-action="creation-continue"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="agent-test-legend"]').exists()).toBe(
      true
    );
  });

  it('mostra os metadados reais e só oferece ensino a quem gerencia', async () => {
    const response = {
      role: 'assistant',
      content: 'Resposta baseada no material.',
      confidence: 0.82,
      handoff: { should: true, reason: 'human_requested' },
      usedKnowledge: [{ source: 'Manual de atendimento' }],
      writesExternal: true,
      skippedTools: [{ code: 'viewer_not_allowed' }],
    };
    const wrapper = mountPhone({
      mode: 'panel',
      canManage: true,
      messages: [{ role: 'user', content: 'Como funciona?' }, response],
    });

    expect(wrapper.get('[data-testid="agent-test-legend"]').text()).toContain(
      'Certeza'
    );
    expect(wrapper.get('[data-testid="agent-test-legend"]').text()).toContain(
      'Material usado'
    );
    expect(wrapper.get('[data-testid="agent-test-legend"]').text()).toContain(
      'Amarelo'
    );
    expect(wrapper.find('[data-testid="test-handoff"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="test-used-material"]').text()).toContain(
      'Manual de atendimento'
    );
    expect(wrapper.find('[data-testid="test-writes-external"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-action="test-teach"]').exists()).toBe(true);

    await wrapper.get('[data-action="test-teach"]').trigger('click');
    expect(wrapper.emitted('teach')).toHaveLength(1);

    await wrapper.setProps({ canManage: false });
    expect(wrapper.find('[data-action="test-teach"]').exists()).toBe(false);
  });

  it('limpa a conversa e explica que a apresentação reiniciou o teste', async () => {
    const wrapper = mountPhone({
      messages: [
        { role: 'user', content: 'Pergunta antiga' },
        { role: 'assistant', content: 'Resposta antiga' },
      ],
      presentationRevision: 0,
    });

    await wrapper.setProps({ presentationRevision: 1 });

    expect(wrapper.emitted('clear')).toEqual([[{ reason: 'presentation' }]]);
    expect(
      wrapper.get('[data-testid="test-presentation-reset"]').exists()
    ).toBe(true);
  });

  it('não mostra passagem amarela no ajudante interno, mas mantém ensino para quem gerencia', async () => {
    const wrapper = mountPhone({
      mode: 'panel',
      canManage: true,
      isInternal: true,
      agent: { ...agent, actuation: 'internal' },
      messages: [
        {
          role: 'assistant',
          content: 'Resposta interna.',
          confidence: 0.2,
          handoff: { should: true, reason: 'low_confidence' },
        },
      ],
    });

    expect(wrapper.find('[data-testid="test-handoff"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="legend-handoff"]').exists()).toBe(false);
    expect(wrapper.find('[data-action="test-teach"]').exists()).toBe(true);
    await wrapper.get('[data-action="test-teach"]').trigger('click');
    expect(wrapper.emitted('teach')).toHaveLength(1);
  });

  it('não oferece ensino no agente de cotação mesmo para quem gerencia', () => {
    const wrapper = mountPhone({
      mode: 'panel',
      canManage: true,
      agent: { ...agent, agent_type: 'insurance_quote' },
    });

    expect(wrapper.find('[data-action="test-teach"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="quote-test-notice"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="legend-handoff"]').exists()).toBe(false);
  });

  it('mostra aviso de cotação só no resultado com not_in_test e distingue permissão', async () => {
    const wrapper = mountPhone({
      mode: 'panel',
      agent: { ...agent, agent_type: 'insurance_quote' },
    });
    await wrapper.setProps({
      messages: [
        { role: 'assistant', content: 'Resposta normal.', skippedTools: [] },
      ],
    });
    expect(wrapper.find('[data-testid="quote-test-notice"]').exists()).toBe(
      false
    );
    await wrapper.setProps({
      messages: [
        {
          role: 'assistant',
          content: 'Resposta de cotação.',
          skippedTools: [
            { code: 'not_in_test', name: 'Consultar seguradoras' },
          ],
        },
      ],
    });
    expect(wrapper.findAll('[data-testid="quote-test-notice"]')).toHaveLength(
      1
    );
    expect(wrapper.get('[data-testid="quote-test-notice"]').text()).toContain(
      'não consulta as seguradoras'
    );
    await wrapper.setProps({
      messages: [
        {
          role: 'assistant',
          content: 'Resposta só de leitura.',
          skippedTools: [
            { code: 'viewer_not_allowed', name: 'Consultar seguradoras' },
          ],
        },
      ],
    });
    expect(wrapper.find('[data-testid="quote-test-notice"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toContain('só quem edita testa essa ação');
    await wrapper.setProps({ messages: [] });
    expect(wrapper.find('[data-testid="quote-test-notice"]').exists()).toBe(
      false
    );
  });

  it('mantém o compositor bloqueado durante a janela de limite', () => {
    const wrapper = mountPhone({ mode: 'panel', rateLimited: true });

    expect(
      wrapper.get('[data-testid="test-message"]').attributes('disabled')
    ).toBe('');
    expect(
      wrapper.get('[data-action="test-send"]').attributes('disabled')
    ).toBe('');
  });
});
