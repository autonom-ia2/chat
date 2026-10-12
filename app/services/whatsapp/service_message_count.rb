# Quantas respostas ao cliente (mensagem livre, sem modelo) cada número do WhatsApp oficial mandou no mês corrente
# (#1332): a tela compara com a franquia de `Whatsapp::Pricing.free_tier('service')`. Conta mensagens enviadas, não
# privadas, que não falharam e não levam modelo (`additional_attributes.template_params`). O mês é o do calendário em
# UTC, como a cobrança da Meta. Uma consulta só para todas as caixas, guardada por 5 minutos.
class Whatsapp::ServiceMessageCount
  CACHE_TTL = 5.minutes

  def initialize(account:, inbox_ids:, now: Time.current)
    @account = account
    @inbox_ids = inbox_ids.sort
    @now = now
  end

  # { inbox_id => n }, com 0 para a caixa que não mandou nada.
  def perform
    counts = Rails.cache.fetch(['whatsapp_service_message_count', @account.id, @inbox_ids, month_start.to_date], expires_in: CACHE_TTL) do
      Message.where(account_id: @account.id, inbox_id: @inbox_ids, message_type: :outgoing, private: false,
                    created_at: month_start..@now)
             .where.not(status: :failed)
             .where("(messages.additional_attributes -> 'template_params') IS NULL")
             .reorder(nil).group(:inbox_id).count
    end
    @inbox_ids.index_with { |inbox_id| counts.fetch(inbox_id, 0) }
  end

  private

  def month_start
    @now.utc.beginning_of_month
  end
end
