# Seus posts (#2199): o período escolhido na tela (7, 30 ou 90 dias de calendário até agora, contando hoje, no fuso da
# conta) e o anterior, do mesmo tamanho, para comparar. Janelas em segundos, como a Meta pede em since/until.
class Crm::MetaAds::Organico::Periodo
  DIAS = [7, 30, 90].freeze

  attr_reader :dias

  def initialize(dias, zona: Time.zone, agora: Time.current)
    raise ArgumentError, "período inválido: #{dias.inspect}" unless DIAS.include?(dias)

    @dias = dias
    @agora = agora.in_time_zone(zona)
    @inicio = (@agora.to_date - (dias - 1)).in_time_zone(zona)
  end

  def atual
    { since: @inicio.to_i, until: @agora.to_i }
  end

  def anterior
    { since: (@inicio - dias.days).to_i, until: @inicio.to_i }
  end

  # Para contar as conversas da caixa no mesmo período.
  def intervalo
    @inicio..@agora
  end

  # As conversas do período anterior, para comparar (Seus posts #2304).
  def intervalo_anterior
    (@inicio - dias.days)...@inicio
  end

  # Datas que a tela mostra ("21 de out. a 27 de out.").
  def de
    @inicio.to_date.iso8601
  end

  def ate
    @agora.to_date.iso8601
  end
end
