require 'rails_helper'

# IA entende a conversa F1 (flag `crm_ia_fatos_da_conversa`): a fala pública do nosso agente de IA relê o card em foco,
# 2 min depois, até 6 vezes por card por dia, sem contar como atividade do card.
RSpec.describe Crm::Conversations::CardEmFoco do
  include ActiveJob::TestHelper
  include_context 'with crm responsible agent'

  let!(:card) { create_card(pipeline: comercial) }

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    account.enable_features!(described_class::FLAG, Crm::Ai::FatosDaConversa::FLAG)
    card.update_columns(last_activity_at: 3.days.ago, last_message_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations
    clear_enqueued_jobs
  end

  def fala(sender: porta, **atributos)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: 'Vou chamar uma pessoa da equipe para te atender', sender: sender, **atributos)
  end

  def perform(message) = described_class.new(conversation: conversation.reload, message: message).perform

  def avaliacoes
    enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
  end

  it 'agenda a avaliação do card em foco com o gatilho da fala do robô e a espera da equipe', :aggregate_failures do
    expect(perform(fala)).to eq(card)

    expect(avaliacoes.size).to eq(1)
    expect(avaliacoes.first['arguments'].values_at(0, 2)).to eq([card.id, Crm::Ai::FatosDaConversa::TRIGGER_DO_ROBO])
    ai = card.reload.metadata['ai']
    expect(Time.zone.parse(ai['evaluate_after'])).to be_within(5.seconds).of(described_class::ESPERA_DA_EQUIPE.from_now)
    expect(ai.dig(Crm::Ai::FatosDaConversa::CONTADOR, 'total')).to eq(1)
  end

  it 'não conta como atividade do card (o StaleCardsJob não reavalia por ela)' do
    perform(fala)

    expect(card.reload.last_activity_at).to be < 1.day.ago
    expect(card.last_message_at).to be < 1.day.ago
  end

  it 'com uma avaliação já esperando a vez, não agenda outra' do
    perform(fala)
    perform(fala)

    expect(avaliacoes.size).to eq(1)
  end

  # O teto é por dia (Date.current) e o laço anda ~18 min: começando depois das 23:42, virava o dia no meio e o
  # contador zerava (#2102). O meio-dia de amanhã deixa o laço inteiro no mesmo dia, a qualquer hora em que a suíte
  # rode, e o relógio só anda para a frente. O bloco devolve o relógio no fim.
  it 'para no teto do dia' do
    travel_to(Time.current.tomorrow.noon) do
      Crm::Ai::FatosDaConversa::MAX_AVALIACOES_DO_ROBO_POR_DIA.times do
        perform(fala)
        travel(3.minutes)
      end
      perform(fala)

      expect(avaliacoes.size).to eq(Crm::Ai::FatosDaConversa::MAX_AVALIACOES_DO_ROBO_POR_DIA)
    end
  end

  it 'fora: follow-up em nome de uma pessoa, robô de fora, nota privada, envio que falhou', :aggregate_failures do
    de_fora = AgentBot.create!(account: account, name: 'Integração', outgoing_url: 'https://integracao.invalid/webhook')
    seguimento = fala(sender: admin)
    seguimento.update_columns(content_attributes: { 'crm_follow_up_id' => 1 }) # rubocop:disable Rails/SkipsModelValidations

    [seguimento.reload, fala(sender: de_fora), fala(private: true), fala(status: :failed)].each { |message| perform(message) }

    expect(avaliacoes).to be_empty
  end

  it 'fora: o agente protegido' do
    allow_any_instance_of(Autonomia::Agents::Agent).to receive(:instrucao_mantida?).and_return(true) # rubocop:disable RSpec/AnyInstance

    perform(fala)

    expect(avaliacoes).to be_empty
  end

  it 'sem a flag, a fala do robô não faz nada (como antes)' do
    account.disable_features!(Crm::Ai::FatosDaConversa::FLAG)

    expect(perform(fala)).to be_nil
    expect(avaliacoes).to be_empty
  end

  # Integração: pelo caminho da mensagem (CardSyncer da caixa sem card ao chegar), a fala do robô chega aqui.
  it 'pelo CardSyncer, como a mensagem da equipe' do
    account.crm_inbox_settings.find_by!(inbox: inbox).update!(auto_create_card: false)

    Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: fala).perform

    expect(avaliacoes.map { |job| job['arguments'].values_at(0, 2) }).to eq([[card.id, Crm::Ai::FatosDaConversa::TRIGGER_DO_ROBO]])
  end
end
