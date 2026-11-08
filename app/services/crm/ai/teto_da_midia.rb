# O teto de leituras de mídia por conta por dia (Crm::Ai::LeitorDeMidia::MAX_LEITURAS_POR_DIA), num contador do Redis por
# dia UTC. Conta toda tentativa que chamou a leitura, inclusive a que falhou (#2109: em dia de API lenta, o gasto tem
# limite); só a que não chegou a ler (arquivo ainda fora do storage) é devolvida.
class Crm::Ai::TetoDaMidia
  VALIDADE = 2.days

  def initialize(account)
    @chave = "crm:leitor_de_midia:#{account.id}:#{Time.current.utc.to_date.iso8601}"
  end

  # Soma uma leitura. INCR e EXPIRE juntos (MULTI): a chave nunca fica sem validade.
  def somar
    total, = Redis::Alfred.with do |conn|
      conn.multi do |fila|
        fila.incr(@chave)
        fila.expire(@chave, VALIDADE.to_i)
      end
    end
    total
  end

  def devolver = Redis::Alfred.with { |conn| conn.decr(@chave) }

  def usado = Redis::Alfred.get(@chave).to_i
end
