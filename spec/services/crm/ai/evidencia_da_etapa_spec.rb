require 'rails_helper'

# #1920: a evidência que vai à IA que escreve a frase sai do que está gravado (sugestões da IA e movimentos de pessoa).
RSpec.describe Crm::Ai::EvidenciaDaEtapa do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:novo) { pipeline_and_stage.last }
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1) }
  let(:fechado) { create_crm_stage(account: account, pipeline: pipeline, name: 'Fechado', position: 2) }
  let(:inbox) { create_crm_inbox(account: account) }

  def card_com_conversa(titulo, falas)
    contact = create(:contact, account: account, name: 'Cliente Sintético')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    falas.each do |texto, quando|
      conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :incoming, content: texto,
                                    sender: contact, created_at: quando)
    end
    account.crm_cards.create!(pipeline: pipeline, stage: novo, title: titulo, conversation_id: conversation.id)
  end

  def sugestao(card, para:, status:, quando:, confianca: 0.8)
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: novo, to_stage: para, confidence: confianca, reasoning: 'Motivo da IA',
                                             model_used: 'modelo', status: status, created_at: quando, updated_at: quando)
  end

  def movimento_de_pessoa(card, origem:, para:, quando:)
    Crm::Activity.create!(account: account, card: card, actor_type: 'user', actor_id: admin.id, event_type: 'move', created_at: quando,
                          payload: { from_pipeline_id: pipeline.id, to_pipeline_id: pipeline.id, from_stage_id: origem.id, to_stage_id: para.id })
  end

  it 'traz o card que a IA pôs na etapa e uma pessoa tirou logo, com a conversa só até a decisão' do
    card = card_com_conversa('Pedido A', [['Vou te ligar para apresentar a cotação', 3.hours.ago], ['Mensagem depois', 1.minute.ago]])
    sugestao(card, para: proposta, status: :auto_applied, quando: 2.hours.ago)
    movimento_de_pessoa(card, origem: proposta, para: novo, quando: 1.hour.ago)

    casos = described_class.new(stage: proposta).casos

    expect(casos.size).to eq(1)
    expect(casos.first).to include(signal: 'levou_e_pessoa_tirou', ai_chose: 'Proposta', person_chose: 'Novo Lead', ai_confidence: 0.8)
    expect(casos.first[:messages]).to eq([{ role: 'customer', content: 'Vou te ligar para apresentar a cotação' }])
    expect(casos.first.to_json).not_to include('Cliente Sintético')
  end

  it 'não conta como correção a pessoa que avança o card dias depois do movimento da IA' do
    card = card_com_conversa('Pedido B', [['Pode mandar a proposta', 5.days.ago]])
    sugestao(card, para: proposta, status: :auto_applied, quando: 4.days.ago)
    movimento_de_pessoa(card, origem: proposta, para: fechado, quando: 1.day.ago)

    expect(described_class.new(stage: proposta).casos).to be_empty
  end

  it 'traz o card que uma pessoa pôs na etapa logo depois de a IA escolher outra' do
    card = card_com_conversa('Pedido C', [['Já resolvi com outra empresa', 3.hours.ago]])
    sugestao(card, para: proposta, status: :auto_applied, quando: 2.hours.ago)
    movimento_de_pessoa(card, origem: proposta, para: fechado, quando: 1.hour.ago)

    casos = described_class.new(stage: fechado).casos

    expect(casos.first).to include(signal: 'pessoa_trouxe', ai_chose: 'Proposta', person_chose: 'Fechado')
  end

  it 'traz a sugestão recusada e a dúvida, um caso por card, e ignora o que não tem conversa' do
    recusada = card_com_conversa('Pedido D', [['Quanto custa?', 3.hours.ago]])
    duvida = card_com_conversa('Pedido E', [['Talvez mais para frente', 3.hours.ago]])
    sem_conversa = account.crm_cards.create!(pipeline: pipeline, stage: novo, title: 'Sem conversa')
    sugestao(recusada, para: proposta, status: :dismissed, quando: 2.hours.ago)
    sugestao(recusada, para: proposta, status: :pending, quando: 1.hour.ago, confianca: 0.6)
    sugestao(duvida, para: proposta, status: :pending, quando: 1.hour.ago, confianca: 0.6)
    sugestao(duvida, para: proposta, status: :pending, quando: 1.hour.ago, confianca: 0.9)
    sugestao(sem_conversa, para: proposta, status: :dismissed, quando: 1.hour.ago)

    casos = described_class.new(stage: proposta).casos

    expect(casos.map { |caso| caso[:signal] }).to eq(%w[sugeriu_e_pessoa_recusou ficou_em_duvida])
    expect(casos.last[:ai_confidence]).to eq(0.6)
  end

  it 'não lê sugestões de outra etapa' do
    card = card_com_conversa('Pedido F', [['Oi', 3.hours.ago]])
    sugestao(card, para: fechado, status: :dismissed, quando: 1.hour.ago)

    expect(described_class.new(stage: proposta).casos).to be_empty
  end
end
