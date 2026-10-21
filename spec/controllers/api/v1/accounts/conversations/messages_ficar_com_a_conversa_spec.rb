require 'rails_helper'

# #2067: o envio pelo painel leva `ficar_com_a_conversa`, e quem atribui é o servidor, depois da mensagem gravada: texto,
# anexo e modelo seguem a mesma regra. Sem o parâmetro, a regra de antes (#1377/#1499).
RSpec.describe 'Ficar com a conversa ao enviar pela API do painel', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:joao) { create(:user, account: account, role: :agent, name: 'João') }
  let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [ana, joao].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  def enviar(params, como: ana)
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: params, headers: como.create_new_auth_token, as: :json
  end

  it 'texto com o ícone ligado, na conversa da IA: a mensagem sai e a conversa fica com quem enviou', :aggregate_failures do
    conversation.update!(ai_assignee: bot)

    enviar({ content: 'Oi', ficar_com_a_conversa: true })

    expect(response).to have_http_status(:success)
    expect(conversation.messages.where(sender: ana).count).to eq(1)
    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
  end

  it 'modelo segue a regra do texto: na conversa do colega, sem o ícone, continua com o colega', :aggregate_failures do
    conversation.update!(assignee: joao)
    modelo = { name: 'boas_vindas', category: 'UTILITY', language: 'pt_BR', processed_params: {} }

    enviar({ content: 'Olá', template_params: modelo, ficar_com_a_conversa: false })

    expect(response).to have_http_status(:success)
    expect(conversation.reload.assignee_id).to eq(joao.id)

    enviar({ content: 'Olá de novo', template_params: modelo, ficar_com_a_conversa: true })

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'anexo pelo formulário (multipart) leva o pedido como texto' do
    conversation.update!(ai_assignee: bot)
    arquivo = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { attachments: [arquivo], private: 'false', ficar_com_a_conversa: 'true' },
         headers: ana.create_new_auth_token

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # Pega a atribuição antes do aceite: mensagem recusada não muda o dono.
  it 'mensagem recusada não muda quem está com a conversa', :aggregate_failures do
    conversation.update!(ai_assignee: bot)

    enviar({ content: "#{'h' * 150 * 1000}a", ficar_com_a_conversa: true })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'sem o parâmetro (API, app): o robô atendendo continua com a conversa' do
    conversation.update!(ai_assignee: bot)

    enviar({ content: 'Oi' })

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Quem não pode operar a conversa não envia, e portanto não fica com ela (a mesma porta da atribuição).
  it 'quem não alcança a conversa não envia nem fica com ela', :aggregate_failures do
    conversation.update!(ai_assignee: bot)
    de_fora = create(:user, account: account, role: :agent)

    enviar({ content: 'Oi', ficar_com_a_conversa: true }, como: de_fora)

    expect(response).to have_http_status(:unauthorized)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end
end
