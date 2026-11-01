require 'rails_helper'

# #2414 F1.1: com a flag `automacao_fundacao`, a mudança feita por uma regra dispara as outras regras, e a cadeia
# segura laço, cascata e repetição na mesma raiz. Sem a flag, uma regra nunca dispara outra, como antes. Quando a
# cadeia corta, fica uma nota só por raiz no histórico da conversa.
RSpec.describe Autonomia::Automacao::CadeiaNosMotores::RegraDisparaRegra do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:listener) { AutomationRuleListener.instance }
  let(:conversation) { create(:conversation, account: account).reload }
  let(:cadeia) { Autonomia::Automacao::Cadeia }
  let(:regra_que_mudou) { create(:automation_rule, account: account, name: 'Marca lead') }
  let!(:regra_seguinte) do
    create(:automation_rule, account: account, name: 'Etiqueta de quem abriu', event_name: 'conversation_updated',
                             conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }],
                             actions: [{ action_name: 'add_label', action_params: ['seguinte'] }])
  end

  def evento_da_regra
    Events::Base.new('conversation_updated', Time.zone.now,
                     conversation: conversation, performed_by: regra_que_mudou, changed_attributes: { label_list: [[], ['lead']] })
  end

  def tratar_na_cadeia(origens, raiz = SecureRandom.uuid)
    cadeia.restaurada(origens, account.id, raiz) { listener.conversation_updated(evento_da_regra) }
  end

  def regra(nome, evento, condicoes, acoes)
    create(:automation_rule, account: account, name: nome, event_name: evento, conditions: condicoes, actions: acoes)
  end

  def aberta
    [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }]
  end

  def notas_de_atividade
    enqueued_jobs.select { |job| job['job_class'] == 'Conversations::ActivityMessageJob' }
  end

  describe 'com a flag' do
    before { account.enable_features!('automacao_fundacao') }

    it 'a mudança de uma regra dispara a regra seguinte' do
      tratar_na_cadeia(["regra:#{regra_que_mudou.id}"])

      expect(conversation.reload.label_list).to include('seguinte')
    end

    it 'de ponta a ponta, pelo evento despachado' do
      regra_que_mudou.update!(actions: [{ action_name: 'add_label', action_params: ['lead'] }])

      perform_enqueued_jobs(only: EventDispatcherJob) do
        AutomationRules::ActionService.new(regra_que_mudou, account, conversation).perform
      end

      expect(conversation.reload.label_list).to include('lead', 'seguinte')
    end

    it 'a regra com atraso disparada por outra regra segue sem armar' do
      account.enable_features!('delayed_automations')
      regra_seguinte.update!(execution_delay: 30)

      expect { tratar_na_cadeia(["regra:#{regra_que_mudou.id}"]) }.not_to change(AutomationRulePendingExecution, :count)
    end

    it 'a regra que já rodou no ramo é recusada (laço) e deixa uma nota no histórico' do
      tratar_na_cadeia(["regra:#{regra_seguinte.id}"])

      expect(conversation.reload.label_list).not_to include('seguinte')
      expect(notas_de_atividade.size).to eq(1)
      expect(notas_de_atividade.first['arguments'].last['content']).to include('Etiqueta de quem abriu', 'to avoid repetition')
    end

    it 'deixa uma nota só por raiz, por mais que a cadeia corte' do
      tratar_na_cadeia(["regra:#{regra_seguinte.id}"], 'raiz-1')
      tratar_na_cadeia(%w[regra:1 etapa:2 regra:3], 'raiz-1')
      tratar_na_cadeia(["regra:#{regra_seguinte.id}"], 'raiz-2')

      expect(notas_de_atividade.size).to eq(2)
    end

    it 'a quarta automação seguida é recusada e o motivo vai para o histórico da conversa' do
      tratar_na_cadeia(%w[regra:1 etapa:2 regra:3])

      expect(conversation.reload.label_list).not_to include('seguinte')
      expect(notas_de_atividade.size).to eq(1)
      expect(notas_de_atividade.first['arguments'].last['content']).to include('Etiqueta de quem abriu')
    end

    it 'a regra recusada não deixa o Current preenchido para os próximos listeners' do
      tratar_na_cadeia(["regra:#{regra_seguinte.id}"])

      expect(Current.executed_by).to be_nil
    end
  end

  # Ponta a ponta pelo EventDispatcherJob, como em produção: a regra A muda a conversa duas vezes, e cada mudança é um
  # evento. A regra B casa com os dois, mas roda uma vez só por raiz.
  describe 'duas mudanças da mesma regra' do
    let(:agente) { create(:user, account: account, role: :agent) }
    let(:regra_a) do
      regra('A', 'conversation_created', [], [{ action_name: 'add_label', action_params: ['vip'] },
                                              { action_name: 'assign_agent', action_params: [agente.id] }])
    end

    before do
      create(:inbox_member, inbox: conversation.inbox, user: agente)
      regra('B', 'conversation_updated', [{ attribute_key: 'labels', filter_operator: 'equal_to', values: ['vip'], query_operator: nil }],
            [{ action_name: 'send_message', action_params: ['Olá! Bem-vindo'] }])
    end

    def mensagens_enviadas
      perform_enqueued_jobs(only: EventDispatcherJob) { AutomationRules::ActionService.new(regra_a, account, conversation).perform }
      conversation.messages.outgoing.where(content: 'Olá! Bem-vindo').count
    end

    it 'com a flag, a mensagem sai uma vez' do
      account.enable_features!('automacao_fundacao')

      expect(mensagens_enviadas).to eq(1)
    end

    it 'sem a flag, uma regra não dispara outra: nenhuma mensagem' do
      expect(mensagens_enviadas).to eq(0)
    end
  end

  it 'com a flag, A dispara B e B dispara A: cada uma roda uma vez e a sequência termina' do
    account.enable_features!('automacao_fundacao')
    regra_a = regra('A', 'conversation_updated', aberta, [{ action_name: 'add_label', action_params: ['x'] },
                                                          { action_name: 'remove_label', action_params: ['y'] }])
    regra('B', 'conversation_updated', aberta, [{ action_name: 'add_label', action_params: ['y'] },
                                                { action_name: 'remove_label', action_params: ['x'] }])
    execucoes = Hash.new(0)
    allow(AutomationRules::Disparos).to receive(:registrar).and_wrap_original do |original, id|
      execucoes[AutomationRule.find(id).name] += 1
      original.call(id)
    end

    perform_enqueued_jobs(only: EventDispatcherJob) { AutomationRules::ActionService.new(regra_a, account, conversation).perform }

    expect(execucoes).to include('A' => 1, 'B' => 1)
  end

  it 'sem a flag, o evento de uma regra segue ignorado' do
    listener.conversation_updated(evento_da_regra)

    expect(conversation.reload.label_list).not_to include('seguinte')
  end

  it 'sem a flag, de ponta a ponta, uma regra não dispara outra' do
    regra_que_mudou.update!(actions: [{ action_name: 'add_label', action_params: ['lead'] }])

    perform_enqueued_jobs(only: EventDispatcherJob) do
      AutomationRules::ActionService.new(regra_que_mudou, account, conversation).perform
    end

    expect(conversation.reload.label_list).to contain_exactly('lead')
  end
end
