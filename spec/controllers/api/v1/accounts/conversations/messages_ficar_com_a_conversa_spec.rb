require 'rails_helper'

# #2067: o envio pelo painel leva `ficar_com_a_conversa` e o dono que a tela viu (`ficar_com_a_conversa_de`), e quem
# atribui é o servidor, depois da mensagem gravada: texto, anexo e modelo seguem a mesma regra. Só com a flag da conta
# (`ficar_com_a_conversa_ao_enviar`); sem ela, ou sem o parâmetro, a regra de antes (#1377/#1499).
RSpec.describe 'Ficar com a conversa ao enviar pela API do painel', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:joao) { create(:user, account: account, role: :agent, name: 'João') }
  let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }
  let(:da_ia) { { tipo: 'ia' } }

  before do
    account.enable_features!('ficar_com_a_conversa_ao_enviar')
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

    enviar({ content: 'Oi', ficar_com_a_conversa: true, ficar_com_a_conversa_de: da_ia })

    expect(response).to have_http_status(:success)
    expect(conversation.messages.where(sender: ana).count).to eq(1)
    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    expect(response.parsed_body).not_to have_key('ficar_com_a_conversa_nao_deu')
  end

  # Pega o 422 com o dono visto malformado: a mensagem sai e vale como se o pedido não dissesse quem a tela viu.
  it 'dono visto malformado (texto, número, lista, id objeto): a mensagem sai, sem 422', :aggregate_failures do
    conversation.update!(ai_assignee: bot)
    ['texto', 42, %w[pessoa 9], { tipo: 'pessoa', id: { x: 1 } }].each_with_index do |dado, indice|
      enviar({ content: "Oi #{indice}", ficar_com_a_conversa: true, ficar_com_a_conversa_de: dado })
      expect(response).to have_http_status(:success)
    end
    expect(conversation.messages.where(sender: ana).count).to eq(4)
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'ícone com valor fora do booleano: ignorado (a regra de antes), sem 422', :aggregate_failures do
    conversation.update!(ai_assignee: bot)

    enviar({ content: 'Oi', ficar_com_a_conversa: 'sim', ficar_com_a_conversa_de: da_ia })

    expect(response).to have_http_status(:success)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'modelo segue a regra do texto: na conversa do colega, sem o ícone, continua com o colega', :aggregate_failures do
    conversation.update!(assignee: joao)
    modelo = { name: 'boas_vindas', category: 'UTILITY', language: 'pt_BR', processed_params: {} }
    do_joao = { tipo: 'pessoa', id: joao.id }

    enviar({ content: 'Olá', template_params: modelo, ficar_com_a_conversa: false, ficar_com_a_conversa_de: do_joao })

    expect(response).to have_http_status(:success)
    expect(conversation.reload.assignee_id).to eq(joao.id)

    enviar({ content: 'Olá de novo', template_params: modelo, ficar_com_a_conversa: true, ficar_com_a_conversa_de: do_joao })

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'anexo pelo formulário (multipart) leva o pedido e o dono visto como texto' do
    conversation.update!(assignee: joao)
    arquivo = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { attachments: [arquivo], private: 'false', ficar_com_a_conversa: 'true',
                   ficar_com_a_conversa_de: { tipo: 'pessoa', id: joao.id.to_s } },
         headers: ana.create_new_auth_token

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  # Pega a corrida: um colega pegou a conversa enquanto a pessoa escrevia, e a tela mostrava a IA.
  it 'a tela viu a IA, o colega pegou antes do envio: continua com o colega e a resposta avisa', :aggregate_failures do
    conversation.update!(assignee: joao)

    enviar({ content: 'Oi', ficar_com_a_conversa: true, ficar_com_a_conversa_de: da_ia })

    expect(response).to have_http_status(:success)
    expect(conversation.reload.assignee_id).to eq(joao.id)
    expect(response.parsed_body['ficar_com_a_conversa_nao_deu']).to be(true)
  end

  # Pega a atribuição antes de gravar: mensagem recusada pelo servidor não muda o dono.
  it 'mensagem recusada não muda quem está com a conversa', :aggregate_failures do
    conversation.update!(ai_assignee: bot)

    enviar({ content: "#{'h' * 150 * 1000}a", ficar_com_a_conversa: true, ficar_com_a_conversa_de: da_ia })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  it 'sem o parâmetro (API, app): o robô atendendo continua com a conversa' do
    conversation.update!(ai_assignee: bot)

    enviar({ content: 'Oi' })

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Pega a flag desligada vazando o comportamento novo: o servidor ignora o pedido.
  it 'flag desligada na conta: o servidor ignora o pedido e vale a regra de antes', :aggregate_failures do
    account.disable_features!('ficar_com_a_conversa_ao_enviar')
    conversation.update!(ai_assignee: bot)

    enviar({ content: 'Oi', ficar_com_a_conversa: true, ficar_com_a_conversa_de: da_ia })

    expect(response).to have_http_status(:success)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end

  # Quem não pode operar a conversa não envia, e portanto não fica com ela (a mesma porta da atribuição).
  it 'quem não alcança a conversa não envia nem fica com ela', :aggregate_failures do
    conversation.update!(ai_assignee: bot)
    de_fora = create(:user, account: account, role: :agent)

    enviar({ content: 'Oi', ficar_com_a_conversa: true, ficar_com_a_conversa_de: da_ia }, como: de_fora)

    expect(response).to have_http_status(:unauthorized)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
  end
end
