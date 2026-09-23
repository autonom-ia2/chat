# UMA ABERTURA DE COTAÇÃO POR VEZ, POR CONEXÃO (chat#612, 23/09/2026).
#
# Abrir uma cotação no portal confere, antes, o login de cada seguradora da corretora (~15 pedidos à rota que devolve
# login e senha). Quatro cotações abertas no mesmo segundo fizeram essas conferências quatro vezes ao mesmo tempo: as
# cotações nasceram com 3, 2, 4 e 1 seguradoras, sem repetição entre elas, e o firewall do portal bloqueou a conta
# minutos depois. O adapter guarda o veredito válido por alguns minutos, mas cada chamada simultânea ao Lambda roda num
# container diferente, e a memória de um não serve ao outro. Em fila, a segunda abertura encontra o veredito da
# primeira. Só a ABERTURA espera a vez; as cotações abertas continuam correndo juntas.
#
# SEM A VEZ, NÃO SE DORME: o motor não segura worker (`AsyncRunJob`), e um `sleep` aqui atravessaria o deploy no meio
# da espera. Levanta `SemAVez` antes da chamada paga; o motor devolve a intenção e reagenda a passada em segundos.
#
# A trava nunca mata a cotação: pedida há mais que `ESPERA_MAXIMA` (uma abertura presa no portal), ela segue sem a
# vez, e fica no log. Sem o instante do pedido não há quem reagende, e ela segue também.
class Autonomia::Insurance::Connections::AberturaUmaPorVez
  # O espaço desta trava nos locks consultivos do Postgres (a outra metade da chave é o id da conexão).
  ESPACO = 7131
  ESPERA_MAXIMA = 90.seconds

  class SemAVez < StandardError; end

  def self.call(connection, pedido_em:, &)
    new(connection, pedido_em).call(&)
  end

  def initialize(connection, pedido_em)
    @connection = connection
    @pedido_em = pedido_em
  end

  def call
    obtida = tentar
    seguir_sem_a_vez unless obtida
    yield
  ensure
    liberar if obtida
  end

  private

  def tentar
    banco.select_value(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_try_advisory_lock(?, ?)', ESPACO, @connection.id]))
  end

  def liberar
    banco.select_value(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_unlock(?, ?)', ESPACO, @connection.id]))
  end

  def seguir_sem_a_vez
    raise SemAVez, "connection=#{@connection.id}" if @pedido_em.present? && @pedido_em > ESPERA_MAXIMA.ago

    Rails.logger.warn("[autonomia][insurance] abertura sem a vez connection=#{@connection.id} espera=#{ESPERA_MAXIMA.to_i}s")
  end

  def banco
    ActiveRecord::Base.connection
  end
end
