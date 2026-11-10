# #2858 (F0): as fontes do catálogo das ferramentas prontas, nos specs. O DNS dos hosts do catálogo é dublado com IPs
# públicos de documentação (o `SafeFetch` recusa IP privado) e cada resposta vem do WebMock.
module FerramentasProntasHelper
  HOSTS_DAS_PRONTAS = {
    'brasilapi.com.br' => '93.184.216.40', 'viacep.com.br' => '93.184.216.41', 'minhareceita.org' => '93.184.216.42',
    'api.opencnpj.org' => '93.184.216.43', 'parallelum.com.br' => '93.184.216.44', 'fora.exemplo.test' => '93.184.216.45'
  }.freeze

  def resolver_hosts_das_prontas
    allow(Resolv).to receive(:getaddresses).and_call_original
    HOSTS_DAS_PRONTAS.each { |host, ip| allow(Resolv).to receive(:getaddresses).with(host).and_return([ip]) }
  end

  def fonte_responde(url, corpo, status: 200, tipo: 'application/json; charset=utf-8')
    stub_request(:get, url).to_return(status: status, body: corpo.is_a?(String) ? corpo : corpo.to_json,
                                      headers: { 'Content-Type' => tipo })
  end

  def fonte_fora(url, status: 500)
    stub_request(:get, url).to_return(status: status, body: '{"message":"fora"}', headers: { 'Content-Type' => 'application/json' })
  end

  def fonte_lenta(url)
    stub_request(:get, url).to_timeout
  end

  def ligar_prontas(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG)
  end

  def incluir_pronta(fonte, conta:, agente:, usar_quando: 'o cliente informar o dado')
    Autonomia::FerramentasProntas::Incluir.new(account: conta, agent: agente, fonte: fonte, usar_quando: usar_quando).call.ferramenta
  end

  def executar_pronta(ferramenta, argumentos)
    JSON.parse(Autonomia::FerramentasProntas::Execucao.new(tool: ferramenta, params: argumentos).call)
  end

  def cache_em_memoria
    loja = ActiveSupport::Cache::MemoryStore.new
    allow(Rails).to receive(:cache).and_return(loja)
    loja
  end
end

RSpec.configure do |config|
  config.include FerramentasProntasHelper
end
