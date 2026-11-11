# O CEP DE REFERÊNCIA DA CIDADE (#2858, regra "QI 70" do Rodrigo, 11/11/2026): "se a API pede o CEP só para saber a
# cidade, usar o CEP padrão da cidade". Para a fonte cujo dado é por cidade e que pede um CEP (a criminalidade da F7):
# a plataforma acha um CEP da cidade sozinha, e o agente não pergunta ao cliente.
#
# INTERFACE ESTÁVEL (a F7 usa). O método que a F7 chama é `Autonomia::FerramentasProntas::Premium::Endereco.cep(cidade:,
# uf:, rua: nil, bairro: nil)`, que devolve `{'cep'=>…}`, `{'candidatos'=>[…]}` ou nil; ele só precisa delegar a:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep(cidade:, uf: nil, rua: nil, bairro: nil, conta: nil)
#   - sem rua: `{'cep' => cep_da_cidade(...)}`, ou nil;
#   - com rua: os CEPs da rua no ViaCEP (a mesma busca da consulta `por_endereco`, `ViaCep#ceps_da_rua`), filtrados
#     pelo bairro quando vem (todas as palavras, sem acento); um só -> `{'cep' => '01311-000'}`; vários ->
#     `{'candidatos' => [{ 'cep', 'logradouro', 'complemento', 'bairro' }]}`, até `Cep::MAX_CEPS`, o CEP da rua (faixa
#     de número) antes do especial de prédio; nenhum, cidade que não existe ou homônima sem UF, fonte fora -> nil.
#   Cada pedido com rua é uma chamada ao ViaCEP (o cache é o da consulta `por_endereco` só quando ela roda pela
#   `Execucao`); nunca levanta.
# E o CEP de referência sozinho:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep_da_cidade(cidade: 'Uberlândia', uf: nil, conta: 42)
#   -> "38400-263" (String, com traço), ou nil.
#   - `cidade`: o nome, como o cliente disse; `uf`: opcional (a cidade única no Brasil basta; a homônima sem UF dá nil);
#   - `conta`: o id da conta, para a fatia dela no teto global do ViaCEP (`TetoDoProvedor`);
#   - nil quando a cidade não existe, é homônima sem UF, ou o ViaCEP não respondeu: quem chama decide (perguntar a cidade,
#     ou dizer que não conseguiu). Nunca levanta.
#
# COMO (escolhido com evidência, 11/11/2026): não há API pública e gratuita de "CEP da cidade". O DNE dos Correios é pago,
# o IBGE não tem CEP, e a BrasilAPI só vai do CEP para o endereço. O ViaCEP busca pela rua (`/ws/UF/cidade/rua/json/`):
#   - cidade com CEP por rua: a busca pela palavra "Rua" devolve até 50 ruas da cidade (Uberlândia: 50, a primeira
#     38400-263); vale o MENOR CEP da própria cidade (conferido pelo código IBGE), para a escolha ser estável;
#   - cidade de CEP único (as pequenas): a mesma busca devolve o registro da localidade sem rua, com o CEP geral (Serra
#     da Saudade/MG: 35617-000), que é o "CEP padrão" da cidade.
# Uma chamada por cidade, guardada por 30 dias (o CEP de uma cidade não muda).
module Autonomia::FerramentasProntas::Fontes::Cep::Referencia
  RUA = 'Rua'.freeze
  PRAZO = 4
  VALIDADE = 30.days
  CHAVE = 'autonomia:prontas:v1:cep_referencia'.freeze

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

    municipio = Autonomia::FerramentasProntas::Municipios.buscar(uf, cidade)
    return if municipio.nil?

    ceps = Autonomia::FerramentasProntas::Lista.filtrar(da_rua(municipio, rua, conta), bairro) { |item| item['bairro'].to_s }
    return if ceps.empty?
    return { 'cep' => ceps.first['cep'] } if ceps.one?

    { 'candidatos' => Autonomia::FerramentasProntas::Fontes::Cep.lista(municipio, rua, ceps)['ceps'] }
  end

  def da_rua(municipio, rua, conta)
    via_cep(conta).ceps_da_rua(municipio, rua.to_s.squish)
  rescue Autonomia::FerramentasProntas::Provedor::Falha, Autonomia::FerramentasProntas::Provedor::NaoEncontrado => e
    Rails.logger.warn("[autonomia][pronta] cep da rua sem resposta municipio=#{municipio.codigo} #{e.class}")
    []
  end

  def via_cep(conta)
    classe = Autonomia::FerramentasProntas::Fontes::Cep::ViaCep
    cliente = Autonomia::FerramentasProntas::ClienteHttp.new(
      hosts: [classe.host], prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + PRAZO, conta: conta
    )
    classe.new(cliente, prazo: PRAZO)
  end

  def da_fonte(municipio, conta)
    via_cep(conta).ceps_da_rua(municipio, RUA).pluck('cep').min
  rescue Autonomia::FerramentasProntas::Provedor::Falha, Autonomia::FerramentasProntas::Provedor::NaoEncontrado => e
    Rails.logger.warn("[autonomia][pronta] cep de referencia sem resposta municipio=#{municipio.codigo} #{e.class}")
    nil
  end

  def ler(municipio)
    Rails.cache.read("#{CHAVE}:#{municipio.codigo}")
  rescue StandardError
    nil
  end

  def gravar(municipio, cep)
    Rails.cache.write("#{CHAVE}:#{municipio.codigo}", cep, expires_in: VALIDADE)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] cache do cep de referencia falhou #{e.class}")
  end
end
