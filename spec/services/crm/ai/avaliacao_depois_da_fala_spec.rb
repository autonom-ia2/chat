require 'rails_helper'

# #2154: a fala do agente que avisou que vai chamar alguém já saiu; a IA de Atribuição avalia o card em foco. Sem token de
# agendamento (uma mensagem do cliente depois não a deixa velha) e só onde há passagem configurada.
RSpec.describe Crm::Ai::AvaliacaoDepoisDaFala do
  include_context 'with crm responsible agent'

  let(:card) { create_card(pipeline: comercial) }

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Rails.logger).to receive(:info).and_call_original
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
  end

  it 'sem a flag, nada (a flag foi desligada no meio da entrega em pedaços)' do
    com_passagem!
    account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)

    expect { described_class.agendar(conversation.reload) }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
  end

  def com_passagem!(enabled: true)
    card.stage.update!(metadata: { 'ai_handoff' => { 'enabled' => enabled, 'handoff_mode' => 'r2_direct' } })
  end

  it 'agenda a avaliação do card em foco com o gatilho da fala do agente, sem token', :aggregate_failures do
    com_passagem!

    expect { described_class.agendar(conversation.reload) }
      .to have_enqueued_job(Crm::Ai::EvaluateCardJob).with(card.id, nil, described_class::TRIGGER)
    expect(Rails.logger).to have_received(:info).with(a_string_including("conversa=#{conversation.id}", 'desfecho=agendada'))
  end

  it 'não mexe no token da avaliação do cliente que já esperava a vez' do
    com_passagem!
    card.update!(metadata: { 'ai' => { 'evaluate_token' => 123.0 } })

    described_class.agendar(conversation.reload)

    expect(card.reload.metadata.dig('ai', 'evaluate_token')).to eq(123.0)
  end

  it 'funil sem passagem configurada: não agenda e deixa a linha' do
    com_passagem!(enabled: false)

    expect { described_class.agendar(conversation.reload) }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=sem_passagem'))
  end

  it 'conversa sem card: não agenda e deixa a linha' do
    expect { described_class.agendar(conversation.reload) }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=sem_card'))
  end

  it 'com a IA do CRM desligada, nada' do
    com_passagem!
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

    expect { described_class.agendar(conversation.reload) }.not_to have_enqueued_job(Crm::Ai::EvaluateCardJob)
  end

  it 'a avaliação da fala do agente não é cortada pelo intervalo entre avaliações (a do cliente pode ter acabado de rodar)' do
    card.update!(metadata: { 'ai' => { 'last_evaluated_at' => 2.seconds.ago.iso8601 } })
    evaluator = Crm::Ai::Evaluator.new(card: card, trigger: described_class::TRIGGER)
    allow(evaluator).to receive_messages(credential_resolver: instance_double(Crm::Ai::CredentialResolver, configured?: true))

    expect(evaluator.motivo_para_pular).to be_nil
    expect(Crm::Ai::Evaluator.new(card: card, trigger: 'message').tap do |outro|
      allow(outro).to receive_messages(credential_resolver: instance_double(Crm::Ai::CredentialResolver, configured?: true))
    end.motivo_para_pular).to eq('debounced')
  end
end
