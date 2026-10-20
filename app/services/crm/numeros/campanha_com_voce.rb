# Próximo passo de quem vende em CRM › Números (#1897, F3 do #1871): "4 pessoas que responderam à campanha Dia das
# Crianças estão com você". Conta os cards abertos da pessoa (no funil principal, o mesmo do "Ver") cuja conversa
# principal ganhou, no mês, a marca de uma campanha respondida (CampaignJourney::CampaignMarks; a marca só é gravada
# quando o cliente responde). Fica a campanha com mais gente; o "Ver" abre o Kanban com a campanha + responsável = eu (filtros do link, #1886).
class Crm::Numeros::CampanhaComVoce
  MAX_CARDS = 2_000

  def initialize(account:, cards:, range:)
    @account = account
    @cards = cards
    @range = range
  end

  def perform
    contagem, nomes = contar
    origem, total = contagem.max_by { |_origem, n| n }
    return if origem.nil? || nomes[origem].blank?

    { tipo: 'campanha_com_voce', n: total, campanha: nomes[origem], origem: origem }
  end

  private

  # Cada card conta uma vez por campanha, mesmo que a pessoa tenha respondido duas vezes.
  def contar
    contagem = Hash.new(0)
    nomes = {}
    toques_por_card.each do |toques|
      toques.uniq { |toque| toque['source_id'] }.each do |toque|
        contagem[toque['source_id']] += 1
        nomes[toque['source_id']] ||= toque['headline']
      end
    end
    [contagem, nomes]
  end

  def toques_por_card
    conversas = @cards.where.not(conversation_id: nil).limit(MAX_CARDS).pluck(:conversation_id)
    atributos = @account.conversations.where(id: conversas.uniq).pluck(:id, :additional_attributes).to_h
    conversas.map { |id| toques_de(atributos[id]).select { |toque| da_campanha_no_mes?(toque) } }
  end

  # `additional_attributes` às vezes vem como JSON dentro de string.
  def toques_de(atributos)
    atributos = JSON.parse(atributos) if atributos.is_a?(String)
    atributos.is_a?(Hash) ? Array(atributos['campaign_touches']) : []
  rescue JSON::ParserError
    []
  end

  def da_campanha_no_mes?(toque)
    return false unless toque.is_a?(Hash) && toque['source_id'].present?
    return false unless CampaignJourney::CampaignMarks::SOURCES.include?(toque['source_type'])

    momento = Time.zone.parse(toque['touched_at'].to_s)
    momento.present? && @range.cover?(momento)
  rescue ArgumentError
    false
  end
end
