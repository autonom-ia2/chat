require 'rails_helper'

# Multifunil 5b (#1145): a sugestão de assunto da IA (modo Sugerir) no painel Assuntos, com Criar e Ignorar.
RSpec.describe 'CRM subject suggestions API', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create_account_and_user.first }
  let(:admin) { account.users.first }
  let(:agent) { create_crm_agent(account: account).first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:contact) { account.contacts.create!(name: 'Joana Lima', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin, name: 'Comercial') }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}" }
  let(:finder) { Crm::Cards::ConversationCardFinder.new(account: account) }

  let!(:setting) { account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, subject_ai_mode: :suggest) }

  before { account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: admin) }

  def card(title, focused_at: nil)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, inbox: inbox,
                              primary_conversation: conversation, title: title).tap do |created|
      Crm::CardConversation.find_or_create_by!(account: account, card: created, conversation: conversation)
                           .update!(is_primary: true, focused_at: focused_at)
    end
  end

  def suggestion(action:, title: nil, target: nil, state: 'suggested')
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
    Crm::SubjectDecision.create!(account: account, conversation: conversation, message: message, mode: 'suggest',
                                 action: action, state: state, title: title, pipeline: pipeline, card: target)
  end

  def accept(decision, user: agent)
    post "#{base_url}/subject_suggestions/#{decision.id}/accept", headers: auth_headers(user)
  end

  it 'traz a sugestão esperando junto da lista de assuntos' do
    card('Agentes de IA', focused_at: 1.hour.ago)
    decision = suggestion(action: 'create', title: 'Chat2You')
    suggestion(action: 'create', title: 'Antiga', state: 'expired')

    get "#{base_url}/cards", headers: auth_headers(agent)

    expect(response.parsed_body['suggestion']).to include('id' => decision.id, 'action' => 'create', 'title' => 'Chat2You',
                                                          'pipeline_name' => 'Comercial')
  end

  it 'sem sugestão esperando, suggestion vem vazio' do
    card('Agentes de IA')

    get "#{base_url}/cards", headers: auth_headers(agent)

    expect(response.parsed_body).to include('suggestion' => nil)
  end

  it 'não mostra sugestão sobre um card que já fechou' do
    agentes = card('Agentes de IA', focused_at: 2.hours.ago)
    card('Chat2You', focused_at: 1.hour.ago)
    suggestion(action: 'focus', target: agentes)
    agentes.update!(status: :won)

    get "#{base_url}/cards", headers: auth_headers(agent)

    expect(response.parsed_body['suggestion']).to be_nil
  end

  it 'Criar: nasce o card do pedido novo na primeira etapa, vira o assunto atual, e a sugestão fica aceita' do
    card('Agentes de IA', focused_at: 1.hour.ago)
    decision = suggestion(action: 'create', title: 'Chat2You')
    allow(Crm::Subjects::Notifier).to receive(:notify)

    expect { accept(decision) }.to change(Crm::Card, :count).by(1)

    novo = account.crm_cards.order(:id).last
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'card_id')).to eq(novo.id)
    expect(novo).to have_attributes(title: 'Chat2You', stage_id: stage.id)
    expect(finder.find(conversation)).to eq(novo)
    expect(decision.reload).to have_attributes(state: 'accepted', card_id: novo.id)
    expect(Crm::Subjects::Notifier).to have_received(:notify).with(conversation)
  end

  it 'dar nome: o assunto atual ganha o nome sugerido' do
    atual = card('Joana Lima')
    decision = suggestion(action: 'rename', title: 'Agentes de IA', target: atual)

    accept(decision)

    expect(response).to have_http_status(:ok)
    expect(atual.reload.title).to eq('Agentes de IA')
    expect(Crm::Subjects::Naming.named?(atual)).to be(true)
  end

  it 'voltar a um assunto: o card sugerido vira o assunto atual' do
    agentes = card('Agentes de IA', focused_at: 2.hours.ago)
    card('Chat2You', focused_at: 1.hour.ago)
    decision = suggestion(action: 'focus', target: agentes)

    accept(decision)

    expect(finder.find(conversation)).to eq(agentes)
  end

  it 'responder duas vezes não cria dois cards' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    accept(decision)

    expect { accept(decision) }.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.conversation_cards.suggestion_expired')
  end

  it 'card fechado depois da sugestão não volta a ser o assunto' do
    agentes = card('Agentes de IA', focused_at: 2.hours.ago)
    decision = suggestion(action: 'focus', target: agentes)
    agentes.update!(status: :lost)

    accept(decision)

    expect(response.parsed_body['error']).to eq('crm.conversation_cards.closed_card')
    expect(decision.reload.state).to eq('expired')
  end

  it 'card apagado depois da sugestão: o aviso some e aceitar responde que fechou' do
    agentes = card('Agentes de IA', focused_at: 2.hours.ago)
    decision = suggestion(action: 'focus', target: agentes)
    Crm::CardConversation.where(card: agentes).delete_all
    agentes.delete

    get "#{base_url}/cards", headers: auth_headers(agent)
    expect(response.parsed_body['suggestion']).to be_nil

    accept(decision)
    expect(response.parsed_body['error']).to eq('crm.conversation_cards.closed_card')
    expect(decision.reload.state).to eq('expired')
  end

  it 'funil arquivado ou tirado da caixa: o aviso de criar some e não nasce card' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    account.crm_pipeline_inboxes.where(pipeline: pipeline).delete_all

    get "#{base_url}/cards", headers: auth_headers(agent)
    expect(response.parsed_body['suggestion']).to be_nil

    expect { accept(decision) }.not_to change(Crm::Card, :count)
    expect(response.parsed_body['error']).to eq('crm.conversation_cards.pipeline_unavailable')
    expect(decision.reload.state).to eq('expired')
  end

  it 'Criar numa conversa sem responsável: quem aceitou fica dono, como no Novo assunto feito à mão' do
    conversation.update!(assignee: nil)
    decision = suggestion(action: 'create', title: 'Chat2You')

    accept(decision)

    expect(account.crm_cards.order(:id).last.owner).to eq(agent)
  end

  it 'caixa que saiu do modo Sugerir (#1221): o aviso some e as sugestões pendentes expiram' do
    card('Agentes de IA')
    decision = suggestion(action: 'create', title: 'Chat2You')
    allow(Crm::Subjects::Notifier).to receive(:notify)

    setting.update!(subject_ai_mode: :off)

    expect(Crm::Subjects::Notifier).to have_received(:notify).with(conversation)

    get "#{base_url}/cards", headers: auth_headers(agent)
    expect(response.parsed_body['suggestion']).to be_nil
    expect(decision.reload.state).to eq('expired')
  end

  it 'CRM desligado na caixa também expira as sugestões pendentes' do
    decision = suggestion(action: 'create', title: 'Chat2You')

    setting.update!(crm_enabled: false)

    expect(decision.reload.state).to eq('expired')
  end

  it 'aceitar sugestão de caixa que não está mais em Sugerir não cria card' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    setting.update_columns(subject_ai_mode: Crm::InboxSetting.subject_ai_modes[:auto]) # rubocop:disable Rails/SkipsModelValidations

    expect { accept(decision) }.not_to change(Crm::Card, :count)
    expect(response.parsed_body['error']).to eq('crm.conversation_cards.mode_changed')
    expect(decision.reload.state).to eq('expired')
  end

  it 'salvar a caixa que segue em Sugerir não mexe nas sugestões' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    setting.update!(subject_ai_mode: :suggest, auto_create_card: true)

    expect(decision.reload.state).to eq('suggested')
  end

  it 'Ignorar marca a sugestão e não mexe nos cards' do
    card('Agentes de IA')
    decision = suggestion(action: 'create', title: 'Chat2You')

    expect do
      post "#{base_url}/subject_suggestions/#{decision.id}/dismiss", headers: auth_headers(agent)
    end.not_to change(Crm::Card, :count)

    expect(response).to have_http_status(:no_content)
    expect(decision.reload.state).to eq('dismissed')
  end

  it 'sugestão de outra conversa não é encontrada' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    other = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)

    post "/api/v1/accounts/#{account.id}/crm/conversations/#{other.display_id}/subject_suggestions/#{decision.id}/accept",
         headers: auth_headers(agent)

    expect(response).to have_http_status(:not_found)
  end

  it 'quem não é da caixa não responde à sugestão' do
    decision = suggestion(action: 'create', title: 'Chat2You')
    outsider = create_crm_agent(account: account, name: 'Fora da caixa').first

    expect { accept(decision, user: outsider) }.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:unauthorized)
  end
end
