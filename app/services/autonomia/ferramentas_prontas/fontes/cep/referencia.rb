# O CEP DE REFERÊNCIA DA CIDADE (#2858, regra "QI 70" do Rodrigo, 11/11/2026): "se a API pede o CEP só para saber a
# cidade, usar o CEP padrão da cidade". Para a fonte cujo dado é por cidade e que pede um CEP (a criminalidade da F7):
# a plataforma acha um CEP da cidade sozinha, e o agente não pergunta ao cliente.
#
# CONTRATO COM QUEM CHAMA (a F7): aqui não há contador, acesso nem flag. Quem chama já passou pela própria `Execucao` (ou
# equivalente) e é ele quem confere o acesso da conta e a flag e conta o uso no limite do dia (`Uso.reservar!`). Aqui
# valem só o teto global do ViaCEP (`TetoDoProvedor`, pela `conta`) e o cache da fonte CEP.
#
# INTERFACE ESTÁVEL (a F7 usa). O método que a F7 chama é `Autonomia::FerramentasProntas::Premium::Endereco.cep(cidade:,
# uf:, rua: nil, bairro: nil)`, que devolve `{'cep'=>…}`, `{'candidatos'=>[…]}` ou nil; ele só precisa delegar a:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep(cidade:, uf: nil, rua: nil, bairro: nil, conta: nil)
#   - sem rua: `{'cep' => cep_da_cidade(...)}`, ou nil;
#   - com rua: a MESMA consulta `por_endereco` (mesma normalização, mesmo cache de 30 dias e mesma chave, pelo `Apoio`):
#     até `Cep::MAX_CEPS` CEPs, o da rua (faixa de número) antes do especial de prédio. O bairro, quando vem, filtra
#     (todas as palavras, sem acento); se o filtro esvaziar a lista ("Jardim America" contra "Jd America"), vale a lista
#     sem ele. Um só -> `{'cep' => '01311-000'}`; vários -> `{'candidatos' => [{ 'cep', 'logradouro', 'complemento',
#     'bairro' }]}`; nenhum, cidade que não existe, homônima sem UF ou UF errada, fonte fora -> nil.
# E o CEP de referência sozinho:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep_da_cidade(cidade: 'Uberlândia', uf: nil, conta: 42)
#   -> "38400-263" (String, com traço), ou nil.
#   - `cidade`: o nome, como o cliente disse; `uf`: opcional (a cidade única no Brasil basta; a homônima sem UF dá nil);
#   - `conta`: o id da conta, para a fatia dela no teto global do ViaCEP;
#   - nil quando a cidade não existe, é homônima sem UF, ou o ViaCEP não respondeu: quem chama decide (perguntar a cidade,
#     ou dizer que não conseguiu).
# Não levanta por fonte fora nem por cache fora do ar (erro de conexão do Redis, logado com a classe).
#
# COMO (escolhido com evidência, 11/11/2026): não há API pública e gratuita de "CEP da cidade". O DNE dos Correios é pago,
# o IBGE não tem CEP, e a BrasilAPI só vai do CEP para o endereço. O ViaCEP busca pela rua (`/ws/UF/cidade/rua/json/`):
#   - cidade com CEP por rua: a busca pela palavra "Rua" devolve até 50 ruas da cidade (Uberlândia: 50, a primeira
#     38400-263); vale o MENOR CEP comum (o especial de prédio ou órgão, sufixo 900 a 999, só se não houver outro) entre
#     os que a consulta `por_endereco` guarda, conferidos pelo código IBGE, para a escolha ser estável;
#   - cidade de CEP único (as pequenas): a mesma busca devolve o registro da localidade sem rua, com o CEP geral (Serra
#     da Saudade/MG: 35617-000), que é o "CEP padrão" da cidade.
# Uma chamada por cidade, guardada por 30 dias (o CEP de uma cidade não muda).
module Autonomia::FerramentasProntas::Fontes::Cep::Referencia
  RUA = 'Rua'.freeze
  PRAZO = 4
  VALIDADE = 30.days
  CHAVE = 'autonomia:prontas:v1:cep_referencia'.freeze
  ERROS_DO_CACHE = Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS

  module_function

  def cep_da_cidade(cidade:, uf: nil, conta: nil) # rubocop:disable Naming/MethodParameterName
    municipio = Autonomia::FerramentasProntas::Municipios.buscar(uf, cidade)
    return if municipio.nil?

    guardado = ler(municipio)
    return guardado if guardado

    da_fonte(municipio, conta).tap { |cep| gravar(municipio, cep) if cep }
  end

  def cep(cidade:, uf: nil, rua: nil, bairro: nil, conta: nil) # rubocop:disable Naming/MethodParameterName
    return cep_da_cidade(cidade: cidade, uf: uf, conta: conta)&.then { |achado| { 'cep' => achado } } if rua.blank?

    ceps = do_bairro(da_rua(cidade, uf, rua, conta), bairro)
    return if ceps.empty?
    return { 'cep' => ceps.first['cep'] } if ceps.one?

    { 'candidatos' => ceps }
  end

  # O filtro do bairro que esvazia a lista não vale: o bairro do cliente pode estar escrito de outro jeito.
  def do_bairro(ceps, bairro)
    filtrados = Autonomia::FerramentasProntas::Lista.filtrar(ceps, bairro) { |item| item['bairro'].to_s }
    filtrados.presence || ceps
  end

  # Os CEPs da rua pela consulta `por_endereco`: a mesma conferência dos parâmetros e o mesmo cache. -> lista (vazia
  # quando a cidade não serve, a rua não tem CEP ou a fonte não respondeu).
  def da_rua(cidade, uf, rua, conta) # rubocop:disable Naming/MethodParameterName
    fonte = Autonomia::FerramentasProntas::Fontes::Cep::FONTE
    params, falta = fonte.consulta('por_endereco').conferir('logradouro' => rua, 'cidade' => cidade, 'uf' => uf)
    return [] if falta

    Array(Autonomia::FerramentasProntas::Apoio.new(fonte, cliente(conta)).dados('por_endereco', params)&.dig('ceps'))
  rescue Autonomia::FerramentasProntas::Apoio::SemResposta => e
    Rails.logger.warn("[autonomia][pronta] cep da rua sem resposta motivos=#{e.motivos.join(',')}")
    []
  end

  def cliente(conta)
    Autonomia::FerramentasProntas::ClienteHttp.new(
      hosts: [Autonomia::FerramentasProntas::Fontes::Cep::ViaCep.host],
      prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + PRAZO, conta: conta
    )
  end

  def da_fonte(municipio, conta)
    ceps = da_rua(municipio.nome, municipio.uf, RUA, conta).pluck('cep')
    comuns = ceps.reject { |cep| Autonomia::FerramentasProntas::Fontes::Cep.especial?(cep) }
    (comuns.presence || ceps).min
  end

  def ler(municipio)
    Rails.cache.read("#{CHAVE}:#{municipio.codigo}")
  rescue *ERROS_DO_CACHE => e
    Rails.logger.warn("[autonomia][pronta] cache do cep de referencia falhou na leitura #{e.class}")
    nil
  end

  def gravar(municipio, cep)
    Rails.cache.write("#{CHAVE}:#{municipio.codigo}", cep, expires_in: VALIDADE)
  rescue *ERROS_DO_CACHE => e
    Rails.logger.warn("[autonomia][pronta] cache do cep de referencia falhou na escrita #{e.class}")
  end
end
