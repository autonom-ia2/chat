require 'rails_helper'

# Aviso de clique de uma página (#1011, docs/crm/ponte-lp-atribuicao.md seção 2).
RSpec.describe 'Public tracked link signals', type: :request do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+15551234567', provider: 'whatsapp_cloud', validate_provider_config: false,
                              sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:origin) { 'https://placement.com.br' }
  let!(:tracked_link) do
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'LP Seguro Viagem', code: 'ABC234', usage: 'website',
                              allowed_origins: [origin])
  end
  let(:body) do
    {
      'token' => 'K7P2M9QX',
      'page_url' => 'https://placement.com.br/seguro-viagem?gclid=x#topo',
      'consent' => true,
      'params' => {
        'utm_source' => 'meta', 'utm_medium' => 'paid', 'utm_campaign' => 'Viagem EUA', 'utm_term' => 'Conjunto 60+',
        'utm_content' => 'Video 2', 'utm_id' => '120211', 'fbclid' => 'IwAR123', 'ignored' => 'drop-me'
      },
      'fbc' => 'fb.1.1759650000000.IwAR123',
      'fbp' => 'fb.1.1759650000000.123456789',
      'lead' => { 'fields' => [
        { 'key' => 'destination', 'label' => 'Destino', 'value' => 'América do Norte - EUA' },
        { 'key' => 'ages', 'label' => 'Idades', 'value' => '72' }
      ] }
    }
  end

  def signal(payload = body, code: 'ABC234', headers: { 'Origin' => origin })
    post "/l/#{code}/clicks", params: payload.is_a?(String) ? payload : payload.to_json,
                              headers: { 'CONTENT_TYPE' => 'text/plain;charset=UTF-8', 'HTTP_USER_AGENT' => 'Mozilla/5.0 iPhone' }.merge(headers)
  end

  it 'grava o clique completo, conta o clique e marca o último aviso (204)' do
    freeze_time do
      expect { signal }.to change(Ctwa::TrackedLinkClick, :count).by(1)

      expect(response).to have_http_status(:no_content)
      click = Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX')
      expect(click).to have_attributes(
        account_id: account.id,
        tracked_link_id: tracked_link.id,
        campaign_key: '120211',
        page_url: 'https://placement.com.br/seguro-viagem',
        user_agent: 'Mozilla/5.0 iPhone',
        conversation_id: nil,
        expires_at: 72.hours.from_now
      )
      expect(click.params).to eq(
        'utm_source' => 'meta', 'utm_medium' => 'paid', 'utm_campaign' => 'Viagem EUA', 'utm_term' => 'Conjunto 60+',
        'utm_content' => 'Video 2', 'utm_id' => '120211', 'fbclid' => 'IwAR123'
      )
      expect(click.meta_signals).to eq(
        'fbc' => 'fb.1.1759650000000.IwAR123', 'fbp' => 'fb.1.1759650000000.123456789',
        'client_ip_address' => '127.0.0.1', 'client_user_agent' => 'Mozilla/5.0 iPhone'
      )
      expect(click.lead_data).to eq('fields' => [
                                      { 'key' => 'destination', 'label' => 'Destino', 'value' => 'América do Norte - EUA' },
                                      { 'key' => 'ages', 'label' => 'Idades', 'value' => '72' }
                                    ])
    end
  end

  it 'conta o clique no link e marca o último aviso' do
    freeze_time do
      signal

      expect(tracked_link.reload.clicks_count).to eq(1)
      expect(tracked_link.last_signal_at).to eq(Time.current)
      expect(tracked_link.conversations_count).to eq(0)
    end
  end

  it 'responde com os cabeçalhos CORS da origem autorizada' do
    signal

    expect(response.headers['Access-Control-Allow-Origin']).to eq(origin)
    expect(response.headers['Vary']).to include('Origin')
    expect(response.headers['Access-Control-Allow-Methods']).to eq('POST, OPTIONS')
    expect(response.headers['Access-Control-Allow-Headers']).to eq('Content-Type')
    expect(response.headers['Access-Control-Max-Age']).to eq('600')
    expect(response.headers['Set-Cookie']).to be_blank
  end

  # O preflight do navegador é respondido pelo Rack::Cors (config/initializers/cors.rb), que
  # intercepta todo OPTIONS com Access-Control-Request-Method antes do Rails.
  it 'responde ao preflight do navegador da origem autorizada sem gravar nada' do
    expect do
      process :options, '/l/abc234/clicks', headers: { 'Origin' => origin, 'Access-Control-Request-Method' => 'POST',
                                                       'Access-Control-Request-Headers' => 'content-type' }
    end.not_to change(Ctwa::TrackedLinkClick, :count)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Access-Control-Allow-Origin']).to eq(origin)
    expect(response.headers['Access-Control-Allow-Methods'].upcase.split(', ')).to contain_exactly('POST', 'OPTIONS')
    expect(response.headers['Access-Control-Allow-Headers'].downcase).to eq('content-type')
    expect(response.headers['Access-Control-Max-Age']).to eq('600')
  end

  it 'responde ao OPTIONS simples pelo controller com 204 e CORS' do
    process :options, '/l/ABC234/clicks', headers: { 'Origin' => origin }

    expect(response).to have_http_status(:no_content)
    expect(response.headers['Access-Control-Allow-Origin']).to eq(origin)
    expect(response.headers['Access-Control-Allow-Methods']).to eq('POST, OPTIONS')
  end

  it 'aceita a origem em maiúsculas e com barra final (normalizada)' do
    signal(headers: { 'Origin' => 'HTTPS://Placement.com.br/' })

    expect(response).to have_http_status(:no_content)
    expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').page_url).to eq('https://placement.com.br/seguro-viagem')
  end

  describe 'recusas' do
    it 'recusa origem não autorizada com 403, sem CORS e sem gravar' do
      expect { signal(headers: { 'Origin' => 'https://evil.example' }) }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
      expect(tracked_link.reload.clicks_count).to eq(0)
      expect(tracked_link.last_signal_at).to be_nil
    end

    it 'recusa aviso sem header Origin com 403' do
      expect { signal(headers: {}) }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'não libera preflight do navegador para origem não autorizada nem para link de QR' do
      process :options, '/l/ABC234/clicks', headers: { 'Origin' => 'https://evil.example', 'Access-Control-Request-Method' => 'POST' }
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil

      Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR', code: 'XYZ789', allowed_origins: [origin])
      process :options, '/l/XYZ789/clicks', headers: { 'Origin' => origin, 'Access-Control-Request-Method' => 'POST' }
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'recusa OPTIONS simples de origem não autorizada com 403' do
      process :options, '/l/ABC234/clicks', headers: { 'Origin' => 'https://evil.example' }

      expect(response).to have_http_status(:forbidden)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'não consulta o banco na checagem de origem de outros caminhos' do
      expect(Ctwa::TrackedLink).not_to receive(:find_by)

      expect(Ctwa::TrackedLink.signal_origin_allowed?('/api/v1/accounts/1/conversations', origin)).to be(false)
      expect(Ctwa::TrackedLink.signal_origin_allowed?('/l/ABC234', origin)).to be(false)
      expect(Ctwa::TrackedLink.signal_origin_allowed?('/l/ABC234/clicks/x', origin)).to be(false)
    end

    it 'responde 404 para link de QR (modo direto), mesmo com origem válida' do
      tracked_link.update_columns(usage: 'direct') # rubocop:disable Rails/SkipsModelValidations

      expect { signal }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.headers['Access-Control-Allow-Origin']).to be_nil
    end

    it 'responde 404 para código inexistente' do
      signal(code: 'ZZZ999')

      expect(response).to have_http_status(:not_found)
    end

    it 'recusa token fora do formato com 422 (tamanho, minúscula, letra fora do alfabeto, tipo)' do
      ['K7P2M9Q', 'K7P2M9QXX', 'k7p2m9qx', 'K7P2M9QI', 'K7P2M9Q0', 12_345_678, nil].each do |token|
        signal(body.merge('token' => token))

        expect(response).to have_http_status(:unprocessable_entity), "token #{token.inspect}"
      end
      expect(Ctwa::TrackedLinkClick.count).to eq(0)
      expect(tracked_link.reload.clicks_count).to eq(0)
    end

    it 'recusa corpo que não é JSON com 422' do
      signal('isto não é json')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa corpo acima de 4096 bytes com 413' do
      big = body.merge('padding' => 'x' * 4100)

      expect { signal(big) }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:content_too_large)
    end

    it 'aceita o mesmo corpo enviado como application/json' do
      signal(headers: { 'Origin' => origin, 'CONTENT_TYPE' => 'application/json' })

      expect(response).to have_http_status(:no_content)
      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').campaign_key).to eq('120211')
    end

    it 'não quebra com JSON inválido enviado como application/json' do
      signal('{"token":', headers: { 'Origin' => origin, 'CONTENT_TYPE' => 'application/json' })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Devolve o log do controller e todo JSON que o Rails decodificou durante o aviso.
    def capture_log
      io = StringIO.new
      decoded = []
      allow(ActiveSupport::JSON).to receive(:decode).and_wrap_original do |decode, json, *rest|
        decoded << json.to_s
        decode.call(json, *rest)
      end
      original = ActionController::Base.logger
      ActionController::Base.logger = ActiveSupport::Logger.new(io)
      yield
      [io.string, decoded.dup]
    ensure
      ActionController::Base.logger = original
    end

    it 'recusa JSON grande antes do Rails interpretar, sem levar o formulário ao log' do
      big = body.merge('lead' => { 'fields' => [{ 'key' => 'nome', 'label' => 'Nome', 'value' => 'Maria Secreta' }] },
                       'padding' => 'x' * 5000)

      # O Rails nunca interpreta o corpo: quem lê é o controller, com o limite.
      log, decoded = capture_log { signal(big, headers: { 'Origin' => origin, 'CONTENT_TYPE' => 'application/json' }) }

      expect(response).to have_http_status(:content_too_large)
      expect(Ctwa::TrackedLinkClick.count).to eq(0)
      expect(decoded).to(be_none { |json| json.include?('Maria Secreta') })
      expect(log).not_to include('Maria Secreta')
    end

    it 'não leva formulário, fbc, fbp nem página ao log quando o corpo vem como application/json' do
      payload = body.merge('lead' => { 'fields' => [{ 'key' => 'nome', 'label' => 'Nome', 'value' => 'Maria Secreta' }] })

      log, decoded = capture_log { signal(payload, headers: { 'Origin' => origin, 'CONTENT_TYPE' => 'application/json' }) }

      expect(response).to have_http_status(:no_content)
      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').lead_data['fields'].sole['value']).to eq('Maria Secreta')
      expect(log).to include('Public::TrackedLinkSignalsController#create')
      # Só o corpo do aviso traz o token (as colunas jsonb lidas na gravação não).
      expect(decoded).to(be_none { |json| json.include?('K7P2M9QX') })
      expect(log).not_to include('Maria Secreta', 'IwAR123', '123456789', 'seguro-viagem')
    end

    it 'recusa com 429 quando o link já recebeu o teto diário de avisos' do
      stub_const('Public::TrackedLinkSignalsController::DAILY_LIMIT_PER_LINK', 2)
      2.times { |index| create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: "AAAA222#{index + 2}") }

      expect { signal }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:too_many_requests)
      expect(tracked_link.reload.clicks_count).to eq(0)
    end
  end

  describe 'campos longos (não perdem o clique)' do
    it 'grava page_url de até 512 caracteres' do
      path = "/#{'p' * 400}"
      signal(body.merge('page_url' => "https://placement.com.br#{path}"))

      expect(response).to have_http_status(:no_content)
      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').page_url).to eq("https://placement.com.br#{path}")
    end

    it 'resume utm_id longo ou que não é só dígitos, sem vírgula na chave da campanha' do
      long_id = "camp,#{'a' * 300}"
      signal(body.merge('params' => { 'utm_id' => long_id, 'utm_campaign' => 'Viagem' }))

      expect(response).to have_http_status(:no_content)
      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').campaign_key).to eq("i:#{Digest::SHA1.hexdigest(long_id)[0, 10]}")
    end
  end

  it 'enfileira a busca da mensagem que pode ter chegado antes do aviso' do
    expect { signal }.to have_enqueued_job(Ctwa::LateClickReconcileJob).with(kind_of(Integer))
  end

  describe 'token repetido' do
    it 'é idempotente no mesmo link: 204 e nada muda (nem contador, nem dados)' do
      signal
      first_signal_at = tracked_link.reload.last_signal_at

      travel 1.minute do
        expect { signal(body.merge('params' => { 'utm_campaign' => 'Outra' })) }.not_to change(Ctwa::TrackedLinkClick, :count)
      end

      expect(response).to have_http_status(:no_content)
      expect(tracked_link.reload.clicks_count).to eq(1)
      expect(tracked_link.last_signal_at).to eq(first_signal_at)
      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').params['utm_campaign']).to eq('Viagem EUA')
    end

    it 'dá 409 quando o token já pertence a outro link' do
      other_link = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR Loja', code: 'XYZ789')
      create(:ctwa_tracked_link_click, account: account, tracked_link: other_link, token: 'K7P2M9QX')

      expect { signal }.not_to change(Ctwa::TrackedLinkClick, :count)

      expect(response).to have_http_status(:conflict)
      expect(tracked_link.reload.clicks_count).to eq(0)
    end
  end

  describe 'consentimento e limpeza' do
    it 'sem consentimento não grava fbc/fbp/IP/user agent, mas grava UTMs e formulário' do
      signal(body.merge('consent' => false))

      click = Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX')
      expect(response).to have_http_status(:no_content)
      expect(click.meta_signals).to eq({})
      expect(click.user_agent).to be_nil
      expect(click.params).to include('utm_campaign' => 'Viagem EUA', 'utm_id' => '120211', 'fbclid' => 'IwAR123')
      expect(click.lead_data['fields'].size).to eq(2)
    end

    it 'trata consentimento que não é true literal como ausente' do
      signal(body.merge('consent' => 'true'))

      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').meta_signals).to eq({})
    end

    it 'descarta fbc/fbp inválidos em silêncio e grava o clique' do
      invalid = [
        'fb.1.17596500x0000.IwAR', # timestamp com letra
        'fx.1.1759650000000.IwAR', # prefixo errado
        'fb.1.1759650000000', # três partes
        "fb.1.1759650000000.#{'a' * 300}" # longo demais
      ]
      invalid.each_with_index do |cookie, index|
        token = "K7P2M9Q#{'ABCD'[index]}"
        signal(body.merge('token' => token, 'fbc' => cookie, 'fbp' => cookie))

        click = Ctwa::TrackedLinkClick.find_by!(token: token)
        expect(click.meta_signals.keys).to contain_exactly('client_ip_address', 'client_user_agent'), cookie
      end
    end

    it 'descarta page_url de outra origem' do
      signal(body.merge('page_url' => 'https://evil.example/seguro-viagem'))

      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').page_url).to be_nil
    end

    it 'descarta page_url com usuário embutido ou que não é URL' do
      signal(body.merge('token' => 'K7P2M9QA', 'page_url' => 'https://user:pass@placement.com.br/x'))
      signal(body.merge('token' => 'K7P2M9QB', 'page_url' => 'nada'))

      expect(Ctwa::TrackedLinkClick.where(token: %w[K7P2M9QA K7P2M9QB]).pluck(:page_url)).to eq([nil, nil])
    end

    it 'limita parâmetros a texto de até 512 caracteres e só às chaves conhecidas' do
      signal(body.merge('params' => { 'utm_campaign' => 'a' * 600, 'utm_source' => ['meta'], 'utm_medium' => { 'x' => 1 }, 'evil' => 'x' }))

      click = Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX')
      expect(click.params).to eq('utm_campaign' => 'a' * 512)
      expect(click.campaign_key).to eq("c:#{Digest::SHA1.hexdigest('a' * 512)[0, 10]}")
    end

    it 'usa `none` como campanha quando o clique não traz campanha' do
      signal(body.merge('params' => { 'fbclid' => 'IwAR123' }))

      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').campaign_key).to eq('none')
    end

    it 'descarta itens inválidos do formulário e guarda no máximo 12' do
      fields = [
        { 'key' => 'a' * 41, 'label' => 'Longa', 'value' => 'x' },
        { 'key' => 'ok', 'label' => 'b' * 61, 'value' => 'x' },
        { 'key' => 'ok', 'label' => 'Valor', 'value' => 'c' * 201 },
        { 'key' => 'ok', 'label' => 'Num', 'value' => 72 },
        { 'key' => '', 'label' => 'Sem chave', 'value' => 'x' },
        'texto solto'
      ] + Array.new(14) { |index| { 'key' => "k#{index}", 'label' => "L#{index}", 'value' => "v#{index}" } }

      signal(body.merge('lead' => { 'fields' => fields }))

      stored = Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').lead_data['fields']
      expect(stored.size).to eq(12)
      expect(stored.first).to eq('key' => 'k0', 'label' => 'L0', 'value' => 'v0')
      expect(stored.pluck('key')).to eq((0..11).map { |index| "k#{index}" })
    end

    it 'grava formulário vazio como {} quando não vem lead' do
      signal(body.except('lead'))

      expect(Ctwa::TrackedLinkClick.find_by!(token: 'K7P2M9QX').lead_data).to eq({})
    end
  end

  describe 'Rack::Attack' do
    def throttle_key(method, path)
      env = Rack::MockRequest.env_for(path, method: method).merge('REMOTE_ADDR' => '10.0.0.9')
      Rack::Attack.throttles.fetch('public_tracked_link_signals/ip').block.call(Rack::Attack::Request.new(env))
    end

    it 'limita avisos por IP a 30 por minuto, só em POST /l/' do
      throttle = Rack::Attack.throttles.fetch('public_tracked_link_signals/ip')

      expect(throttle.limit).to eq(30)
      expect(throttle.period).to eq(60)
      expect(throttle_key('POST', '/l/ABC234/clicks')).to eq('10.0.0.9')
      expect(throttle_key('GET', '/l/ABC234')).to be_nil
      expect(throttle_key('POST', '/api/v1/x')).to be_nil
    end

    it 'limita avisos por link (código), independente do IP' do
      throttle = Rack::Attack.throttles.fetch('public_tracked_link_signals/code')
      key = lambda do |method, path|
        throttle.block.call(Rack::Attack::Request.new(Rack::MockRequest.env_for(path, method: method)))
      end

      expect(throttle.limit).to eq(120)
      expect(key.call('POST', '/l/abc234/clicks')).to eq('ABC234')
      expect(key.call('GET', '/l/ABC234/clicks')).to be_nil
      expect(key.call('POST', '/l/ABC234')).to be_nil
      expect(key.call('POST', '/l/ABC234/clicks/x')).to be_nil
    end
  end
end
