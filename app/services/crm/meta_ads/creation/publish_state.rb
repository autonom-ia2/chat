# Onde está a publicação de um post numa rede, por chave de tentativa (#2198 PR 3, #2653). Post não tem pausa nem
# desfazer: na dúvida, nunca publica de novo sozinho. Fica no Redis por um dia:
#
# - trava (`:lock`, 2 minutos): só uma tentativa por chave e rede de cada vez; a outra recebe `in_progress`. Se o
#   processo cair, a trava vence sozinha.
# - `container`: o Instagram recebeu a mídia e ainda não publicou. A próxima tentativa segue com o mesmo contêiner.
# - `sent`: a chamada que publica saiu e não voltou resposta certa (rede, 5xx, queda do processo). Pode ter publicado:
#   a mesma chave responde `unconfirmed` e a pessoa confere no Instagram e no Facebook antes de publicar de novo.
# - `done`: publicado; guarda o que a tela mostra, e a mesma chave devolve isso sem chamar a Meta.
#
# A chave vale para um conteúdo só (Página, mídia e legenda): o mesmo id com outro conteúdo é `idempotency_conflict`.
class Crm::MetaAds::Creation::PublishState
  LOCK_TTL = 2.minutes
  KEEP_TTL = 1.day

  def initialize(account, key, network, digest)
    @state_key = "meta_ads:publish:#{account.id}:#{Digest::SHA256.hexdigest(key.to_s)}:#{network}"
    @lock_key = "#{@state_key}:lock"
    @digest = digest
    @saved = {}
    @locked = false
    @sent = false
    @owner = SecureRandom.uuid
  end

  # Toma a vez. Já publicado: devolve o post (com chaves em símbolo). Senão nil, e a tentativa segue.
  def claim!
    fail!('in_progress') unless Redis::Alfred.set(@lock_key, @owner, nx: true, ex: LOCK_TTL.to_i)
    @locked = true
    @saved = read
    return if @saved.empty?

    fail!('idempotency_conflict') unless @saved['digest'] == @digest
    fail!('unconfirmed') if @saved['state'] == 'sent'

    @saved['post'].deep_symbolize_keys if @saved['state'] == 'done'
  end

  def container
    @saved['container'].presence
  end

  def container!(id)
    write('state' => 'container', 'container' => id)
  end

  # Logo antes da chamada que publica: daqui em diante, falha sem resposta certa vira `unconfirmed`.
  def sending!
    write('state' => 'sent', 'container' => container)
    @sent = true
  end

  def sent?
    @sent
  end

  def done!(post)
    write('state' => 'done', 'post' => post)
  end

  # O contêiner quebrou na Meta: a próxima tentativa cria outro.
  def forget_container!
    @saved = @saved.except('container')
  end

  # Não publicou com certeza (recusa antes de publicar, ou recusa definitiva da própria publicação): libera a chave,
  # guardando o contêiner do Instagram, se houver.
  def not_published!
    return Redis::Alfred.delete(@state_key) if container.blank? || @sent

    write('state' => 'container', 'container' => container)
  end

  def unlock!
    # Só a própria trava: se ela venceu e outra tentativa pegou a vez, a dela fica.
    Redis::Alfred.delete_if_equals(@lock_key, @owner) if @locked
    @locked = false
  end

  private

  def write(value)
    @saved = value.merge('digest' => @digest)
    Redis::Alfred.set(@state_key, @saved.to_json, ex: KEEP_TTL.to_i)
  end

  def read
    JSON.parse(Redis::Alfred.get(@state_key).to_s)
  rescue JSON::ParserError
    {}
  end

  def fail!(code)
    raise Crm::MetaAds::Creation::Error, code
  end
end
