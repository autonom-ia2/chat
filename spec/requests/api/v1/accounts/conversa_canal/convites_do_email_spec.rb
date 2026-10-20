require 'rails_helper'

# #1984 — Sim / Talvez / Não ao convite de reunião pelo painel (PUT conversa_canal/convites_do_email/:message_id).
RSpec.describe 'Resposta ao convite de reunião', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
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
    create(:inbox_member, user: agente, inbox: caixa)
    allow(Mail::SMTP).to receive(:new).and_return(smtp)
  end

  def responder(resposta, usuario: agente, conversation_id: conversa.display_id)
    put "/api/v1/accounts/#{account.id}/conversa_canal/convites_do_email/#{mensagem.id}",
        params: { conversation_id: conversation_id, resposta: resposta }, headers: usuario.create_new_auth_token, as: :json
  end

  it 'responde ao organizador e devolve o convite com a resposta', :aggregate_failures do
    responder('aceito')

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['convite']).to include('minha_resposta' => 'aceito', 'via' => 'email', 'respondida_por' => agente.id)
    expect(smtp).to have_received(:deliver!).once
    expect(mensagem.reload.content_attributes['email']['convite']['minha_resposta']).to eq('aceito')
  end

  it 'resposta inválida: 422 com a frase para a tela', :aggregate_failures do
    responder('quem_sabe')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.convite.resposta_invalida'))
  end

  it 'servidor de e-mail fora: 502 e nada é gravado', :aggregate_failures do
    allow(smtp).to receive(:deliver!).and_raise(Net::OpenTimeout)

    responder('aceito')

    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.convite.falhou'))
    expect(mensagem.reload.content_attributes['email']['convite']).not_to have_key('minha_resposta')
  end

  it 'agente fora da caixa não responde' do
    outro = create(:user, account: account, role: :agent)

    responder('aceito', usuario: outro)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'mensagem de outra conversa não é achada' do
    outra = create(:conversation, account: account, inbox: caixa)

    responder('aceito', conversation_id: outra.display_id)

    expect(response).to have_http_status(:not_found)
  end

  it 'sem a conversa com a cara do canal: 404' do
    account.disable_features!('conversa_cara_do_canal')
    account.save!

    responder('aceito')

    expect(response).to have_http_status(:not_found)
  end
end
