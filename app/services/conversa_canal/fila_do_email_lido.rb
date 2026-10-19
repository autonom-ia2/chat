# Fila do "lido" do e-mail por caixa (#1870), no Redis. O painel junta os pedidos (ação + conversa) de uma caixa e um job
# só, por caixa, escreve todos numa conexão (ConversaCanal::EmailLidoNoServidorJob): aberturas seguidas viram um job, e
# a importação da caixa não perde minutos esperando o lock por causa do lido.
# - O job tira os pedidos da fila ANTES de escrever (`retirar`, SPOP atômico) e devolve os que não escreveu (`devolver`).
#   Um pedido igual que chega durante a escrita entra de novo na fila e não se perde.
# - A marca de "job agendado" dura o teto da espera pelo lock: enquanto um job espera a caixa, os pedidos novos entram
#   na fila dele em vez de agendar outro.
class ConversaCanal::FilaDoEmailLido
  SEPARADOR = ':'.freeze
  VALIDADE = 1.day

  def initialize(inbox_id)
    @inbox_id = inbox_id
  end

  def adicionar(conversation_id, acao)
    devolver([[acao, conversation_id]])
  end

  # true para quem deve agendar o job da caixa (ninguém agendado agora).
  def agendar?(validade)
    Redis::Alfred.set(chave_do_job, '1', nx: true, ex: validade.to_i)
  end

  def soltar_agendamento
    Redis::Alfred.delete(chave_do_job)
  end

  # Tira da fila até `limite` pedidos: [[acao, conversation_id], ...].
  def retirar(limite)
    membros = Redis::Alfred.with { |conn| conn.spop(chave_da_fila, limite) }
    Array(membros).map { |membro| ler(membro) }
  end

  def devolver(pedidos)
    return if pedidos.empty?

    Redis::Alfred.with do |conn|
      conn.sadd(chave_da_fila, pedidos.map { |acao, conversation_id| [acao, conversation_id].join(SEPARADOR) })
      conn.expire(chave_da_fila, VALIDADE.to_i)
    end
  end

  # Os pedidos na fila, sem tirar: [[acao, conversation_id], ...].
  def pedidos
    Redis::Alfred.with { |conn| conn.smembers(chave_da_fila) }.map { |membro| ler(membro) }
  end

  # O painel não conseguiu agendar o job: o pedido sai (não fica parado sem job).
  def remover(conversation_id, acao)
    Redis::Alfred.with { |conn| conn.srem(chave_da_fila, [acao, conversation_id].join(SEPARADOR)) }
  end

  def pendente?
    Redis::Alfred.with { |conn| conn.scard(chave_da_fila) }.positive?
  end

  # O job desistiu: tira tudo da fila e solta o agendamento no mesmo MULTI (nenhum pedido entra entre um e outro sem
  # conseguir agendar o próprio job) e devolve os pedidos tirados.
  def esvaziar
    membros, = Redis::Alfred.with do |conn|
      conn.multi do |transacao|
        transacao.smembers(chave_da_fila)
        transacao.del(chave_da_fila)
        transacao.del(chave_do_job)
      end
    end
    Array(membros).map { |membro| ler(membro) }
  end

  private

  def chave_da_fila
    "conversa_canal:email_lido:fila:#{@inbox_id}"
  end

  def chave_do_job
    "conversa_canal:email_lido:job:#{@inbox_id}"
  end

  def ler(membro)
    acao, conversation_id = membro.split(SEPARADOR, 2)
    [acao, conversation_id.to_i]
  end
end
