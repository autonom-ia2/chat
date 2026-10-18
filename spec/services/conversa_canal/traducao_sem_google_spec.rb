require 'rails_helper'

# #1786: sem o Google Tradutor, a conversa de e-mail nova traduz pela IA da conta; com ele, nada muda.
RSpec.describe ConversaCanal::TraducaoSemGoogle do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Hello', content_attributes: { email: { html_content: { full: '<p>Hello <b>Ana</b></p>' } } })
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:credencial) { { api_key: 'chave-de-teste', api_base: 'https://api.openai.com', source: :hook } }

  def traduzir(alvo = message)
    Integrations::GoogleTranslate::ProcessorService.new(message: alvo, target_language: 'pt_BR').perform
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, resolve: credencial, configured?: true)
    )
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  it 'sem Google, e-mail novo: traduz o HTML pela IA, para o idioma pedido' do
    account.enable_features!('conversa_email_nova')
    allow(cliente).to receive(:create).and_return(text: { traducao: '<p>Olá <b>Ana</b></p>' }.to_json)

    expect(traduzir).to eq('<p>Olá <b>Ana</b></p>')
    expect(cliente).to have_received(:create).with(hash_including(input: '<p>Hello <b>Ana</b></p>',
                                                                  instructions: a_string_including('pt-BR')))
  end

  it 'sem a chave conversa_email_nova: continua sem tradução, como no Chatwoot' do
    allow(cliente).to receive(:create)

    expect(traduzir).to be_nil
    expect(cliente).not_to have_received(:create)
  end

  it 'com o Google ligado: usa o Google e não chama a IA' do
    account.enable_features!('conversa_email_nova')
    create(:integrations_hook, account: account, app_id: 'google_translate',
                               settings: { 'project_id' => 'p', 'credentials' => {} })
    google = instance_double(Google::Cloud::Translate::V3::TranslationService::Client)
    allow(Google::Cloud::Translate::V3::TranslationService::Client).to receive(:new).and_return(google)
    allow(google).to receive(:translate_text).and_return(
      Struct.new(:translations).new([Struct.new(:translated_text).new('<p>Olá Ana</p>')])
    )
    allow(cliente).to receive(:create)

    expect(traduzir).to eq('<p>Olá Ana</p>')
    expect(cliente).not_to have_received(:create)
  end

  it 'IA falhou: devolve vazio, sem quebrar (a tela avisa)' do
    account.enable_features!('conversa_email_nova')
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    expect(traduzir).to be_nil
  end
end
