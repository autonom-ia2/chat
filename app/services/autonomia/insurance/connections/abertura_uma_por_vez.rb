# UMA ABERTURA DE COTAÇÃO POR VEZ, POR CONEXÃO (chat#612, 23/09/2026).
#
# Abrir uma cotação no portal confere, antes, o login de cada seguradora da corretora (~15 pedidos à rota que devolve
# login e senha). Quatro cotações abertas no mesmo segundo fizeram essas conferências quatro vezes ao mesmo tempo: as
# cotações nasceram com 3, 2, 4 e 1 seguradoras, sem repetição entre elas, e o firewall do portal bloqueou a conta
# minutos depois. O adapter guarda o veredito válido por alguns minutos, mas cada chamada simultânea ao Lambda roda num
# container diferente, e a memória de um não serve ao outro. Em fila, a segunda abertura encontra o veredito da
# primeira. Só a ABERTURA espera a vez (segundos); as cotações abertas continuam correndo juntas.
#
# A trava nunca mata a cotação: esperando mais que `ESPERA_MAXIMA` (uma abertura presa no portal), ela segue sem a
# vez, e fica no log.
class Autonomia::Insurance::Connections::AberturaUmaPorVez
  # O espaço desta trava nos locks consultivos do Postgres (a outra metade da chave é o id da conexão).
  ESPACO = 7131
  ESPERA_MAXIMA = 90.seconds
  INTERVALO = 0.5

  def self.call(connection, &)
    new(connection).call(&)
  end

  def initialize(connection)
    @connection = connection
  end

  def call
    obtida = esperar_a_vez
    yield
  ensure
    liberar if obtida
  end

  private

  def esperar_a_vez
    limite = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ESPERA_MAXIMA
    loop do
      return true if tentar
      return sem_a_vez if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= limite

      sleep(INTERVALO)
    end
  end

  def tentar
    banco.select_value(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_try_advisory_lock(?, ?)', ESPACO, @connection.id]))
  end

  def liberar
    banco.select_value(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_unlock(?, ?)', ESPACO, @connection.id]))
  end

  def sem_a_vez
    Rails.logger.warn("[autonomia][insurance] abertura sem a vez connection=#{@connection.id} espera=#{ESPERA_MAXIMA.to_i}s")
    false
  end

  def banco
    ActiveRecord::Base.connection
  end
end
