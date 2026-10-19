# Lock por caixa de e-mail com dono (#1870), na mesma chave da importação (Redis::Alfred::EMAIL_MESSAGE_MUTEX, que o
# Inboxes::FetchImapEmailsJob segura com o Redis::LockManager por até 5 min). Quem pega grava um token próprio; quem
# solta ou renova só mexe se o token ainda for o seu (WATCH/MULTI, Redis::Alfred.delete_if_equals). O job do lido nunca
# apaga nem estica o lock da importação. O Redis::LockManager do Chatwoot fica como está.
# O TTL é renovado a cada passo da escrita (`renovar!`); se o lock não é mais nosso (passou do TEMPO e outro pegou),
# LockPerdido para o trabalho antes do passo seguinte.
class ConversaCanal::LockDaCaixa
  class LockPerdido < MutexApplicationJob::LockAcquisitionError; end

  # Um passo: conectar (open_timeout do Net::IMAP é 30 s) e autenticar com a renovação do token, ou a escrita de uma
  # conversa (uma busca, um FETCH de cabeçalhos, um STORE). 90 s cobrem um passo com folga; o job renova entre passos.
  TEMPO = 90.seconds

  def self.chave(inbox)
    format(Redis::Alfred::EMAIL_MESSAGE_MUTEX, inbox_id: inbox.id)
  end

  # Executa o bloco com o lock da caixa (o bloco recebe o lock, para renovar); ocupada,
  # MutexApplicationJob::LockAcquisitionError.
  def self.com_lock(inbox)
    lock = new(chave(inbox))
    raise MutexApplicationJob::LockAcquisitionError, "caixa ocupada: #{lock.chave}" unless lock.pegar

    begin
      yield lock
    ensure
      lock.soltar
    end
  end

  attr_reader :chave

  def initialize(chave)
    @chave = chave
    @token = SecureRandom.hex(16)
  end

  def pegar
    Redis::Alfred.set(@chave, @token, nx: true, ex: TEMPO.to_i)
  end

  def soltar
    Redis::Alfred.delete_if_equals(@chave, @token)
  end

  def renovar!
    raise LockPerdido, "lock perdido: #{@chave}" unless renovar
  end

  # Estica o TTL só se o lock ainda é nosso. Devolve false se não é mais.
  def renovar
    Redis::Alfred.with do |conn|
      conn.watch(@chave) do
        next conn.unwatch && false unless conn.get(@chave) == @token

        conn.multi { |transacao| transacao.expire(@chave, TEMPO.to_i) }.present?
      end
    end
  end
end
