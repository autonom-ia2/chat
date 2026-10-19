require 'rails_helper'

# #1786: sem o Google Tradutor, a conversa de e-mail nova traduz pela IA da conta num job (202 na hora, a tradução chega
# pelo message.updated). Com o Google, ou sem a chave conversa_email_nova, o translate do Chatwoot segue igual.
RSpec.describe 'Tradução do e-mail pela IA da conta' do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Hello', content_attributes: { email: { html_content: { full: '<p>Hello <b>Ana</b></p>' } } })
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k', api_base: 'https://api.openai.com' }, configured?: true)
    )
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create)
  end

  def traduzir(idioma = 'pt_BR')
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/translate",
         params: { target_language: idioma }, headers: agent.create_new_auth_token, as: :json
  end

  describe 'com a chave conversa_email_nova e sem o Google' do
    before { account.enable_features!('conversa_email_nova') }

    it 'responde 202 e põe a tradução num job, sem chamar a IA na requisição' do
      expect { traduzir }.to have_enqueued_job(ConversaCanal::TraduzirEmailJob).with(message.id, 'pt_BR')

      expect(response).to have_http_status(:accepted)
      expect(cliente).not_to have_received(:create)
    end

    it 'idioma fora da lista do painel: 422 e nada vai para a IA' do
      expect { traduzir('a1') }.not_to have_enqueued_job(ConversaCanal::TraduzirEmailJob)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    describe 'uma tradução por vez para a mensagem e o idioma' do
      before { Redis::Alfred.delete(ConversaCanal::TraduzirEmailJob.trava(message.id, 'pt_BR')) }

      after { Redis::Alfred.delete(ConversaCanal::TraduzirEmailJob.trava(message.id, 'pt_BR')) }

      it 'cliques repetidos enquanto ela corre: um job só, e todos respondem 202' do
        expect { 3.times { traduzir } }.to have_enqueued_job(ConversaCanal::TraduzirEmailJob).exactly(:once)

        expect(response).to have_http_status(:accepted)
      end

      it 'outro idioma da mesma mensagem é outra tradução' do
        Redis::Alfred.delete(ConversaCanal::TraduzirEmailJob.trava(message.id, 'en'))

        expect { traduzir && traduzir('en') }.to have_enqueued_job(ConversaCanal::TraduzirEmailJob).twice
      ensure
        Redis::Alfred.delete(ConversaCanal::TraduzirEmailJob.trava(message.id, 'en'))
      end

      it 'o job solta a trava no fim, mesmo quando a IA falha' do
        allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')
        traduzir

        ConversaCanal::TraduzirEmailJob.perform_now(message.id, 'pt_BR')

        expect { traduzir }.to have_enqueued_job(ConversaCanal::TraduzirEmailJob).once
      end
    end

    it 'já traduzido para o idioma: 200, sem job' do
      message.update!(translations: { 'pt_BR' => '<p>Olá</p>' })

      expect { traduzir }.not_to have_enqueued_job(ConversaCanal::TraduzirEmailJob)
      expect(response).to have_http_status(:ok)
    end
  end

  it 'sem a chave conversa_email_nova: o translate do Chatwoot, sem job e sem IA' do
    expect { traduzir }.not_to have_enqueued_job(ConversaCanal::TraduzirEmailJob)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to be_nil
    expect(cliente).not_to have_received(:create)
  end

  describe ConversaCanal::TraduzirEmailJob do
    before { account.enable_features!('conversa_email_nova') }

    it 'traduz o HTML pela IA, para o idioma pedido, e grava em translations' do
      allow(cliente).to receive(:create).and_return(text: { traducao: '<p>Olá <b>Ana</b></p>' }.to_json)

      described_class.perform_now(message.id, 'pt_BR')

      expect(message.reload.translations).to eq('pt_BR' => '<p>Olá <b>Ana</b></p>')
      expect(cliente).to have_received(:create).with(hash_including(input: '<p>Hello <b>Ana</b></p>',
                                                                    instructions: a_string_including('pt-BR')))
    end

    it 'já traduzido: não paga a IA de novo' do
      message.update!(translations: { 'pt_BR' => '<p>Olá</p>' })

      described_class.perform_now(message.id, 'pt_BR')

      expect(cliente).not_to have_received(:create)
    end

    it 'IA falhou: não grava nada e não quebra o job' do
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

      expect { described_class.perform_now(message.id, 'pt_BR') }.not_to raise_error
      expect(message.reload.translations).to be_blank
    end

    it 'IA falhou: o rastreador recebe só a classe do erro, sem a mensagem do provedor' do
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'Olá Ana, segue o contrato')
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

      described_class.perform_now(message.id, 'pt_BR')

      expect(ChatwootExceptionTracker).to have_received(:new) do |erro, **|
        expect(erro.message).to eq('Crm::Ai::ResponsesClient::Error')
      end
    end
  end
end
