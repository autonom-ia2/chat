require 'rails_helper'

# IA entende a conversa F3 (decisão do Rodrigo, 22/10): a sugestão de fechar o card chega à tela pelo mesmo cartão da
# sugestão de etapa (`fechar` no payload) e se responde pelos mesmos botões. Aceitar fecha com a pessoa como autora;
# recusar não fecha nada.
RSpec.describe 'Sugestão de fechar o card', type: :request do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:stage) { funil_e_etapa.last }
  let(:card) { account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: stage, title: 'Pedido', currency: 'BRL') }
  let!(:sugestao) do
    account.crm_ai_stage_suggestions.create!(
      card: card, from_stage: stage, to_stage: stage, confidence: 0.86, reasoning: 'Disse que vai pensar.', model_used: 'm',
      metadata: { fechar: { resultado: 'perdido', motivo: 'recusou' }, lido_em: Time.current.utc.iso8601(6) }
    )
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  before { account.enable_features!(Crm::Ai::FecharCard::FLAG) }

  def url(acao) = "/api/v1/accounts/#{account.id}/crm/ai_suggestions/#{sugestao.id}/#{acao}"

  it 'o cartão da sugestão traz o que fechar' do
    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/current_ai_suggestion", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body.dig('payload', 'fechar')).to eq('resultado' => 'perdido', 'motivo' => 'recusou')
  end

  it 'aceitar fecha o card com o motivo', :aggregate_failures do
    post url('accept'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload).to have_attributes(status: 'lost', lost_reason: 'Declined')
    expect(sugestao.reload).to be_accepted
  end

  it 'recusar não fecha nada', :aggregate_failures do
    post url('dismiss'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload).to be_open
    expect(sugestao.reload).to be_dismissed
  end

  # Revisão adversarial (item 10): o "Encerrar" de um card que já fechou seguia na tela, e o aceite respondia 200.
  describe 'card já fechado' do
    before { Crm::Cards::Closer.new(card: card, actor: admin, result: 'won').perform }

    it 'a sugestão de fechar some da tela' do
      get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/current_ai_suggestion", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_nil
    end

    it 'aceitar responde 422 e não mexe no card', :aggregate_failures do
      sugestao.update_columns(status: Crm::AiStageSuggestion.statuses[:pending]) # rubocop:disable Rails/SkipsModelValidations

      post url('accept'), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload).to be_won
      expect(sugestao.reload).to be_expired
    end
  end

  # Revisão adversarial (item 2): o cliente escreveu depois da leitura que gerou a sugestão.
  it 'mensagem do cliente depois da leitura: 422, e a sugestão expira', :aggregate_failures do
    conversa = create(:conversation, account: account)
    card.update!(primary_conversation: conversa)
    create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Mudei de ideia')

    post url('accept'), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.ai.suggestion_expired')
    expect(card.reload).to be_open
    expect(sugestao.reload).to be_expired
  end

  # Pega (revisão): a conta que desligou a flag seguir vendo e aceitando o "Encerrar" gravado antes.
  describe 'conta que desligou a flag' do
    before { account.disable_features!(Crm::Ai::FecharCard::FLAG) }

    it 'a sugestão de fechar some da tela' do
      get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/current_ai_suggestion", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_nil
    end

    it 'aceitar não fecha; a sugestão expira', :aggregate_failures do
      post url('accept'), headers: admin.create_new_auth_token, as: :json

      expect(card.reload).to be_open
      expect(sugestao.reload).to be_expired
    end
  end

  # Pega: a sugestão de etapa de sempre ganhar um campo novo na resposta.
  it 'a sugestão de etapa não traz `fechar`' do
    sugestao.update!(metadata: {})

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/current_ai_suggestion", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).not_to have_key('fechar')
  end
end
