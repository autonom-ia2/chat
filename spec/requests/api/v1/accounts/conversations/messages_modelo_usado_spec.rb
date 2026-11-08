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

  # #1717: a foto do que foi enviado sai junto com o nome e o idioma; processed_params (cupom, valores) nunca.
  it 'traz a foto do envio (enviado) e nunca o processed_params' do
    enviado = { 'versao' => 1, 'oferta' => { 'expira_em' => 1_760_659_200 },
                'botoes' => [{ 'tipo' => 'copy_code', 'texto' => 'Copiar código' },
                             { 'tipo' => 'url', 'texto' => 'Ver proposta', 'url' => 'https://loja.com.br/b/AB3K' }] }
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Oferta',
                     additional_attributes: { 'template_params' => { 'name' => 'oferta', 'language' => 'pt_BR', 'enviado' => enviado,
                                                                     'processed_params' => { 'buttons' => [{ 'parameter' => 'SEGREDO9' }] } } })

    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages", headers: agente.create_new_auth_token, as: :json

    mensagem = response.parsed_body['payload'].find { |m| m['content'] == 'Oferta' }
    expect(mensagem['additional_attributes']).to eq('template_params' => { 'name' => 'oferta', 'language' => 'pt_BR', 'enviado' => enviado })
    expect(response.body).not_to include('processed_params', 'SEGREDO9')
  end

  it 'na mensagem da campanha traz a foto gravada em campaign_template_enviado' do
    enviado = { 'versao' => 1, 'produto' => { 'retailer_id' => 'SKU1' } }
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Vitrine',
                     additional_attributes: { 'campaign_id' => 7, 'campaign_template_name' => 'vitrine', 'campaign_template_enviado' => enviado })

    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages", headers: agente.create_new_auth_token, as: :json

    mensagem = response.parsed_body['payload'].find { |m| m['content'] == 'Vitrine' }
    expect(mensagem['additional_attributes'])
      .to eq('campaign_id' => 7, 'campaign_template_name' => 'vitrine', 'template_params' => { 'name' => 'vitrine', 'enviado' => enviado })
  end

  it 'na mensagem da jornada de campanha usa o nome gravado pela campanha' do
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Promo',
                     additional_attributes: { 'campaign_id' => 7, 'campaign_template_name' => 'promo_outubro' })
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Livre',
                     additional_attributes: { 'campaign_id' => 7, 'campaign_free_text' => true })

    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages", headers: agente.create_new_auth_token, as: :json

    mensagens = response.parsed_body['payload']
    expect(mensagens.find { |m| m['content'] == 'Promo' }['additional_attributes'])
      .to eq('campaign_id' => 7, 'campaign_template_name' => 'promo_outubro', 'template_params' => { 'name' => 'promo_outubro' })
    expect(mensagens.find { |m| m['content'] == 'Livre' }['additional_attributes']).to eq('campaign_id' => 7)
  end

  # #2049: o rótulo com o nome da campanha lê o id da campanha; sem ele na lista, o rótulo sumia ao recarregar.
  it 'traz de qual campanha veio, também na campanha da API do WhatsApp, e só isso dos atributos da campanha' do
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Disparo',
                     additional_attributes: { 'whatsapp_api_campaign_id' => 12, 'whatsapp_api_campaign_recipient_id' => 345 })
    create(:message, conversation: conversa, account: account, inbox: caixa, message_type: :outgoing, content: 'Comum',
                     additional_attributes: { 'campaign_id' => nil, 'outro' => 'x' })

    get "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages", headers: agente.create_new_auth_token, as: :json

    mensagens = response.parsed_body['payload']
    expect(mensagens.find { |m| m['content'] == 'Disparo' }['additional_attributes']).to eq('whatsapp_api_campaign_id' => 12)
    expect(mensagens.find { |m| m['content'] == 'Comum' }).not_to have_key('additional_attributes')
  end
end
