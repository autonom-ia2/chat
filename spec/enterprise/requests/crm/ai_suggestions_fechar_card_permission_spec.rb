require 'rails_helper'

# IA entende a conversa F3 (revisão adversarial, item 4): aceitar a sugestão de fechar É fechar o card, e aceitar o "era
# teste" É arquivar. Além da chave de IA (`crm_manage_ai`, a do aceite de sempre), cada um pede a permissão do gesto
# manual: fechar (CardPolicy#close?, `crm_manage_cards`) e arquivar (CardPolicy#destroy?, `crm_delete_cards`).
RSpec.describe 'Aceitar a sugestão de fechar com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent, admin]) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:stage) { pipeline_and_stage.last }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: stage, contact: contact, primary_conversation: conversation,
                              inbox: inbox, owner: agent, title: 'Renovação')
  end

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  before { account.enable_features!(Crm::Ai::FecharCard::FLAG) }

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def sugestao(fechar)
    account.crm_ai_stage_suggestions.create!(
      card: card, from_stage: stage, to_stage: stage, confidence: 0.86, reasoning: 'x', model_used: 'm',
      metadata: { fechar: fechar, lido_em: Time.current.utc.iso8601(6) }
    )
  end

  def aceitar(sugestao)
    post "/api/v1/accounts/#{account.id}/crm/ai_suggestions/#{sugestao.id}/accept", headers: agent.create_new_auth_token, as: :json
  end

  describe 'com a chave de IA, sem poder mexer no card' do
    before { give_role(%w[crm_view crm_manage_ai conversation_participating_manage]) }

    it 'não fecha o card', :aggregate_failures do
      fechar = sugestao(resultado: 'perdido', motivo: 'recusou')

      aceitar(fechar)

      expect(response).to have_http_status(:unauthorized)
      expect(card.reload).to be_open
      expect(fechar.reload).to be_pending
    end
  end

  describe 'com a chave de IA e Pode mexer, sem Arquivar' do
    before { give_role(%w[crm_view crm_manage_ai crm_manage_cards conversation_participating_manage]) }

    it 'não arquiva pelo "era teste"', :aggregate_failures do
      teste = sugestao(resultado: Crm::Ai::FecharCard::ARQUIVADO, motivo: Crm::Ai::NaoENegocio::MOTIVO_TESTE)

      aceitar(teste)

      expect(response).to have_http_status(:unauthorized)
      expect(card.reload).to be_open
    end

    it 'fecha pelo "perdido"' do
      aceitar(sugestao(resultado: 'perdido', motivo: 'recusou'))

      expect(card.reload).to be_lost
    end
  end

  describe 'com a chave de IA, Pode mexer e Arquivar' do
    before { give_role(%w[crm_view crm_manage_ai crm_manage_cards crm_delete_cards conversation_participating_manage]) }

    it 'arquiva pelo "era teste"' do
      aceitar(sugestao(resultado: Crm::Ai::FecharCard::ARQUIVADO, motivo: Crm::Ai::NaoENegocio::MOTIVO_TESTE))

      expect(card.reload).to be_archived
    end
  end
end
