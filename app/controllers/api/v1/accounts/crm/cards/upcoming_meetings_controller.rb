# Aviso ao arquivar (Parte A, #2091): a reunião marcada continua de pé quando o card é arquivado (Crm::Cards::Archiver),
# e o diálogo de arquivar avisa. Devolve, para os cards pedidos que a pessoa vê, o início da próxima reunião marcada, numa
# consulta só (o lote manda até 100 cards). O horário vem no fuso da conta, que o painel usa para escrever a data.
#
#   GET .../crm/cards/upcoming_meetings?card_ids[]=1&card_ids[]=2
#   => { payload: { timezone: 'America/Sao_Paulo', cards: [{ card_id: 1, starts_at: '2026-10-25T10:00:00-03:00' }] } }
class Api::V1::Accounts::Crm::Cards::UpcomingMeetingsController < Api::V1::Accounts::Crm::BaseController
  MAX_CARDS = Crm::Cards::BulkAction::MAX_IDS

  def index
    authorize ::Crm::Card, :index?
    zone = Crm::Timezone::Resolver.new(account: Current.account).zone_or_default
    render json: { payload: { timezone: zone.tzinfo.name, cards: proximas.map { |card_id, inicio| linha(card_id, inicio, zone) } } }
  end

  private

  def proximas
    ids = Array(params[:card_ids]).filter_map { |id| Integer(id, exception: false) }.uniq.first(MAX_CARDS)
    return {} if ids.empty?

    Current.account.crm_meetings.upcoming.where(card_id: policy_scope(::Crm::Card).where(id: ids).select(:id))
           .group(:card_id).minimum(:starts_at)
  end

  def linha(card_id, inicio, zone)
    { card_id: card_id, starts_at: inicio.in_time_zone(zone).iso8601 }
  end
end
