# Criar post (#2198 PR 3, #2653): publica na hora a foto ou o vídeo, com a legenda, na Página e/ou no Instagram dela.
# Post não tem pausa nem desfazer: é público assim que a Meta responde. Por isso:
#
# - Cada rede publica por conta própria. Falha numa não desfaz a outra: a resposta diz quais publicaram e quais não
#   (`failed`), e a pessoa tenta de novo só na que faltou, com a mesma chave. Nenhuma publicou: erro.
# - Chave por tentativa (`idempotency_key`), por rede (Crm::MetaAds::Creation::PublishState). Na dúvida, nunca publica
#   de novo sozinho: se a chamada que publica saiu e não voltou resposta certa (rede, 5xx, queda), a mesma chave
#   responde `unconfirmed`, e a pessoa confere na rede antes de publicar outra vez (com chave nova).
# - Só a Página que o token alcança (Crm::MetaAds::Creation::Options.pages); o Instagram é o ligado a ela. Cada rede
#   pede a sua permissão (Crm::MetaAds::Creation::Access#can_publish); sem ela, `cannot_publish` e nada chama a Meta.
# - Instagram: a Meta prepara o contêiner antes de publicar. A requisição não fica esperando: a foto ganha poucos
#   segundos; vídeo que não está pronto volta em `failed` com `processing`, e o "Tentar de novo" segue com o mesmo
#   contêiner (não sobe o vídeo de novo). Contêiner que já aparece publicado é `unconfirmed`.
#
# Resposta: { facebook: { id:, permalink:, boostable: }, instagram: { id:, permalink:, boostable: }, failed: [...],
# errors: { rede => código }, published_now: [...] }. `id` é o que o impulsionar usa (post da Página ou mídia do
# Instagram). `published_now`: as redes que publicaram nesta chamada (fora as que a mesma chave já tinha publicado).
class Crm::MetaAds::Creation::Publish
  NETWORKS = %w[instagram facebook].freeze
  CAPTION_MAX = 2200
  KEY_MAX = 64
  # Quanto a requisição espera o contêiner do Instagram (segundos). Vídeo não espera: confere uma vez.
  CONTAINER_WAIT = { 'image' => 4, 'video' => 0 }.freeze
  POLL_EVERY = 2
  FINISHED = 'FINISHED'.freeze
  ALREADY_PUBLISHED = 'PUBLISHED'.freeze
  BROKEN = %w[ERROR EXPIRED].freeze
  # Recusas da trava: a tentativa não chegou a mexer no estado.
  CLAIM_REFUSALS = %w[in_progress idempotency_conflict unconfirmed].freeze

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
    { key: key, networks: networks, caption: caption, page: page, media: media, digest: digest(page, params[:media_id], caption) }
  end

  # O conteúdo que a chave promete: a mesma chave com outro conteúdo é recusada (Crm::MetaAds::Creation::PublishState).
  def digest(page, media_id, caption)
    Digest::SHA256.hexdigest([page[:id], media_id.to_s, caption].to_json)
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
    state = Crm::MetaAds::Creation::PublishState.new(@connection.account, request[:key], network, request[:digest])
    done = state.claim!
    return { ok: true, post: done, again: true } if done

    { ok: true, post: publish_on(network, request, state) }
  rescue Crm::MetaAds::Creation::Error => e
    { ok: false, code: settle(state, e.code) }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @connection.account).capture_exception
    { ok: false, code: settle(state, 'meta_unavailable') }
  ensure
    state&.unlock!
  end

  # Publicado: grava antes de buscar o link, para uma queda depois daqui nunca virar outra publicação.
  def publish_on(network, request, state)
    client, post = network == 'facebook' ? facebook!(request, state) : instagram!(request, state)
    state.done!(post)
    post = post.merge(permalink: link(client, post[:id], network == 'facebook' ? 'permalink_url' : 'permalink'))
    state.done!(post)
    post
  end

  # A chamada que publica saiu e a resposta não é uma recusa certa: pode ter publicado (`unconfirmed`, e a chave fica
  # presa). Recusa certa, ou falha antes de publicar: a chave fica livre para tentar de novo.
  def settle(state, code)
    return code if state.nil? || CLAIM_REFUSALS.include?(code)
    return 'unconfirmed' if state.sent? && code != 'meta_refused'

    state.not_published!
    code
  end

  def facebook!(request, state)
    page_id = request[:page][:id]
    page_client = Meta::AdsGraphClient.new(access_token: page_token!(page_id))
    state.sending!
    result = page_post(page_client, page_id, request[:media], request[:caption])
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    # Foto: `post_id` é o post da Página, que o impulsionar usa. Vídeo: a Meta devolve só o vídeo (impulsionar o post
    # do vídeo fica para a chamada real confirmar).
    post_id = result.data['post_id'].presence
    [page_client, { id: (post_id || result.data['id']).to_s, boostable: post_id.present? }]
  end

  def page_post(page_client, page_id, media, caption)
    return page_client.publish_page_photo(page_id, url: media[:url], message: caption) if media[:kind] == 'image'

    page_client.publish_page_video(page_id, file_url: media[:url], description: caption)
  end

  def instagram!(request, state)
    instagram_id = request[:page][:instagram][:id]
    state.container!(container!(instagram_id, request)) unless state.container
    wait_ready!(state, request[:media][:kind])
    state.sending!
    result = @access.client.instagram_publish(instagram_id, state.container)
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    [@access.client, { id: result.data['id'].to_s, boostable: true }]
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

  # Espera o contêiner ficar pronto, pouco. Quebrado: recusa (e a próxima tentativa cria outro). Já publicado (outra
  # tentativa publicou e não gravou): `unconfirmed`. Sem ficar pronto: `processing`, com o contêiner guardado.
  def wait_ready!(state, kind)
    waited = 0
    loop do
      status = container_status(state.container)
      return if status == FINISHED

      already_published!(state) if status == ALREADY_PUBLISHED
      broken!(state) if BROKEN.include?(status)
      fail!('processing') if waited >= CONTAINER_WAIT.fetch(kind)

      @pause.call(POLL_EVERY)
      waited += POLL_EVERY
    end
  end

  def already_published!(state)
    state.sending!
    fail!('unconfirmed')
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
