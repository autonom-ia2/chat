require 'rails_helper'

# Porte de registry/hydrator.test.ts do Orth. O transporte é dublado e o relógio é de mentira: o tempo só anda quando o
# dublê manda, e o sleep do Retry-After é registrado em vez de dormir.
RSpec.describe Autonomia::Prospecting::Research::Registry::Hydrator do
  let(:registry) { Autonomia::Prospecting::Research::Registry }
  let(:cnpj) { '11222333000181' }
  let(:now) { [0.0] }
  let(:sleeps) { [] }
  let(:requests) { [] }

  def fixture(name)
    JSON.parse(Rails.root.join('spec/fixtures/prospecting/registry', "#{name}.json").read)
  end

  def open_payload(cnpj) = fixture('opencnpj-success').merge('cnpj' => cnpj)
  def brasil_payload(cnpj) = fixture('brasilapi-success').merge('cnpj' => cnpj)

  def response(status, body = {}, headers = {})
    registry::HttpTransport::Response.new(status: status, body: body, headers: headers)
  end

  def provider_of(url)
    registry::PROVIDERS.find { |provider| URI(url).host == provider.host }.name
  end

  # O bloco recebe (provider, cnpj, timeout) e devolve a resposta ou levanta.
  def transport(&block)
    test = self
    handler = block
    Class.new do
      define_method(:request) do |url:, timeout:|
        provider = test.provider_of(url)
        test.requests << { provider: provider, url: url, timeout: timeout }
        handler.call(provider, url.split('/').last, timeout)
      end
    end.new
  end

  def hydrator(transport)
    described_class.new(transport: transport, clock: -> { now[0] }, sleeper: ->(seconds) { sleeps << seconds })
  end

  def hydrate_one(transport)
    hydrator(transport).hydrate([cnpj]).first
  end

  it 'segue a ordem pública congelada e os endereços documentados, com 5 s por tentativa' do
    result = hydrate_one(transport do |provider, requested|
      if provider == 'CNPJá'
        response(200, 'taxId' => requested, 'status' => { 'text' => 'Ativa' }, 'address' => { 'city' => 'SAO PAULO', 'state' => 'SP' },
                      'company' => { 'name' => 'ULTIMO PROVIDER LTDA', 'members' => [] })
      else
        response(404)
      end
    end)

    expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ BrasilAPI CNPJ.ws CNPJá])
    expect(requests.pluck(:url)).to eq(
      [
        'https://api.opencnpj.org/11222333000181', 'https://brasilapi.com.br/api/cnpj/v1/11222333000181',
        'https://publica.cnpj.ws/cnpj/11222333000181', 'https://open.cnpja.com/office/11222333000181'
      ]
    )
    expect(requests.pluck(:timeout).uniq).to eq([5])
    expect(result.company.provider).to eq('CNPJá')
    expect(result.result).to eq(result.company)
  end

  it 'passa adiante depois de corpo semanticamente inválido e não audita corpo nem dado pessoal' do
    secret = 'CPF 000.000.000-00 PESSOA PRIVADA'
    result = hydrate_one(transport do |provider, requested|
      provider == 'OpenCNPJ' ? response(200, open_payload('22333444000155').merge('segredo' => secret)) : response(200, brasil_payload(requested))
    end)

    expect(result.attempts).to match(
      [
        hash_including('provider' => 'OpenCNPJ', 'outcome' => 'semantic_invalid', 'reason' => 'cnpj_mismatch'),
        hash_including('provider' => 'BrasilAPI', 'outcome' => 'success')
      ]
    )
    expect(result.attempts.to_json).not_to include(secret, 'segredo', 'body', 'raw')
  end

  {
    'erro de rede' => [-> { raise Errno::ECONNREFUSED, 'detalhe privado' }, 'network_error'],
    'HTTP 404' => [-> { response(404) }, 'not_found'],
    'HTTP 429 sem Retry-After' => [-> { response(429) }, 'http_error'],
    'HTTP 500 sem Retry-After' => [-> { response(500) }, 'http_error'],
    'redirecionamento' => [-> { response(301) }, 'redirect_refused'],
    'corpo acima de 1 MB' => [-> { raise registry::HttpTransport::BodyTooLarge }, 'body_too_large'],
    'timeout' => [-> { raise Net::ReadTimeout }, 'timeout']
  }.each do |label, (first, outcome)|
    it "não repete #{label} e cai para a próxima fonte" do
      result = hydrate_one(transport do |provider, requested|
        if provider == 'OpenCNPJ'
          instance_exec(&first)
        else
          response(200, brasil_payload(requested))
        end
      end)

      expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ BrasilAPI])
      expect(result.attempts.first).to include('provider' => 'OpenCNPJ', 'outcome' => outcome)
      expect(result.attempts.size).to eq(2)
      expect(result.company.provider).to eq('BrasilAPI')
    end
  end

  [429, 503].each do |status|
    it "repete o HTTP #{status} uma vez só quando o Retry-After é de até 1 s" do
      calls = 0
      result = hydrate_one(transport do |_provider, requested|
        calls += 1
        calls == 1 ? response(status, {}, { 'retry-after' => '1' }) : response(200, open_payload(requested))
      end)

      expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ OpenCNPJ])
      expect(sleeps).to eq([1.0])
      expect(result.attempts).to match(
        [
          hash_including('provider' => 'OpenCNPJ', 'outcome' => 'http_error', 'http_status' => status, 'retry_after_ms' => 1000),
          hash_including('provider' => 'OpenCNPJ', 'outcome' => 'success', 'retry_of' => 0)
        ]
      )
    end
  end

  it 'não repete com Retry-After acima de 1 s' do
    hydrate_one(transport do |provider, requested|
      provider == 'OpenCNPJ' ? response(429, {}, { 'retry-after' => '2' }) : response(200, brasil_payload(requested).merge('qsa' => []))
    end)

    expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ BrasilAPI])
    expect(sleeps).to eq([])
  end

  it 'repete no máximo uma vez a mesma fonte' do
    result = hydrate_one(transport do |provider, requested|
      provider == 'OpenCNPJ' ? response(503, {}, { 'retry-after' => '0' }) : response(200, brasil_payload(requested))
    end)

    expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ OpenCNPJ BrasilAPI])
    expect(result.attempts[1]).to include('retry_of' => 0)
    expect(result.attempts[2]).not_to have_key('retry_of')
  end

  it 'não repete quando o Retry-After mais uma tentativa inteira passam do prazo do candidato' do
    result = hydrate_one(transport do |provider, requested|
      case provider
      when 'OpenCNPJ' then now[0] += 5
                           raise Net::ReadTimeout
      when 'BrasilAPI' then now[0] += 4.5
                            response(503, {}, { 'retry-after' => '1' })
      else response(200, fixture('cnpjws-success').tap { |p| p['estabelecimento']['cnpj'] = requested })
      end
    end)

    expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ BrasilAPI CNPJ.ws])
    expect(result.attempts[1]).to include('retry_after_ms' => 1000)
    expect(result.attempts[2]).not_to have_key('retry_of')
    expect(result.company.provider).to eq('CNPJ.ws')
  end

  it 'para no prazo de 15 s do candidato, sem repetir timeout' do
    result = hydrate_one(transport do
      now[0] += 5
      raise Net::ReadTimeout
    end)

    expect(requests.pluck(:provider)).to eq(%w[OpenCNPJ BrasilAPI CNPJ.ws])
    expect(result.attempts.pluck('outcome')).to eq(%w[timeout timeout timeout])
    expect(result.failure_reason).to eq(:deadline_exceeded)
    expect(result.result).to be_failed
    expect(result.result.reason).to eq(:deadline_exceeded)
  end

  it 'devolve providers_exhausted quando todas as fontes falham dentro do prazo' do
    result = hydrate_one(transport { response(404) })

    expect(result.failure_reason).to eq(:providers_exhausted)
    expect(result.result).to have_attributes(cnpj: cnpj, reason: :providers_exhausted, attempts: result.attempts)
  end

  it 'pesquisa até três CNPJs ao mesmo tempo e recusa mais de três' do
    queue = Queue.new
    peak = Mutex.new
    active = [0, 0]
    slow = transport do |_provider, requested|
      peak.synchronize do
        active[0] += 1
        active[1] = [active[1], active[0]].max
      end
      queue.pop
      peak.synchronize { active[0] -= 1 }
      response(200, open_payload(requested))
    end
    pending = Thread.new { hydrator(slow).hydrate(%w[11222333000181 11444777000161 19131243000197]) }
    sleep 0.01 until requests.size == 3
    3.times { queue << :go }
    results = pending.value

    expect(active[1]).to eq(3)
    expect(results.map { |item| item.company.cnpj }).to eq(%w[11222333000181 11444777000161 19131243000197])
    expect { hydrator(slow).hydrate(%w[11222333000181 11444777000161 19131243000197 27865757000102]) }
      .to raise_error(ArgumentError, 'at most 3 CNPJs')
  end

  it 'recusa CNPJ que não tem 14 dígitos' do
    expect { hydrator(transport { response(404) }).hydrate(['123']) }.to raise_error(ArgumentError, 'requires 14-digit CNPJs')
  end

  it 'não guarda a mensagem do erro de rede no envelope de auditoria' do
    secret = 'token=secret CPF=000.000.000-00'
    result = hydrate_one(transport { raise StandardError, secret })

    expect(result.attempts.to_json).not_to include(secret, 'token=')
    expect(result.attempts.pluck('outcome').uniq).to eq(['network_error'])
  end
end
