require 'rails_helper'

# Este contato é (#2084/#2085): ler e gravar a relação do contato; ao tirar do funil, as sugestões de card que esperam
# uma pessoa expiram e, com "Arquivar", os cards abertos dele são arquivados.
RSpec.describe 'CRM contato relação API', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create_account_and_user.first }
  let(:admin) { account.users.first }
  let(:agent) { create_crm_agent(account: account).first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:contact) { account.contacts.create!(name: 'Joana Lima', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/contacts/#{contact.id}/relacao" }
  let!(:aberto) { card(:open) }

  before { account.enable_features!('contato_relacao') }

  def card(status)
    pipeline, stage = pipeline_and_stage
    created = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, inbox: inbox,
                                        primary_conversation: conversation, title: "Pedido #{SecureRandom.hex(3)}")
    created.update!(status: status) unless status == :open
    created
  end

  def sugestao
    Crm::SubjectDecision.create!(account: account, conversation: conversation, mode: 'suggest', action: 'create',
                                 state: 'suggested', title: 'Seguro auto', pipeline: pipeline_and_stage.first)
  end

  def marcar(relacao, arquivar_cards: false, user: admin)
    put url, params: { relacao: relacao, arquivar_cards: arquivar_cards }, headers: auth_headers(user), as: :json
  end

  it 'com a flag desligada, a rota não existe' do
    account.disable_features!('contato_relacao')

    get url, headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
    marcar('parceiro')
    expect(response).to have_http_status(:not_found)
    expect(contact.reload).to be_relacao_interessado
  end

  it 'lê a relação, os cards abertos e se a pessoa pode mudar' do
    card(:won)

    get url, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('relacao' => 'interessado', 'cardsAbertos' => 1, 'podeEditar' => true)
  end

  it 'tira do funil e arquiva o card aberto quando a pessoa escolhe Arquivar' do
    pendente = sugestao
    ganho = card(:won)

    marcar('parceiro', arquivar_cards: true)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('relacao' => 'parceiro', 'cardsArquivados' => 1, 'cardsNaoArquivados' => 0)
    expect(contact.reload).to be_relacao_parceiro
    expect(aberto.reload).to be_archived
    expect(ganho.reload).to be_won
    expect(pendente.reload.state).to eq('expired')
  end

  it 'com Deixar, o card continua aberto e a sugestão expira do mesmo jeito' do
    pendente = sugestao

    marcar('nao_e_negocio')

    expect(response.parsed_body).to eq('relacao' => 'nao_e_negocio', 'cardsArquivados' => 0, 'cardsNaoArquivados' => 0)
    expect(aberto.reload).to be_open
    expect(pendente.reload.state).to eq('expired')
  end

  it 'voltar para Interessado não mexe em sugestão nem em card' do
    contact.update!(relacao: :parceiro)
    pendente = sugestao

    marcar('interessado', arquivar_cards: true)

    expect(response.parsed_body).to include('relacao' => 'interessado', 'cardsArquivados' => 0)
    expect(aberto.reload).to be_open
    expect(pendente.reload.state).to eq('suggested')
  end

  it 'arquiva em lotes: contato com mais cards abertos que o lote não fica pela metade' do
    stub_const('Crm::Cards::BulkAction::MAX_IDS', 1)
    outro = card(:open)

    marcar('parceiro', arquivar_cards: true)

    expect(response.parsed_body).to include('cardsArquivados' => 2, 'cardsNaoArquivados' => 0)
    expect([aberto.reload, outro.reload]).to all(be_archived)
  end

  it 'avisa o painel Assuntos da conversa que tinha sugestão' do
    sugestao
    allow(Crm::Subjects::Notifier).to receive(:notify)

    marcar('parceiro')

    expect(Crm::Subjects::Notifier).to have_received(:notify).with(conversation).once
  end

  it 'o Guia pede confirmação antes de gravar (arquiva em lote e expira sugestões)' do
    expect(Autonomia::Guide::Acoes::SEM_DESFAZER).to include('PUT crm/contacts/:contact_id/relacao')
  end

  it 'recusa relação desconhecida sem mudar nada' do
    marcar('cliente')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload).to be_relacao_interessado
  end

  it 'não mexe em sugestão de conversa de outro contato' do
    outro = account.contacts.create!(name: 'Outro', phone_number: '+5511900000000')
    alheia = Crm::SubjectDecision.create!(account: account, conversation: create_crm_conversation(account: account, inbox: inbox, contact: outro),
                                          mode: 'suggest', action: 'create', state: 'suggested', pipeline: pipeline_and_stage.first)

    marcar('parceiro')

    expect(alheia.reload.state).to eq('suggested')
  end

  context 'with função personalizada sem contact_manage' do
    before do
      conversation
      role = create(:custom_role, account: account, permissions: %w[conversation_manage contact_view])
      agent.account_users.find_by(account: account).update!(custom_role: role)
    end

    it 'lê, mas não grava' do
      get url, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['podeEditar']).to be(false)

      marcar('parceiro', arquivar_cards: true, user: agent)
      expect(response).to have_http_status(:unauthorized)
      expect(contact.reload).to be_relacao_interessado
      expect(aberto.reload).to be_open
    end
  end
end
