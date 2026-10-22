require 'rails_helper'

# IA entende a conversa F1: quem falou, num lugar só (a IA de etapa e a de assunto leem daqui).
RSpec.describe Crm::Ai::PapelDaMensagem do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:nosso_robo) { create(:agent_bot, account: account) }
  let(:robo_de_fora) { create(:agent_bot, account: account) }

  before do
    Autonomia::Agents::AgentInbox.create!(account: account, inbox: inbox, agent_bot: nosso_robo,
                                          agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'))
  end

  def mensagem(tipo, sender: nil, atributos: {})
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: 'texto',
                               sender: sender)
    message.update_columns(content_attributes: atributos) if atributos.present? # rubocop:disable Rails/SkipsModelValidations
    message
  end

  def papel(message) = described_class.de(message, robos: described_class.robos_da_conta(account.id))

  it 'distingue os quatro papéis', :aggregate_failures do
    expect(papel(mensagem(:incoming, sender: contact))).to eq('customer')
    expect(papel(mensagem(:outgoing, sender: admin))).to eq('human_agent')
    expect(papel(mensagem(:outgoing, sender: nosso_robo))).to eq('platform_agent')
    expect(papel(mensagem(:outgoing, sender: robo_de_fora))).to eq('external_agent')
  end

  it 'o follow-up e o Agendamento em nome de uma pessoa são da plataforma', :aggregate_failures do
    expect(papel(mensagem(:outgoing, sender: admin, atributos: { 'crm_follow_up_id' => 1 }))).to eq('platform_agent')
    expect(papel(mensagem(:outgoing, sender: admin, atributos: { 'crm_booking_invite_id' => 2 }))).to eq('platform_agent')
    expect(papel(mensagem(:outgoing, sender: admin, atributos: { 'crm_booking_notice' => 'lembrete' }))).to eq('platform_agent')
  end

  it 'o eco do celular é pessoa da equipe; a saída sem remetente e sem eco é de outro sistema', :aggregate_failures do
    eco = mensagem(:outgoing)
    eco.update_columns(sender_type: nil, sender_id: nil, content_attributes: { 'external_echo' => true }) # rubocop:disable Rails/SkipsModelValidations
    automacao = mensagem(:outgoing)
    automacao.update_columns(sender_type: nil, sender_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect(papel(eco.reload)).to eq('human_agent')
    expect(papel(automacao.reload)).to eq('external_agent')
  end

  it 'os robôs da conta são só os dos vínculos dela' do
    outra = create(:account)
    create(:agent_bot, account: outra)

    expect(described_class.robos_da_conta(account.id)).to eq(Set[nosso_robo.id])
  end
end
