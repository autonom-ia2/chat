require 'rails_helper'

# #2216, caminho da conversa visível: a gaveta Nova conversa, numa caixa com "Reabrir a mesma conversa", manda a
# mensagem pela API de mensagem com o sinal `reabrir_ao_escrever`. Com o sinal, a conversa resolvida ou adiada reabre
# sem mudar quem cuida. Resposta comum (sem o sinal) segue como sempre: a conversa resolvida continua resolvida.
RSpec.describe 'Mensagem da gaveta reabre a conversa (#2216)', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, lock_to_single_conversation: true) }
  let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:dona) { create(:user, account: account, role: :agent, auto_offline: false) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    create(:inbox_member, user: dona, inbox: inbox)
  end

  def conversa_com(status:, assignee: dona, **extra)
    create(:conversation, account: account, inbox: inbox, status: status, assignee: assignee, **extra)
  end

  def escrever(conversa, sinal: true, headers: agent.create_new_auth_token, **extra)
    params = { content: 'Oi, tudo bem?', private: false }.merge(extra)
    params[:reabrir_ao_escrever] = sinal unless sinal.nil?
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         headers: headers, params: params, as: :json
  end

  it 'com o sinal, a conversa resolvida reabre, a mensagem entra e quem cuida não muda' do
    conversa = conversa_com(status: :resolved)

    escrever(conversa)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_open
    expect(conversa.assignee).to eq(dona)
    expect(conversa.messages.outgoing.last.content).to eq('Oi, tudo bem?')
  end

  it 'com o sinal, a conversa adiada reabre' do
    conversa = conversa_com(status: :snoozed, snoozed_until: 2.days.from_now)

    escrever(conversa)

    expect(conversa.reload).to be_open
    expect(conversa.snoozed_until).to be_nil
  end

  it 'com o sinal e ninguém cuidando, continua sem ninguém mesmo com o rodízio da caixa ligado' do
    conversa = conversa_com(status: :resolved, assignee: nil)

    escrever(conversa)

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to be_nil
  end

  it 'o sinal no formulário (com anexo) também vale' do
    conversa = conversa_com(status: :resolved)

    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         headers: agent.create_new_auth_token,
         params: { content: 'Segue', private: 'false', reabrir_ao_escrever: 'true',
                   attachments: [Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')] }

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_open
  end

  it 'sem o sinal, a resposta comum não muda nada' do
    conversa = conversa_com(status: :resolved)

    escrever(conversa, sinal: nil)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
    expect(conversa.assignee).to eq(dona)
  end

  it 'com o sinal falso, não reabre' do
    conversa = conversa_com(status: :resolved)

    escrever(conversa, sinal: false)

    expect(conversa.reload).to be_resolved
  end

  it 'o sinal numa conversa aberta não faz nada' do
    conversa = conversa_com(status: :open)
    status_changed_at = conversa.reload.status_changed_at

    escrever(conversa)

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_open
    expect(conversa.status_changed_at).to eq(status_changed_at)
  end

  it 'nota privada com o sinal não reabre' do
    conversa = conversa_com(status: :resolved)

    escrever(conversa, private: true)

    expect(conversa.reload).to be_resolved
  end

  it 'caixa que cria conversas novas: o sinal não reabre' do
    inbox.update!(lock_to_single_conversation: false)
    conversa = conversa_com(status: :resolved)

    escrever(conversa)

    expect(conversa.reload).to be_resolved
  end

  it 'se a mensagem não sai, a conversa não reabre' do
    conversa = conversa_com(status: :resolved)
    builder = instance_double(Messages::MessageBuilder)
    allow(Messages::MessageBuilder).to receive(:new).and_return(builder)
    allow(builder).to receive(:perform).and_raise(ActiveRecord::RecordInvalid.new(Message.new))

    escrever(conversa)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversa.reload).to be_resolved
  end

  it 'robô (token de AgentBot) não reabre, mesmo com o sinal' do
    conversa = conversa_com(status: :snoozed, snoozed_until: 2.days.from_now)
    robo = create(:agent_bot, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: robo)

    escrever(conversa, headers: { api_access_token: robo.access_token.token })

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_snoozed
  end

  it 'integração com o token de API de uma pessoa não reabre, mesmo com o sinal' do
    conversa = conversa_com(status: :resolved)

    escrever(conversa, headers: { api_access_token: agent.access_token.token })

    expect(response).to have_http_status(:success)
    expect(conversa.reload).to be_resolved
  end
end
