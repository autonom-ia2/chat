# Carga das ligações conversa → anúncio dos últimos WINDOW (#1073, F2b). Roda uma vez por conexão: ao abrir a
# tela ou na rodada das 4h, enquanto `links_backfilled_at` estiver vazio. Lê só o banco (os toques já gravados e
# o cache de nomes); não chama a Meta.
#
# Uma carga por conexão de cada vez (RUNNING_KEY, solta no fim). Avisa a tela aberta quando termina.
class Crm::MetaAds::LinksBackfillJob < ApplicationJob
  queue_as :low

  WINDOW = 90.days
  RUNNING_KEY = 'crm:meta_ads:links:backfill'.freeze
  RUNNING_TTL = 1.hour

  def self.start(connection)
    return false unless Redis::Alfred.set("#{RUNNING_KEY}:#{connection.id}", 1, nx: true, ex: RUNNING_TTL.to_i)

    perform_later(connection.id)
    true
  end

  def perform(connection_id)
    connection = Crm::MetaAdsConnection.find_by(id: connection_id)
    return if connection.blank? || !connection.active?

    candidates(connection).find_each { |conversation| Crm::MetaAds::Links::Linker.new(conversation, connection: connection).perform }
    connection.update!(links_backfilled_at: Time.current)
    Crm::MetaAds::Insights::Broadcaster.broadcast(connection) if connection.ad_account_id.present?
  ensure
    Redis::Alfred.delete("#{RUNNING_KEY}:#{connection_id}")
  end

  private

  # Gravar um toque atualiza a conversa: quem teve toque na janela tem updated_at dentro dela.
  def candidates(connection)
    Conversation.where(account_id: connection.account_id)
                .where(updated_at: WINDOW.ago..)
                .where("conversations.additional_attributes ? 'campaign_touches'")
  end
end
