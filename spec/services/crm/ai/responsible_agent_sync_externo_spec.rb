require 'rails_helper'

# #1606: caixa atendida por um agente externo (robô de fora, ex.: n8n) não aceita área (#1621, :robo_externo). Mesmo
# com um responsável configurado para o funil, não há vínculo de área na caixa: o Sync do assunto não troca o dono e nem
# chega a pedir a passagem ao PassarParaIa.
RSpec.describe Crm::Ai::ResponsibleAgentSync do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
  let(:externo) { create(:agent_bot, account: account, name: 'n8n') }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').first }
  let(:area) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Área Suporte', agent_type: 'custom', status: :active, enabled: true)
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_call_original
    allow(Autonomia::Agents::Config).to receive(:enabled?).with(account).and_return(true)
    Autonomia::Agents::Fase2.ligar!(account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: externo)
    account.crm_pipeline_inboxes.create!(pipeline: suporte, inbox: inbox, default_stage: suporte.stages.first, created_by: admin)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true)
    # A validação já recusa responsável sem vínculo de área; a linha simula uma configuração antiga, de antes do robô de fora.
    Crm::InboxAiAgent.new(account: account, inbox: inbox, pipeline: suporte, agent: area).save!(validate: false)
    conversation.update!(ai_assignee: externo)
    card = account.crm_cards.create!(pipeline: suporte, stage: suporte.stages.first, contact: contact,
                                     primary_conversation: conversation, inbox: inbox, title: 'Pedido')
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: Time.current)
    allow(Autonomia::Agents::PassarParaIa).to receive(:call).and_call_original
  end

  it 'caixa com agente externo: sem vínculo de área, o assunto não troca o dono nem pede passagem' do
    expect(Autonomia::Agents::AgentInbox.where(inbox_id: inbox.id)).to be_empty

    resultado = described_class.new(conversation: conversation.reload, motivo: described_class::FOCO).perform

    expect(resultado.trocou).to be(false)
    expect(conversation.reload.ai_assignee).to eq(externo)
    expect(Autonomia::Agents::PassarParaIa).not_to have_received(:call)
    expect(Crm::Passagem.where(conversation_id: conversation.id)).to be_empty
  end
end
