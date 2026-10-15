require 'rails_helper'

RSpec.describe Crm::Ai::ResponsibleAgentSyncJob do
  include_context 'with crm responsible agent'

  it 'entrega a conversa ao responsável pelo caminho do perform_later' do
    create_card(pipeline: suporte)

    perform_enqueued_jobs { described_class.perform_later(conversation.id, 'foco', nil) }

    expect(conversation.reload.ai_assignee).to eq(espelho_area)
  end

  it 'ignora motivo desconhecido e conversa apagada' do
    create_card(pipeline: suporte)

    described_class.perform_now(conversation.id, 'qualquer', nil)
    described_class.perform_now(-1, 'foco', nil)

    expect(conversation.reload.ai_assignee).to eq(porta)
  end
end
