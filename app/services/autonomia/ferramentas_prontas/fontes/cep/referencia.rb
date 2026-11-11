# O CEP DE REFERÊNCIA DA CIDADE (#2858, regra "QI 70" do Rodrigo, 11/11/2026): "se a API pede o CEP só para saber a
# cidade, usar o CEP padrão da cidade". Para a fonte cujo dado é por cidade e que pede um CEP (a criminalidade da F7):
# a plataforma acha um CEP da cidade sozinha, e o agente não pergunta ao cliente.
#
# INTERFACE ESTÁVEL (a F7 usa):
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

  def da_fonte(municipio, conta)
    via_cep = Autonomia::FerramentasProntas::Fontes::Cep::ViaCep
    cliente = Autonomia::FerramentasProntas::ClienteHttp.new(
      hosts: [via_cep.host], prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + PRAZO, conta: conta
    )
    via_cep.new(cliente, prazo: PRAZO).ceps_da_rua(municipio, RUA).pluck('cep').min
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
