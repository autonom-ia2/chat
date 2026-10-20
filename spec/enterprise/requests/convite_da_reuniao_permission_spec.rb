require 'rails_helper'

# #1984 — responder ao convite de reunião fala em nome da caixa: é escrita, e passa por ConversationPolicy#show? (o trio
# conversation_*). Função só com conversation_view lê a conversa e o cartão, mas não responde (parecer da sessão Funções
# personalizadas, 20/10).
RSpec.describe 'Resposta ao convite de reunião com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:canal) do
    create(:channel_email, account: account, email: 'vendas@empresa.example', smtp_enabled: true, smtp_address: 'smtp.empresa.example',
                           smtp_port: 587, smtp_login: 'vendas@empresa.example', smtp_password: 'senha-de-teste')
  end
  let(:caixa) { canal.inbox }
  let(:conversa) { create(:conversation, account: account, inbox: caixa) }
  let(:convite) do
    { uid: 'uid-1@google.com', sequencia: 0, metodo: 'REQUEST', titulo: 'Alinhamento', inicio: 2.days.from_now.to_i,
      organizador: { email: 'diana@agencia.example' }, convidados: [{ email: 'vendas@empresa.example' }] }
  end
  let!(:mensagem) do
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming,
                     content_attributes: { email: { convite: convite } })
  end
  let(:smtp) { instance_double(Mail::SMTP, deliver!: true) }

  before do
    account.enable_features!('conversa_cara_do_canal', 'convite_da_reuniao')
    account.save!
    allow(Mail::SMTP).to receive(:new).and_return(smtp)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    caixa.add_members([user.id])
    user
  end

  def responder(usuario)
    put "/api/v1/accounts/#{account.id}/conversa_canal/convites_do_email/#{mensagem.id}",
        params: { conversation_id: conversa.display_id, resposta: 'aceito' }, headers: usuario.create_new_auth_token, as: :json
  end

  it 'só com conversation_view: 401, nada sai e nada é gravado', :aggregate_failures do
    responder(pessoa_com(%w[conversation_view]))

    expect(response).to have_http_status(:unauthorized)
    expect(smtp).not_to have_received(:deliver!)
    expect(mensagem.reload.content_attributes['email']['convite']).not_to have_key('minha_resposta')
  end

  it 'com conversation_manage responde' do
    responder(pessoa_com(%w[conversation_manage]))

    expect(response).to have_http_status(:ok)
  end
end
