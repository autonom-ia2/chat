require 'rails_helper'

# "Guardar junto" (#2095) com o follow-up de IA em cadência: a cadência para sem gastar, e o planner volta a armar
# quando o funil é restaurado. Antes, o estado ficava `active: true` e o card nunca mais entrava em cadência.
RSpec.describe Crm::Pipelines::RetornosDosGuardados do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:config) do
    { 'enabled' => true, 'intervals_hours' => [20, 72, 168], 'max_touches' => 3, 'quiet_hours' => { 'start' => 0, 'end' => 24 } }
  end
  let(:funil) do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { 'ai' => { 'auto_followup' => config } })
    [pipeline, stage]
  end
  let!(:outro_funil) { create_crm_pipeline(account: account, user: user, name: 'Vendas').first }

  # Conversa WhatsApp com troca dos dois lados e a última mensagem há 21 h (elegível para o primeiro toque).
  def conversa_parada(inbox, contact)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    2.times { create_incoming_message(conversation: conversation) }
    2.times { conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'Oi') }
    conversation.messages.reorder(id: :desc).first.update!(created_at: 21.hours.ago)
    conversation
  end

  def card_em_conversa
    pipeline, stage = funil
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511999990555')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversa_parada(inbox, contact), title: 'Lead')
  end

  def planejar
    Crm::FollowUps::AutoFollowupPlanner.new(pipeline: funil.first.reload).perform
  end

  def estado(card)
    card.reload.metadata.dig('ai', 'auto_followup_state')
  end

  it 'para a cadência sem gastar e, com o funil restaurado, o planner volta a armar' do
    card = card_em_conversa
    expect(planejar).to eq(1)
    expect(estado(card)['active']).to be(true)
    novo_principal = funil.first.is_default? ? outro_funil : nil

    Crm::Pipelines::Archiver.new(pipeline: funil.first, actor: user, stop_follow_ups: true, new_default: novo_principal).perform

    expect(estado(card)).to include('active' => false, 'spent' => false, 'stopped_reason' => 'pipeline_archived', 'next_due_at' => nil)
    expect(card.follow_ups.active).to be_empty

    funil.first.active!
    expect(planejar).to eq(1)
    expect(estado(card)['active']).to be(true)
  end

  it 'sem pedir para parar (DELETE antigo), a cadência fica como estava' do
    card = card_em_conversa
    planejar
    novo_principal = funil.first.is_default? ? outro_funil : nil

    Crm::Pipelines::Archiver.new(pipeline: funil.first, actor: user, new_default: novo_principal).perform

    expect(estado(card)['active']).to be(true)
  end
end
