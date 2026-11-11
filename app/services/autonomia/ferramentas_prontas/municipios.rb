# Os municípios do Brasil, da tabela das sedes municipais da Localização (`lib/ferramentas_prontas/sedes_municipais.csv`,
# licença MIT ao lado): o código IBGE de 7 dígitos, o código que o CNES usa (o IBGE sem o dígito verificador, 6 dígitos:
# Campinas é 3509502 no IBGE e 350950 no CNES) e a coordenada da sede. Servem às fontes da F4 que pedem a cidade: Hospitais
# (o código do CNES), Compras do governo (o IBGE), Estações do tempo e Quanto choveu (a coordenada). O nome compara sem
# acento e sem caixa: é o nome oficial do município, não interpretação de texto.
module Autonomia::FerramentasProntas::Municipios
  DIGITOS_CNES = 6
  DEDUZA_UF = 'a UF sai da cidade: mande só a cidade, ou a sigla de 2 letras do estado dela.'.freeze

  Municipio = Data.define(:codigo, :uf, :nome, :latitude, :longitude) do
    def codigo_cnes
      codigo.first(DIGITOS_CNES)
    end

    def rotulo
      "#{nome} (#{uf})"
    end
  end

  module_function

  # O parâmetro `uf` das fontes que pedem a cidade: opcional, porque sai da cidade (`buscar`). `local`: só filtra aqui.
  def parametro_uf(local: false)
    Autonomia::FerramentasProntas::Parametro.new(
      nome: 'uf', local: local, descricao: 'A sigla do estado da cidade. Opcional: sai da cidade.',
      opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase), deduza: DEDUZA_UF
    )
  end

  # "3170206" -> o município, ou nil.
  def por_codigo(codigo)
    por_codigo_indice[codigo.to_s]
  end

  # "350950" (o código do CNES) -> o município, ou nil.
  def por_codigo_cnes(codigo)
    por_codigo_cnes_indice[codigo.to_s]
  end

  # ("MG", "uberlandia") -> o município, ou nil.
  def buscar(uf_sigla, nome)
    por_nome_indice[[uf_sigla.to_s.upcase, Autonomia::FerramentasProntas::Lista.comparavel(nome)]]
  end

  def municipios
    @municipios ||= CSV.foreach(Autonomia::FerramentasProntas::Fontes::Localizacao::Sedes::ARQUIVO, headers: true).map do |linha|
      Municipio.new(codigo: linha['codigo_ibge'].to_s, uf: linha['uf'], nome: linha['nome'],
                    latitude: linha['latitude'].to_f, longitude: linha['longitude'].to_f)
    end.freeze
  end

  def por_codigo_indice
    @por_codigo_indice ||= municipios.index_by(&:codigo).freeze
  end

  def por_codigo_cnes_indice
    @por_codigo_cnes_indice ||= municipios.index_by(&:codigo_cnes).freeze
  end

  def por_nome_indice
    @por_nome_indice ||= municipios.index_by { |municipio| [municipio.uf, Autonomia::FerramentasProntas::Lista.comparavel(municipio.nome)] }.freeze
  end
end
