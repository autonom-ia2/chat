# #2907 — A checagem de saúde (a cada 6 h pelo `HealthSyncScheduler`, e quando alguém abre a Saúde da conta) passa a
# contar o erro de autorização da Graph. No segundo erro de autorização sem checagem boa no meio
# (`Reauthorizable::AUTHORIZATION_ERROR_THRESHOLD`; erro de outro tipo, como 5xx, não zera nem soma), a caixa fica "precisa
# reconectar": acende o aviso do menu, manda o e-mail aos administradores e o evento da caixa.
#
# Uma checagem boa apaga só o que a contagem marcou. O aviso que veio do webhook da Meta (`AccountUpdateJob`, contagem 0)
# fica até a reconexão ou o ACCOUNT_RECONNECTED: depois de um ACCOUNT_OFFBOARDED a Graph ainda pode ler o número enquanto o
# envio falha. Prepended em `Whatsapp::HealthService`.
module Whatsapp::AccessLoss::HealthCheck
  private

  def fetch_health_status_with_error(...)
    health_status, error = super
    error ? record_access_error(error) : record_access_ok
    [health_status, error]
  rescue Whatsapp::HealthService::ApiError => e
    record_access_error(e)
    raise
  end

  def record_access_error(error)
    @channel.authorization_error! if error.is_a?(Whatsapp::HealthService::ApiError) && error.authorization_error?
  end

  def record_access_ok
    @channel.reauthorized! if @channel.authorization_error_count.positive?
  end
end
