# Onde está a publicação de um post numa rede, por chave de tentativa (#2198 PR 3, #2653). Fica no Redis:
#
# - `running`: publicando agora. Vale 5 minutos, para um processo que caiu não travar a chave pelo dia inteiro.
# - `container`: o Instagram recebeu o vídeo, mas ainda não publicou. A próxima tentativa segue com o mesmo contêiner
#   (a Meta não publica o mesmo contêiner duas vezes).
# - `done`: publicado; guarda o que a tela mostra, para a mesma chave nunca publicar de novo.
class Crm::MetaAds::Creation::PublishState
  RUNNING_TTL = 5.minutes
  KEEP_TTL = 1.day

  def initialize(account, key, network)
    @redis_key = "meta_ads:publish:#{account.id}:#{Digest::SHA256.hexdigest(key.to_s)}:#{network}"
    @container = nil
  end

  attr_reader :container

  # Toma a vez. Já publicado: devolve o post. Outra tentativa publicando agora: `in_progress`.
  def claim!
    return if write({ state: 'running' }, only_new: true, ttl: RUNNING_TTL)

    saved = read
    return saved['post'].symbolize_keys if saved['state'] == 'done'
    raise Crm::MetaAds::Creation::Error, 'in_progress' unless saved['state'] == 'container'

    @container = saved['container']
    write({ state: 'running', container: @container }, ttl: RUNNING_TTL)
    nil
  end

  def container!(id)
    @container = id
    write({ state: 'running', container: id }, ttl: RUNNING_TTL)
  end

  # O contêiner quebrou na Meta: a próxima tentativa cria outro.
  def forget_container!
    @container = nil
  end

  def done!(post)
    write({ state: 'done', post: post }, ttl: KEEP_TTL)
  end

  # Não publicou: libera a chave, guardando o contêiner do Instagram, se houver, para a próxima tentativa.
  def release!
    return Redis::Alfred.delete(@redis_key) if @container.blank?

    write({ state: 'container', container: @container }, ttl: KEEP_TTL)
  end

  private

  def write(value, ttl:, only_new: false)
    Redis::Alfred.set(@redis_key, value.to_json, nx: only_new, ex: ttl.to_i)
  end

  def read
    JSON.parse(Redis::Alfred.get(@redis_key).to_s)
  rescue JSON::ParserError
    {}
  end
end
