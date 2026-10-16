require 'rails_helper'

# #1702 — a lista de mensagens diz qual modelo foi usado (só nome e idioma), para a conversa desenhar os botões dele.
RSpec.describe 'Mensagens com o modelo usado', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:caixa) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:conversa) { create(:conversation, account: account, inbox: caixa) }

  before { create(:inbox_member, user: agente, inbox: caixa) }

  it 'traz o nome e o idioma do modelo e nada além disso' do
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Oi',
                     additional_attributes: { 'template_params' => { 'name' => 'boas_vindas', 'language' => 'pt_BR',
                                                                     'processed_params' => { '1' => 'Ana' } } })
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :incoming, content: 'Olá')

    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages", headers: agente.create_new_auth_token, as: :json

    mensagens = response.parsed_body['payload']
    expect(mensagens.find { |m| m['content'] == 'Oi' }['additional_attributes'])
      .to eq('template_params' => { 'name' => 'boas_vindas', 'language' => 'pt_BR' })
    expect(mensagens.find { |m| m['content'] == 'Olá' }).not_to have_key('additional_attributes')
  end
end
