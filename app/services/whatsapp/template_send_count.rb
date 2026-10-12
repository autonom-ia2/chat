# Quantas vezes cada modelo saiu por cada caixa no mês corrente (#1332): a lista de Modelos mostra "Enviado N vezes
# neste mês". Conta mensagens enviadas, não privadas, que não falharam e levam o modelo
# (`additional_attributes.template_params.name`), em uma consulta só. Mês do calendário em UTC.
class Whatsapp::TemplateSendCount
  NAME = "messages.additional_attributes -> 'template_params' ->> 'name'".freeze

  def initialize(account:, inbox_ids:, now: Time.current)
    @account = account
    @inbox_ids = inbox_ids
    @now = now
  end

  # { inbox_id => { 'nome_do_modelo' => n } }
  def perform
    counts = Message.where(account_id: @account.id, inbox_id: @inbox_ids, message_type: :outgoing, private: false,
                           created_at: @now.utc.beginning_of_month..@now)
                    .where.not(status: :failed)
                    .where("#{NAME} IS NOT NULL")
                    .reorder(nil).group(:inbox_id, Arel.sql(NAME)).count
    counts.each_with_object({}) do |((inbox_id, name), total), result|
      (result[inbox_id] ||= {})[name] = total
    end
  end
end
