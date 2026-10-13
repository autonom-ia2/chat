require 'rails_helper'

# chat#1473: quem cria a mensagem pela API sabe na hora que errou o formato (422), sem a mensagem ser criada.
describe RichMessages::CreationCheck, type: :request do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:account) { inbox.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:rich_message) { { type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br/x' } }

  def create_message(params)
    post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
         params: params, headers: agent.create_new_auth_token, as: :json
  end

  it 'creates the message when the rich_message is valid' do
    expect { create_message(content: 'Corpo', content_attributes: { rich_message: rich_message }) }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(Message.last.content_attributes['rich_message']).to eq(rich_message.stringify_keys)
  end

  it 'creates a message without rich_message as before, without building a draft' do
    allow(RichMessages).to receive(:format_error).and_call_original

    expect { create_message(content: 'Corpo', content_attributes: { in_reply_to: nil }) }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:success)
    expect(RichMessages).not_to have_received(:format_error)
  end

  button = { type: 'link_button', label: 'Abrir', url: 'https://x.io' }
  select_items = [{ title: 'Sim', value: 'sim' }]
  {
    'an unknown type' => [{ content_attributes: { rich_message: { type: 'carousel' } } }, RichMessages::UNKNOWN_TYPE],
    'an empty rich_message' => [{ content_attributes: { rich_message: {} } }, RichMessages::UNKNOWN_TYPE],
    'a label above the limit' => [{ content_attributes: { rich_message: button.merge(label: 'a' * 21) } },
                                  RichMessages::Types::LinkButton::LABEL_TOO_LONG],
    'an invalid link' => [{ content_attributes: { rich_message: button.merge(url: 'x.io') } }, RichMessages::Types::LinkButton::INVALID_URL],
    'a body above the limit' => [{ content: 'a' * 1025, content_attributes: { rich_message: button } },
                                 RichMessages::Types::LinkButton::BODY_TOO_LONG],
    'rich_message as a JSON string with an unknown type' => [{ content_attributes: { rich_message: { type: 'carousel' } }.to_json },
                                                             RichMessages::UNKNOWN_TYPE],
    'rich_message with a template' => [{ content_attributes: { rich_message: button }, template_params: { name: 'x', language: 'pt_BR' } },
                                       RichMessages::WITH_TEMPLATE],
    'rich_message on a message that is not plain text' => [{ content_type: 'input_select',
                                                             content_attributes: { rich_message: button, items: select_items } },
                                                           RichMessages::NOT_PLAIN_TEXT]
  }.each do |title, (params, error)|
    it "answers 422 with the reason and creates nothing for #{title}" do
      expect { create_message(params.reverse_merge(content: 'Corpo')) }.not_to change(Message, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(error)
    end
  end

  it 'answers 422 for rich_message with an attachment' do
    file = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

    expect do
      post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { content: 'Corpo', content_attributes: { rich_message: rich_message }.to_json, attachments: [file] },
           headers: agent.create_new_auth_token
    end.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(RichMessages::WITH_ATTACHMENT)
  end
end
