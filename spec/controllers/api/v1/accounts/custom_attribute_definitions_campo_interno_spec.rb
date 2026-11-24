require 'rails_helper'

# #3176: a definição de uma chave interna (WAHA, controle da Prospecção) não é apagada nem troca de chave, tipo ou
# modelo, por nenhuma porta. A API (a mesma que o Guia e o MCP usam) devolve 422 com o motivo. Cada exemplo diz a falha
# que pega.
RSpec.describe 'Custom Attribute Definitions API: chave interna', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:interna) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'waha_whatsapp_chat_id',
                                         attribute_display_type: 'text')
  end
  let(:caminho) { "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{interna.id}" }
  let(:recusa) { I18n.t('errors.custom_attribute_definition.campo_interno') }

  # MOTIVO: apagar a definição da WAHA faria a busca dela achar o contato errado; quem tentou fica sabendo por quê.
  it 'apagar devolve 422 com o motivo e a definição fica' do
    delete caminho, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(recusa)
    expect(CustomAttributeDefinition.exists?(interna.id)).to be(true)
  end

  # MOTIVO: o update! vira RecordInvalid, e o handler do app responde 422 com a mensagem, sem gravar nada.
  it 'trocar o tipo ou a chave devolve 422 com o motivo', :aggregate_failures do
    patch caminho, headers: admin.create_new_auth_token,
                   params: { custom_attribute_definition: { attribute_display_type: 'number' } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to eq(recusa)

    patch caminho, headers: admin.create_new_auth_token,
                   params: { custom_attribute_definition: { attribute_key: 'chat_do_whatsapp' } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(interna.reload).to have_attributes(attribute_key: 'waha_whatsapp_chat_id', attribute_display_type: 'text')
  end

  # MOTIVO: o nome continua editável; a trava não pode virar bloqueio total.
  it 'mudar o nome continua valendo' do
    patch caminho, headers: admin.create_new_auth_token,
                   params: { custom_attribute_definition: { attribute_display_name: 'Chat do WhatsApp' } }, as: :json

    expect(response).to have_http_status(:success)
    expect(interna.reload.attribute_display_name).to eq('Chat do WhatsApp')
  end

  # MOTIVO: as outras definições da conta não são afetadas pela trava.
  it 'a definição comum continua sendo apagada' do
    comum = create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'placa')

    delete "/api/v1/accounts/#{account.id}/custom_attribute_definitions/#{comum.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(CustomAttributeDefinition.exists?(comum.id)).to be(false)
  end
end
