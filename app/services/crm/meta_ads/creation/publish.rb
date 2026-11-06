# Criar post (#2198 PR 3, #2653): publica na hora a foto ou o vídeo, com a legenda, na Página e/ou no Instagram dela.
# Post não tem pausa: é público assim que a Meta responde. Por isso:
#
# - Cada rede publica por conta própria. Falha numa não desfaz a outra: a resposta diz quais publicaram e quais não
#   (`failed`), e a pessoa tenta de novo só na que faltou, com a mesma chave. Nenhuma publicou: erro.
# - Chave por tentativa (`idempotency_key`), guardada por rede no Redis por um dia. Dois toques, ou outra tentativa
#   depois de cair a rede, devolvem o que já foi publicado e não publicam de novo. Enquanto uma publica: `in_progress`.
# - Só a Página que o token alcança (Crm::MetaAds::Creation::Options.pages); o Instagram é o ligado a ela. Cada rede
#   pede a sua permissão (Crm::MetaAds::Creation::Access#can_publish); sem ela, `cannot_publish` e nada chama a Meta.
# - Vídeo no Instagram: a Meta prepara o contêiner antes de publicar. Se não ficar pronto a tempo, o Instagram volta em
#   `failed` com `processing`, e o "Tentar de novo" segue com o mesmo contêiner (não sobe o vídeo de novo).
#
# Resposta: { facebook: { id:, permalink:, boostable: }, instagram: { id:, permalink:, boostable: }, failed: [...],
# errors: { rede => código }, published_now: [...] }. `id` é o que o impulsionar usa (post da Página ou mídia do
# Instagram). `published_now`: as redes que publicaram nesta chamada (fora as que a mesma chave já tinha publicado).
class Crm::MetaAds::Creation::Publish
  NETWORKS = %w[instagram facebook].freeze
  CAPTION_MAX = 2200
  KEY_MAX = 64
  KEY_TTL = 1.day
  CONTAINER_WAIT = { 'image' => 10, 'video' => 40 }.freeze
  POLL_EVERY = 2
  FINISHED = 'FINISHED'.freeze
  BROKEN = %w[ERROR EXPIRED].freeze

  def initialize(connection, pause: ->(seconds) { sleep(seconds) })
    @connection = connection
    @access = Crm::MetaAds::Creation::Access.new(connection)
    @pause = pause
  end

  def publish!(params)
    request = validate!(params)
    results = request[:networks].index_with { |network| attempt(request, network) }
    published, failed = results.partition { |_, result| result[:ok] }.map(&:to_h)
    raise Crm::MetaAds::Creation::Error, failed.values.first[:code] if published.empty?

    response(published, failed)
  end

  private

  def response(published, failed)
    published.to_h { |network, result| [network.to_sym, result[:post]] }
             .merge(failed: failed.keys, errors: failed.transform_values { |result| result[:code] },
                    published_now: published.reject { |_, result| result[:again] }.keys)
  end

  def validate!(params)
    key = params[:idempotency_key].to_s
    fail!('invalid_key') unless key.size.between?(1, KEY_MAX)
    networks = networks!(params[:networks])
    caption = params[:caption].to_s
    fail!('caption_too_long') if caption.size > CAPTION_MAX

    page = page!(params[:page_id].to_s)
    fail!('no_instagram') if networks.include?('instagram') && page[:instagram].blank?
    media = Crm::MetaAds::Creation::PostMedia.new(@connection.account).find!(params[:media_id])
    { key: key, networks: networks, caption: caption, page: page, media: media }
  end

  # As redes pedidas, cada uma com a permissão dela no token.
  def networks!(value)
    networks = Array(value).map(&:to_s).uniq
    fail!('invalid_networks') if networks.empty? || (networks - NETWORKS).any?
    allowed = @access.can_publish
    fail!('cannot_publish') unless networks.all? { |network| allowed[network] }
    networks
  end

  def page!(page_id)
    Crm::MetaAds::Creation::Options.pages(@access.client).find { |page| page[:id] == page_id } || fail!('invalid_page')
  end

  # Uma rede, uma vez por chave: o que já publicou volta igual; o que está publicando agora é `in_progress`.
  def attempt(request, network)
    state = Crm::MetaAds::Creation::PublishState.new(@connection.account, request[:key], network)
    done = state.claim!
    return { ok: true, post: done, again: true } if done

    post = network == 'facebook' ? facebook!(request) : instagram!(request, state)
    state.done!(post)
    { ok: true, post: post }
  rescue Crm::MetaAds::Creation::Error => e
    state.release! unless e.code == 'in_progress'
    { ok: false, code: e.code }
  end

  def facebook!(request)
    page_id = request[:page][:id]
    page_client = Meta::AdsGraphClient.new(access_token: page_token!(page_id))
    result = page_post(page_client, page_id, request[:media], request[:caption])
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    # Foto: `post_id` é o post da Página, que o impulsionar usa. Vídeo: a Meta devolve só o vídeo (impulsionar o post
    # do vídeo fica para a chamada real confirmar).
    post_id = result.data['post_id'].presence
    id = (post_id || result.data['id']).to_s
    { id: id, permalink: link(page_client, id, 'permalink_url'), boostable: post_id.present? }
  end

  def page_post(page_client, page_id, media, caption)
    return page_client.publish_page_photo(page_id, url: media[:url], message: caption) if media[:kind] == 'image'

    page_client.publish_page_video(page_id, file_url: media[:url], description: caption)
  end

  def instagram!(request, state)
    instagram_id = request[:page][:instagram][:id]
    container = state.container || container!(instagram_id, request)
    state.container!(container)
    wait_ready!(state, request[:media][:kind])
    result = @access.client.instagram_publish(instagram_id, container)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    { id: result.data['id'].to_s, permalink: link(@access.client, result.data['id'], 'permalink'), boostable: true }
  end

  def container!(instagram_id, request)
    media = request[:media]
    params = if media[:kind] == 'image'
               { image_url: media[:url], caption: request[:caption] }
             else
               { media_type: 'REELS', video_url: media[:url], caption: request[:caption] }
             end
    result = @access.client.instagram_container(instagram_id, params)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    result.data['id'].to_s
  end

  # Espera o contêiner ficar pronto. Quebrado: recusa (e a próxima tentativa cria outro). Sem ficar pronto a tempo:
  # `processing`, e o contêiner fica guardado para a próxima tentativa.
  def wait_ready!(state, kind)
    waited = 0
    loop do
      status = container_status(state.container)
      return if status == FINISHED

      broken!(state) if BROKEN.include?(status)
      raise Crm::MetaAds::Creation::Error, 'processing' if waited >= CONTAINER_WAIT.fetch(kind)

      @pause.call(POLL_EVERY)
      waited += POLL_EVERY
    end
  end

  def broken!(state)
    state.forget_container!
    fail!('meta_refused')
  end

  def container_status(container)
    result = @access.client.instagram_container_status(container)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    result.data['status_code'].to_s
  end

  def page_token!(page_id)
    result = @access.client.page_access_token(page_id)
    token = result.data.to_h['access_token'].presence if result.ok
    token || raise(Crm::MetaAds::Creation::Error.from_result(result))
  end

  # Sem o endereço, o post continua publicado: a tela só não mostra o link.
  def link(client, object_id, field)
    result = client.permalink(object_id, field)
    result.ok ? result.data[field].presence : nil
  end

  def fail!(code)
    raise Crm::MetaAds::Creation::Error, code
  end
end
