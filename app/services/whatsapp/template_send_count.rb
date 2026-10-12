# Quantas vezes cada modelo saiu por cada caixa no mês corrente (#1332): a lista de Modelos mostra "Enviado N vezes
# neste mês". Soma duas fontes, guardada por 5 minutos, com o mês do calendário em UTC:
# - mensagens enviadas na conversa, não privadas, que não falharam e levam o modelo
#   (`additional_attributes.template_params.name`);
# - envios de campanha do WhatsApp oficial (#1382): o envio da campanha não cria mensagem com `template_params` (a
#   jornada grava na conversa só `campaign_id`/`campaign_template_name`, e só quando a conversa já existe). Conta o
#   destinatário que a Meta aceitou neste mês (`sent_at`, status enviado, entregue ou lido) pelo modelo da campanha.
class Whatsapp::TemplateSendCount
  CACHE_TTL = 5.minutes
  NAME = "messages.additional_attributes -> 'template_params' ->> 'name'".freeze
  CAMPAIGN_NAME = "campaigns.template_params ->> 'name'".freeze
  ACCEPTED_STATUSES = %w[sent delivered read].freeze

  def initialize(account:, inbox_ids:, now: Time.current)
    @account = account
    @inbox_ids = inbox_ids
    @now = now
  end

  # { inbox_id => { 'nome_do_modelo' => n } }
  def perform
    Rails.cache.fetch(['whatsapp_template_send_count', @account.id, @inbox_ids.sort, @now.utc.beginning_of_month.to_date],
                      expires_in: CACHE_TTL) { count }
  end

  private

  def month
    @now.utc.beginning_of_month..@now
  end

  def count
    (message_counts.to_a + campaign_counts.to_a).each_with_object({}) do |((inbox_id, name), total), result|
      by_name = (result[inbox_id] ||= {})
      by_name[name] = by_name.fetch(name, 0) + total
    end
  end

  def message_counts
    Message.where(account_id: @account.id, inbox_id: @inbox_ids, message_type: :outgoing, private: false, created_at: month)
           .where.not(status: :failed)
           .where("#{NAME} IS NOT NULL")
           .reorder(nil).group(:inbox_id, Arel.sql(NAME)).count
  end

  def campaign_counts
    return {} unless ChatwootApp.enterprise?

    CampaignRecipient.joins(:campaign)
                     .where(account_id: @account.id, inbox_id: @inbox_ids, status: ACCEPTED_STATUSES, sent_at: month)
                     .where("#{CAMPAIGN_NAME} IS NOT NULL")
                     .reorder(nil).group('campaign_recipients.inbox_id', Arel.sql(CAMPAIGN_NAME)).count
  end
end
