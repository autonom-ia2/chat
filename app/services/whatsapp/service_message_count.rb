# Quantas respostas ao cliente (mensagem livre, sem modelo) cada número do WhatsApp oficial mandou no mês corrente
# (#1332): a tela compara com a franquia de `Whatsapp::Pricing.free_tier('service')`. Conta mensagens enviadas, não
# privadas, que não falharam e não levam modelo (`additional_attributes.template_params`). O mês é o do calendário em
# UTC, como a cobrança da Meta. A contagem para em `cap` (a franquia + 1): passou disso, a tela só precisa saber que
# passou.
class Whatsapp::ServiceMessageCount
  def initialize(account:, inbox_ids:, cap:, now: Time.current)
    @account = account
    @inbox_ids = inbox_ids
    @cap = cap
    @now = now
  end

  def perform
    @inbox_ids.index_with { |inbox_id| count(inbox_id) }
  end

  private

  def count(inbox_id)
    Message.where(account_id: @account.id, inbox_id: inbox_id, message_type: :outgoing, private: false,
                  created_at: @now.utc.beginning_of_month..@now)
           .where.not(status: :failed)
           .where("(messages.additional_attributes -> 'template_params') IS NULL")
           .limit(@cap).count
  end
end
