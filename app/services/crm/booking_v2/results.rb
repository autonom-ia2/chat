# Números do painel de resultados do agendamento (#1194, J7-A1/A2/A3, J8-A12, RA-19). Só contagens: nenhum nome,
# telefone ou id de cliente sai daqui.
#
# Cada número conta um EVENTO registrado dentro do período (por isso não precisam formar um funil exato: um link
# enviado no fim do mês passado pode ser aberto neste):
#   - enviados: convites com `sent_at` (entregue na conversa ou link copiado);
#   - abriram: convites com `first_opened_at`, aberto antes de virar reunião (abrir o link de gestão depois de
#     marcar não conta de novo);
#   - marcaram: reuniões criadas pelo agendamento novo (`source` invite, public_link, ai ou panel, a marcada pela
#     equipe no painel, #1271);
#   - confirmaram: dessas reuniões, as que o cliente confirmou pelo link (`confirmed_at`);
#   - compareceram / faltaram: resultado registrado (`outcome_recorded_at`) nessas reuniões, o mesmo que o card mostra.
# Convites de teste (`metadata.test`, "Testar no meu WhatsApp") e as reuniões que eles geraram ficam de fora. Os
# convites do link público (`channel: 'public'`) e os da reunião marcada pela equipe (`channel: 'panel'`, só o link
# de gestão) nascem já agendados: não contam como enviados nem abertos. A conversão dos links (enviados → abriram)
# continua só com links que o cliente recebeu para escolher.
#
# Origem (J7-A3) de cada reunião marcada: pedido de contato (o card nasceu de "Nenhum horário serve?"), link
# público, pela equipe (painel), IA ou conversa (o link por cliente, entregue na conversa ou copiado). O pedido de
# contato vem primeiro em qualquer reunião, como sempre: a demanda nasceu ali. IA só aparece quando houver.
#
# `user` presente = "Meus números" (J8-A12): links que a pessoa criou e reuniões em que ela é a responsável
# (`created_by`, quem atende). Na reunião marcada pela equipe vale a mesma regra: conta para quem atende, não para
# quem marcou (`metadata.booked_by_user_id`), decisão do #1271.
class Crm::BookingV2::Results
  BOOKING_SOURCES = %w[invite public_link ai panel].freeze
  NOT_SENT_CHANNELS = %w[public panel].freeze
  ORIGINS = %w[conversation public_link contact_request team ai].freeze
  OPTIONAL_ORIGINS = %w[ai].freeze
  ORIGIN_SQL = <<~SQL.squish.freeze
    CASE WHEN crm_cards.source = 'contact_request' THEN 'contact_request'
         WHEN crm_meetings.source = 'public_link' THEN 'public_link'
         WHEN crm_meetings.source = 'panel' THEN 'team'
         WHEN crm_meetings.source = 'ai' THEN 'ai'
         ELSE 'conversation' END
  SQL

  def initialize(account:, period:, user: nil)
    @account = account
    @period = period
    @user = user
  end

  def totals
    {
      sent: invites.where(sent_at: range).count,
      opened: invites.where(first_opened_at: range).where('scheduled_at IS NULL OR first_opened_at <= scheduled_at').count,
      booked: booked.count,
      confirmed: meetings.where(confirmed_at: range).count,
      attended: meetings.outcome_held.where(outcome_recorded_at: range).count,
      no_show: meetings.outcome_no_show.where(outcome_recorded_at: range).count
    }
  end

  def origins
    counts = booked.joins(:card).group(Arel.sql(ORIGIN_SQL)).count
    ORIGINS.filter_map do |key|
      count = counts.fetch(key, 0)
      { key: key, count: count } unless OPTIONAL_ORIGINS.include?(key) && count.zero?
    end
  end

  private

  attr_reader :account, :period, :user

  def range
    period.range
  end

  def invites
    scope = Crm::BookingInvite.real.where(account_id: account.id).where.not(channel: NOT_SENT_CHANNELS)
    user ? scope.where(created_by_id: user.id) : scope
  end

  def meetings
    scope = Crm::Meeting.where(account_id: account.id, source: BOOKING_SOURCES).where.not(id: test_meeting_ids)
    user ? scope.where(created_by_id: user.id) : scope
  end

  def booked
    meetings.where(created_at: range)
  end

  def test_meeting_ids
    Crm::BookingInvite.where(account_id: account.id).where.not(meeting_id: nil)
                      .where("crm_booking_invites.metadata->>'test' = 'true'").select(:meeting_id)
  end
end
