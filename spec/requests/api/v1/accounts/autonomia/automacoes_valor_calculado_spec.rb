require 'rails_helper'

# G16 do #2414: a data que a automação calcula é gravada igual à que a tela grava num atributo do tipo data
# ("AAAA-MM-DD", o attributeDate do painel) e volta igual pelo mesmo caminho que a tela lê.
RSpec.describe 'Automação livre: data calculada lida pela tela', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, custom_attributes: { 'timezone' => 'America/Sao_Paulo' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pela_automacao) { create(:conversation, account: account) }
  let(:pela_tela) { create(:conversation, account: account) }
  let(:passo) do
    { 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Marcar a revisão',
      'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
      'corpo' => { 'merge' => true,
                   'custom_attributes' => { 'revisao' => { '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } } } } }
  end

  before do
    ligar_motor(account)
    create(:custom_attribute_definition, account: account, attribute_model: :conversation_attribute, attribute_key: 'revisao',
                                         attribute_display_type: :date)
  end

  after { Current.reset }

  def lida_pela_tela(conversa)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['custom_attributes']['revisao']
  end

  it 'grava e lê a mesma data que a tela grava e lê' do
    post "/api/v1/accounts/#{account.id}/conversations/#{pela_tela.display_id}/custom_attributes",
         params: { custom_attributes: { revisao: '2027-05-04' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    travel_to(Time.utc(2026, 11, 5, 1, 30)) do # 22h30 do dia 4 em São Paulo
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao_ligada(account, admin, [passo]), pela_automacao) }
    end

    expect([lida_pela_tela(pela_automacao), lida_pela_tela(pela_tela)]).to eq(%w[2027-05-04 2027-05-04])
  end

  describe 'no card' do
    around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

    let(:funil) { create_crm_pipeline(account: account, user: admin) }
    let(:cards) do
      Array.new(2) { |indice| account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: "Carro #{indice}", currency: 'BRL') }
    end
    let(:revisao_no_card) do
      data = { '$data' => { 'de' => 'hoje', 'mais' => { 'valor' => 6, 'unidade' => 'meses' } } }
      passo.merge('acao' => 'PATCH crm/cards/:id', 'caminho' => { 'id' => { '$valor' => 'card.id' } },
                  'corpo' => { 'card' => { 'custom_attributes' => { 'revisao' => data } } })
    end

    before do
      account.enable_features!('automacao_gatilhos')
      create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'revisao',
                                           attribute_display_type: :date)
    end

    def lido_do_card(card)
      get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      response.parsed_body.dig('payload', 'custom_attributes', 'revisao')
    end

    it 'grava e lê no card a mesma data que a tela grava e lê' do
      pela_automacao_no_card, pela_tela_no_card = cards
      patch "/api/v1/accounts/#{account.id}/crm/cards/#{pela_tela_no_card.id}",
            params: { card: { custom_attributes: { revisao: '2027-05-04' } } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)

      definicao = automacao_ligada(account, admin, [revisao_no_card], gatilho: { 'tipo' => 'card.ganho', 'funil_id' => funil.first.id })
      travel_to(Time.utc(2026, 11, 5, 1, 30)) do
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, pela_automacao_no_card) }
      end

      expect([lido_do_card(pela_automacao_no_card), lido_do_card(pela_tela_no_card)]).to eq(%w[2027-05-04 2027-05-04])
    end
  end
end
