require 'rails_helper'

# #2113 — o atendente reage a uma mensagem do Instagram pelo painel. A caixa Instagram usa a chave `conversa_instagram`;
# as outras continuam na chave da pele (`conversa_cara_do_canal`). Mesmo gate de permissão do WhatsApp.
RSpec.describe 'Reação do atendente no Instagram', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:canal) { create(:channel_instagram, account: account, instagram_id: 'ig-business-1') }
  let(:caixa) { canal.inbox }
  let(:contato) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: 'ig-customer-1') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: contact_inbox) }
  let!(:mensagem) do
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: 'Oi',
                     source_id: 'mid.DOCLIENTE')
  end
  let(:url_da_meta) { 'https://graph.instagram.com/v22.0/ig-business-1/messages' }

  before do
    account.enable_features!('conversa_instagram')
    account.save!
    create(:inbox_member, user: agente, inbox: caixa)
    stub_request(:post, url_da_meta).with(query: hash_including({}))
                                    .to_return(status: 200, body: { recipient_id: 'ig-customer-1' }.to_json,
                                               headers: { 'Content-Type' => 'application/json' })
  end

  def reagir(emoji, usuario: agente)
    post "/api/v1/accounts/#{account.id}/conversa_canal/reacoes",
         params: { conversation_id: conversa.display_id, message_id: mensagem.id, emoji: emoji },
         headers: usuario.create_new_auth_token, as: :json
  end

  it 'reage com a chave conversa_instagram, sem precisar da chave da pele' do
    reagir('❤️')

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['reactions'].pluck('emoji')).to eq(['❤️'])
    expect(a_request(:post, url_da_meta).with(query: hash_including({}))).to have_been_made
  end

  it 'sem a chave conversa_instagram: 404, mesmo com a chave da pele ligada' do
    account.disable_features!('conversa_instagram')
    account.enable_features!('conversa_cara_do_canal')
    account.save!

    reagir('❤️')

    expect(response).to have_http_status(:not_found)
    expect(a_request(:post, url_da_meta).with(query: hash_including({}))).not_to have_been_made
  end

  it 'atendente sem acesso à caixa não reage' do
    reagir('❤️', usuario: create(:user, account: account, role: :agent))

    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:post, url_da_meta).with(query: hash_including({}))).not_to have_been_made
  end

  context 'with a WhatsApp conversation' do
    let(:whatsapp) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    end
    let(:conversa_do_whatsapp) { create(:conversation, account: account, inbox: whatsapp.inbox) }
    let(:mensagem_do_whatsapp) do
      create(:message, account: account, inbox: whatsapp.inbox, conversation: conversa_do_whatsapp, message_type: :incoming,
                       source_id: 'wamid.X')
    end

    it 'a chave conversa_instagram não libera a reação do WhatsApp' do
      post "/api/v1/accounts/#{account.id}/conversa_canal/reacoes",
           params: { conversation_id: conversa_do_whatsapp.display_id, message_id: mensagem_do_whatsapp.id, emoji: '👍' },
           headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
