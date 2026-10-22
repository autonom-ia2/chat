# Travas do CRM com duas conexões reais (#2094): os exemplos marcados com :crm_travas rodam sem transação de teste (os
# dados ficam gravados de verdade, para a outra conexão enxergar) e apagam a conta no fim.
module CrmTravasHelper
  # Roda o bloco numa conexão própria, numa thread. Devolve o pid da conexão; o resultado (ou o nome do erro) vai para
  # `resultados`.
  def em_outra_conexao(resultados)
    pid = Queue.new
    crm_travas_threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '5s'")
        pid << conexao.select_value('SELECT pg_backend_pid()')
        resultados << yield
      rescue StandardError => e
        resultados << e.class.name
      end
    end
    pid.pop
  end

  # Espera a conexão ficar parada numa trava do banco.
  def esperar_na_trava(pid)
    Timeout.timeout(5) do
      sleep 0.02 until ActiveRecord::Base.connection.select_value(
        "SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{pid.to_i}"
      )
    end
  end

  def crm_travas_threads
    @crm_travas_threads ||= []
  end

  def resultados_de(fila, quantos)
    Array.new(quantos) { fila.pop }
  end

  def apagar_conta_gravada(account, *users)
    Crm::FollowUp.where(account_id: account.id).delete_all
    Crm::FollowUpSeries.where(account_id: account.id).delete_all
    Crm::Activity.where(account_id: account.id).delete_all
    account.crm_cards.destroy_all
    account.crm_pipelines.destroy_all
    account.account_users.destroy_all
    account.destroy!
    users.each { |user| apagar_usuario_gravado(user) }
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def apagar_usuario_gravado(user)
    NotificationSetting.where(user_id: user.id).delete_all
    AccessToken.where(owner: user).delete_all
    user.destroy!
  end
end

RSpec.configure do |config|
  config.include CrmTravasHelper, :crm_travas
end
