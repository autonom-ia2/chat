require 'rails_helper'

# O passo do Decisor (#858) não roda dentro do ActionService: enfileira o job e os passos seguintes esperam.
RSpec.describe AutomationRules::ActionService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:decisor) { create(:autonomia_decisor, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming) }
  let(:rule) do
    create(:automation_rule, account: account,
                             actions: [{ action_name: 'add_label', action_params: ['antes'] },
                                       { action_name: 'perguntar_ao_decisor', action_params: [decisor.id, 'sim'] },
                                       { action_name: 'add_label', action_params: ['depois'] }])
  end

  it 'roda os passos de antes, enfileira a pergunta com a mensagem e para' do
    expect { described_class.new(rule, account, conversation).perform(message: message) }
      .to have_enqueued_job(Autonomia::Decisores::PerguntarJob).with(rule.id, conversation.id, message.id, 1)

    expect(conversation.reload.label_list).to eq(['antes'])
  end

  it 'sem mensagem do evento, pergunta sobre a última mensagem recebida da conversa' do
    message

    expect { described_class.new(rule, account, conversation).perform }
      .to have_enqueued_job(Autonomia::Decisores::PerguntarJob).with(rule.id, conversation.id, message.id, 1)
  end

  it 'retoma a partir do passo pedido' do
    expect { described_class.new(rule, account, conversation).perform(desde: 2, message: message) }
      .not_to have_enqueued_job(Autonomia::Decisores::PerguntarJob)

    expect(conversation.reload.label_list).to eq(['depois'])
  end
end
