# Próximo passo de quem vende em CRM › Números (#1897, F3 do #1871): "4 pessoas que responderam à campanha Dia das
# Crianças estão com você". Conta os cards abertos da pessoa cuja conversa principal ganhou, no mês, a marca de uma
# campanha respondida (CampaignJourney::CampaignMarks; a marca só é gravada quando o cliente responde). Fica a campanha
# com mais gente; o "Ver" abre o Kanban com a campanha + responsável = eu (filtros do link, #1886).
class Crm::Numeros::CampanhaComVoce
  MAX_CONVERSAS = 2_000

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

  # Uma pessoa conta uma vez por campanha, mesmo que tenha respondido duas vezes.
  def contar
    contagem = Hash.new(0)
    nomes = {}
    toques_por_conversa.each do |toques|
      toques.uniq { |toque| toque['source_id'] }.each do |toque|
        contagem[toque['source_id']] += 1
        nomes[toque['source_id']] ||= toque['headline']
      end
    end
    [contagem, nomes]
  end

  def toques_por_conversa
    ids = @cards.where.not(conversation_id: nil).limit(MAX_CONVERSAS).pluck(:conversation_id)
    @account.conversations.where(id: ids).pluck(:additional_attributes).map do |atributos|
      toques = atributos.is_a?(Hash) ? Array(atributos['campaign_touches']) : []
      toques.select { |toque| da_campanha_no_mes?(toque) }
    end
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
