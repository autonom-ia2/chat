require 'rails_helper'

# #1702 — leituras do "+" da conversa com a cara do canal: busca de endereço (Google) e formulários aprovados (Meta).
RSpec.describe 'Conversa com a cara do canal', type: :request do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  # A fábrica troca o provider_config no before(:create); a conta do WhatsApp e a chave daqui entram depois.
  let(:canal) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |c|
      c.provider_config = { 'api_key' => 'chave-da-caixa', 'phone_number_id' => '1', 'business_account_id' => '777' }
      c.save!(validate: false)
    end
  end
  let(:caixa) { canal.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/conversa_canal" }

  before do
    account.enable_features!('conversa_cara_do_canal')
    account.save!
    create(:inbox_member, user: agente, inbox: caixa)
  end

  def ler(caminho, **params)
    get "#{base}/#{caminho}", params: params, headers: agente.create_new_auth_token, as: :json
  end

  it 'responde 404 com a chave da conta desligada' do
    account.disable_features!('conversa_cara_do_canal')
    account.save!

    ler('lugares', termo: 'Av Paulista')

    expect(response).to have_http_status(:not_found)
  end

  describe 'lugares' do
    around { |example| with_modified_env(GOOGLE_PLACES_API_KEY: 'chave-google') { example.run } }

    it 'sugere endereços sem o filtro de cidade da Prospecção' do
      pedido = stub_request(:post, 'https://places.googleapis.com/v1/places:autocomplete')
               .with { |req| !JSON.parse(req.body).key?('includedPrimaryTypes') }
               .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                          body: { suggestions: [{ placePrediction: { placeId: 'p1', text: { text: 'Av. Paulista, 1000' } } }] }.to_json)

      ler('lugares', termo: 'Av Paulista')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([{ 'text' => 'Av. Paulista, 1000', 'place_id' => 'p1' }])
      expect(pedido).to have_been_requested
    end

    it 'não chama o Google com menos de 3 letras' do
      ler('lugares', termo: 'Av')

      expect(response.parsed_body['payload']).to eq([])
    end

    it 'devolve nome, endereço e o ponto do lugar escolhido' do
      stub_request(:get, %r{places.googleapis.com/v1/places/p1})
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { id: 'p1', displayName: { text: 'Loja' }, formattedAddress: 'Av. Paulista, 1000',
                           location: { latitude: -23.56, longitude: -46.65 } }.to_json)

      ler('lugares/p1')

      expect(response.parsed_body).to include('nome' => 'Loja', 'endereco' => 'Av. Paulista, 1000', 'latitude' => -23.56,
                                              'longitude' => -46.65)
    end

    # Barra codificada (%2F) nem chega aqui: o roteador não acha a rota (404). O que passa pela rota com letra fora
    # do formato do Google é recusado antes de montar a URL.
    it 'recusa id de lugar que não é do Google, sem chamar o Google' do
      ler('lugares/places:searchText')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(a_request(:any, /places.googleapis.com/)).not_to have_been_made
    end

    it 'leva a sessão do Google nas sugestões' do
      pedido = stub_request(:post, 'https://places.googleapis.com/v1/places:autocomplete')
               .with { |req| JSON.parse(req.body)['sessionToken'] == 'sessao-1' }
               .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { suggestions: [] }.to_json)

      ler('lugares', termo: 'Av Paulista', sessao: 'sessao-1')

      expect(pedido).to have_been_requested
    end

    it 'erro do Google vira frase em português, sem a chave' do
      stub_request(:post, 'https://places.googleapis.com/v1/places:autocomplete').to_return(status: 500, body: '{}')

      ler('lugares', termo: 'Av Paulista')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
      expect(response.body).not_to include('chave-google')
    end
  end

  it 'sem a chave do Google na plataforma, explica e não chama o Google' do
    with_modified_env(GOOGLE_PLACES_API_KEY: '') { ler('lugares', termo: 'Av Paulista') }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.lugares.sem_chave'))
  end

  describe 'formularios' do
    let(:graph) { 'https://graph.facebook.com/v22.0' }

    it 'lista só os publicados da conta do WhatsApp da caixa' do
      stub_request(:get, "#{graph}/777/flows").with(query: hash_including({}), headers: { 'Authorization' => 'Bearer chave-da-caixa' })
                                              .to_return(status: 200, body: { data: [
                                                { id: '11', name: 'Cadastro', status: 'PUBLISHED', categories: ['SIGN_UP'] },
                                                { id: '12', name: 'Rascunho', status: 'DRAFT', categories: [] }
                                              ] }.to_json)

      ler('formularios', inbox_id: caixa.id)

      expect(response.parsed_body['payload']).to eq([{ 'id' => '11', 'nome' => 'Cadastro', 'categorias' => ['SIGN_UP'] }])
    end

    it 'acha a primeira tela no JSON publicado' do
      stub_request(:get, "#{graph}/11/assets")
        .to_return(status: 200, body: { data: [{ asset_type: 'FLOW_JSON', download_url: 'https://lookaside.fbsbx.com/flow.json' }] }.to_json)
      stub_request(:get, 'https://lookaside.fbsbx.com/flow.json')
        .to_return(status: 200, body: { screens: [{ id: 'BOAS_VINDAS' }, { id: 'FIM' }] }.to_json)

      stub_request(:get, "#{graph}/777/flows").with(query: hash_including({}))
                                              .to_return(status: 200, body: { data: [{ id: '11', name: 'Cadastro', status: 'PUBLISHED' }] }.to_json)

      ler('formularios/11/primeira_tela', inbox_id: caixa.id)

      expect(response.parsed_body).to eq('tela' => 'BOAS_VINDAS')
    end

    def publicados(*ids)
      dados = ids.map { |id| { id: id, name: "F#{id}", status: 'PUBLISHED' } }
      stub_request(:get, "#{graph}/777/flows").with(query: hash_including({}))
                                              .to_return(status: 200, body: { data: dados }.to_json)
    end

    it 'não monta URL da Graph com id que não é de formulário publicado da caixa' do
      publicados('11')

      ler('formularios/me/primeira_tela', inbox_id: caixa.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.nao_encontrado'))
      expect(a_request(:get, "#{graph}/me/assets")).not_to have_been_made
    end

    it 'só baixa o JSON de endereço https da Meta' do
      publicados('11')
      stub_request(:get, "#{graph}/11/assets")
        .to_return(status: 200, body: { data: [{ asset_type: 'FLOW_JSON', download_url: 'https://interno.exemplo/segredo' }] }.to_json)

      ler('formularios/11/primeira_tela', inbox_id: caixa.id)

      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.sem_json'))
      expect(a_request(:get, 'https://interno.exemplo/segredo')).not_to have_been_made
    end

    it 'falha de rede no download vira frase, não 500' do
      publicados('11')
      stub_request(:get, "#{graph}/11/assets")
        .to_return(status: 200, body: { data: [{ asset_type: 'FLOW_JSON', download_url: 'https://cdn.fbsbx.com/flow.json' }] }.to_json)
      stub_request(:get, 'https://cdn.fbsbx.com/flow.json').to_timeout

      ler('formularios/11/primeira_tela', inbox_id: caixa.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.meta_fora'))
    end

    it 'JSON sem telas e resposta fora do formato viram frase, não 500' do
      publicados('11')
      stub_request(:get, "#{graph}/11/assets").to_return(status: 200, body: '[]')

      ler('formularios/11/primeira_tela', inbox_id: caixa.id)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'Meta sem permissão explica com frase própria' do
      stub_request(:get, "#{graph}/777/flows").with(query: hash_including({}))
                                              .to_return(status: 403, body: { error: { code: 200, message: 'Permissions error' } }.to_json)

      ler('formularios', inbox_id: caixa.id)

      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.sem_permissao'))
    end

    it 'caixa sem conta do WhatsApp Business explica sem chamar a Meta' do
      canal.provider_config = { 'api_key' => 'chave-da-caixa' }
      canal.save!(validate: false)

      ler('formularios', inbox_id: caixa.id)

      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.sem_conta'))
    end

    it 'caixa de outra conta: 404' do
      outra = create(:channel_whatsapp, account: create(:account), validate_provider_config: false, sync_templates: false).inbox

      ler('formularios', inbox_id: outra.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'recusa caixa que não é o WhatsApp oficial' do
      waha = create(:inbox, account: account, channel: create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }))
      create(:inbox_member, user: agente, inbox: waha)

      ler('formularios', inbox_id: waha.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.formularios.so_oficial'))
    end

    it 'não deixa ler caixa de que o atendente não participa' do
      outra = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox

      ler('formularios', inbox_id: outra.id)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
