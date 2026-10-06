# Quem pode ler a Meta agora (#1073, CA-2.8).
#
# Cada conexão tem uma trava por escopo (`today`, `recent`): quem enfileira a leitura pega a trava e o job a
# solta no fim. Assim várias pessoas abrindo a tela ao mesmo tempo, ou a tela e o agendador, geram uma
# leitura só. A trava expira sozinha em LOCK_TTL se o job morrer no meio.
#
# A tela pede ao abrir, a cada MIN_AGE enquanto está aberta e ao voltar para a aba; só lê de novo se o gasto de
# hoje tiver mais de MIN_AGE. Conexão sem a carga de 90 dias começa a carga ali mesmo, sem esperar as 4h.
class Crm::MetaAds::Insights::Refresh
  MIN_AGE = 2.minutes
  LOCK_TTL = 10.minutes
  KEY_PREFIX = 'crm:meta_ads:insights:lock'.freeze
  TODAY = 'today'.freeze

  class << self
    # Pedido da tela: enfileira a leitura de hoje se estiver velha. true quando há leitura em andamento.
    def request!(connection)
      return false unless connection.active? && connection.ad_account_id.present?

      start_missing_loads(connection)
      return running?(connection.id) unless stale?(connection)
      return false if Crm::MetaAds::Insights::Usage.paused?(connection.ad_account_id)
      return true unless claim(connection.id, TODAY)

      Crm::MetaAds::InsightsSyncJob.perform_later(connection.id, TODAY)
      true
    end

    # Carga de 90 dias (Meta) e das ligações conversa → anúncio (banco) que ainda não rodaram.
    def start_missing_loads(connection)
      Crm::MetaAds::InsightsBackfillJob.start(connection) if connection.insights_backfilled_at.nil?
      Crm::MetaAds::LinksBackfillJob.start(connection) if connection.links_backfilled_at.nil?
    end

    def stale?(connection)
      connection.insights_synced_at.nil? || connection.insights_synced_at < MIN_AGE.ago
    end

    def claim(connection_id, scope)
      Redis::Alfred.set(key(connection_id, scope), 1, nx: true, ex: LOCK_TTL.to_i) ? true : false
    end

    def release(connection_id, scope)
      Redis::Alfred.delete(key(connection_id, scope))
    end

    def running?(connection_id, scope = TODAY)
      Redis::Alfred.exists?(key(connection_id, scope))
    end

    def key(connection_id, scope)
      "#{KEY_PREFIX}:#{connection_id}:#{scope}"
    end
  end
end
