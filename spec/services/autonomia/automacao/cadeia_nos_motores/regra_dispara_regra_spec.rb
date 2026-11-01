require 'rails_helper'

# #2414 F1.1: com a flag `automacao_fundacao`, a mudança feita por uma regra dispara as outras regras, e a cadeia
# segura laço e cascata. Sem a flag, uma regra nunca dispara outra, como antes. A cascata cortada fica no histórico
# da conversa; o laço, só no log.
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

  def tratar_na_cadeia(origens)
    cadeia.restaurada(origens, account.id) { listener.conversation_updated(evento_da_regra) }
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

    it 'a regra que já rodou na sequência é recusada (laço) e não deixa nota no histórico' do
      tratar_na_cadeia(["regra:#{regra_seguinte.id}"])

      expect(conversation.reload.label_list).not_to include('seguinte')
      expect(notas_de_atividade).to be_empty
    end

    it 'a quarta automação seguida é recusada e o motivo vai para o histórico da conversa' do
      tratar_na_cadeia(%w[regra:1 etapa:2 regra:3])

      expect(conversation.reload.label_list).not_to include('seguinte')
      expect(notas_de_atividade.size).to eq(1)
      conteudo = notas_de_atividade.first['arguments'].last['content']
      expect(conteudo).to include('Etiqueta de quem abriu')
    end
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
