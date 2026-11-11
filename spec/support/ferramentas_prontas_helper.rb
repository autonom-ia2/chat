# #2858 (F0): as fontes do catálogo das ferramentas prontas, nos specs. O DNS dos hosts do catálogo é dublado com IPs
# públicos de documentação (o `SafeFetch` recusa IP privado) e cada resposta vem do WebMock.
module FerramentasProntasHelper
  HOSTS_DAS_PRONTAS = {
    'brasilapi.com.br' => '93.184.216.40', 'viacep.com.br' => '93.184.216.41', 'minhareceita.org' => '93.184.216.42',
    'api.opencnpj.org' => '93.184.216.43', 'parallelum.com.br' => '93.184.216.44', 'fora.exemplo.test' => '93.184.216.45',
    'date.nager.at' => '93.184.216.46', 'api.bcb.gov.br' => '93.184.216.47', 'olinda.bcb.gov.br' => '93.184.216.48',
    'servicodados.ibge.gov.br' => '93.184.216.49', 'photon.komoot.io' => '93.184.216.50',
    'www.bcb.gov.br' => '93.184.216.52',
    # F4
    'apidadosabertos.saude.gov.br' => '93.184.216.53', 'pncp.gov.br' => '93.184.216.55',
    'apitempo.inmet.gov.br' => '93.184.216.56', 'archive-api.open-meteo.com' => '93.184.216.57',
    'data.directory.opinbrasil.com.br' => '93.184.216.58', 'www2.susep.gov.br' => '93.184.216.59'
  }.freeze

  # Também zera o teto global por provedor (#2858 F1): ele vive no Redis e passaria de um exemplo para o outro.
  def resolver_hosts_das_prontas
    allow(Resolv).to receive(:getaddresses).and_call_original
    HOSTS_DAS_PRONTAS.each { |host, ip| allow(Resolv).to receive(:getaddresses).with(host).and_return([ip]) }
    zerar_tetos_das_prontas
  end

  def zerar_tetos_das_prontas
    chaves = []
    Redis::Alfred.scan_each(match: "#{Autonomia::FerramentasProntas::TetoDoProvedor::CHAVE}:*") { |chave| chaves << chave }
    chaves.each { |chave| Redis::Alfred.delete(chave) }
  end

  def ligar_consultas(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG, Autonomia::FerramentasProntas::FLAG_CONSULTAS)
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

  # A pronta que o agente já tem, gravada antes de a fonte sair da vitrine (`Fonte#na_vitrine?` falso): o "Incluir" de
  # hoje recusa, mas a linha que já existe continua valendo no turno.
  def pronta_ja_incluida(fonte, conta:, agente:, usar_quando: 'o cliente informar o dado')
    catalogada = Autonomia::FerramentasProntas::Catalogo.buscar(fonte)
    Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: conta.id, fonte: catalogada.chave)
    agente.tools.create!(
      account: conta, slug: catalogada.slug, name: catalogada.nome, fonte_pronta: catalogada.chave, enabled: true,
      description: usar_quando, http_method: 'GET', endpoint_url: '', timeout_seconds: catalogada.prazo_maximo + 1,
      headers_config: [], param_schema: [], request_body_template: nil, response_mapping: {}
    )
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
