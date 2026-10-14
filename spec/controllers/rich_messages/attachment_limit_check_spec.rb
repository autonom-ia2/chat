require 'rails_helper'

# chat#1473 (P4, opção A): quem cria pela API uma mensagem de WhatsApp com 2 ou mais anexos recebe 422 com o motivo,
# e nada é gravado. Com 1 anexo, nos outros canais e em nota privada, a criação é a de sempre.
describe RichMessages::AttachmentLimitCheck, type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :administrator) }

  def file(name = 'avatar.png')
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', name), 'image/png')
  end

  def create_message(target, params)
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: target.display_id),
         params: params, headers: agent.create_new_auth_token
  end

  it 'answers 422 with the reason and creates nothing for two attachments on WhatsApp' do
    expect { create_message(conversation, content: 'Arquivos', attachments: [file, file('sample.png')]) }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(RichMessages::AttachmentLimit::ONE_PER_MESSAGE)
  end

  it 'creates a WhatsApp message with one attachment as before (what the panel sends)' do
    expect { create_message(conversation, content: 'Arquivo', attachments: [file]) }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(Message.last.attachments.count).to eq(1)
  end

  it 'creates a WhatsApp private note with two attachments, which never goes to the channel' do
    expect { create_message(conversation, content: 'Nota', private: 'true', attachments: [file, file('sample.png')]) }
      .to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
  end

  it 'creates a WhatsApp message with template params and two attachments, which goes out by send_template' do
    template_params = { name: 'aviso', language: 'pt_BR', processed_params: { body: { '1' => 'Ana' } } }

    expect { create_message(conversation, content: 'Modelo', template_params: template_params, attachments: [file, file('sample.png')]) }
      .to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
  end

  it 'leaves the MCP integration request to its own path, without checking the attachments' do
    allow(Api::V1::Accounts::Conversations::MessagesController).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |controller| allow(controller).to receive(:mcp_integration_token_request?).and_return(true) }
    end
    allow(RichMessages::AttachmentLimit).to receive(:error_for).and_call_original

    create_message(conversation, content: 'Arquivos', attachments: [file, file('sample.png')])

    expect(RichMessages::AttachmentLimit).not_to have_received(:error_for)
    expect(response.parsed_body['error']).not_to eq(RichMessages::AttachmentLimit::ONE_PER_MESSAGE)
  end

  it 'creates a message with two attachments on a channel that delivers all of them' do
    api_conversation = create(:conversation, inbox: create(:channel_api, account: account).inbox, account: account)

    expect { create_message(api_conversation, content: 'Arquivos', attachments: [file, file('sample.png')]) }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(Message.last.attachments.count).to eq(2)
  end
end
