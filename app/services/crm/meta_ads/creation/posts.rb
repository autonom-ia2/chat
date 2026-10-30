# Posts para impulsionar (#2198 PR 2, #2339), no formato que a tela mostra. A Página vem de
# Crm::MetaAds::Creation::Options.pages (as que o token alcança), nunca do pedido.
#
# - Página: posts publicados, lidos com o token da Página. Pode impulsionar quando `is_eligible_for_promotion` é true
#   (a Meta não diz o motivo). Foto de perfil ou de capa nunca: a Meta recusa no criar (#1487472, 28/10), então sai
#   apagada com o motivo `profile_or_cover`, mesmo que a Meta diga que pode.
# - Instagram: mídias da conta ligada à Página. Pode impulsionar só com `boost_eligibility_info.eligible_to_boost`
#   true; a doc da Meta não lista os subcampos (o nome vem da biblioteca restfb): confirmar na chamada real.
# - Falha ao ler um dos lados: lista vazia e `posts_error`, para a tela dizer que não conseguiu ler, nunca "sem posts".
class Crm::MetaAds::Creation::Posts
  SOURCES = %w[instagram facebook].freeze
  PROFILE_OR_COVER = %w[profile_media cover_photo].freeze
  READ_ERROR = 'posts_unreadable'.freeze

  def initialize(client)
    @client = client
  end

  def list(page)
    page_side = read_page_posts(page[:id])
    instagram_side = page[:instagram] ? read_instagram(page.dig(:instagram, :id)) : { ok: true, rows: [] }
    failed = !(page_side[:ok] && instagram_side[:ok])
    { posts: page_side[:rows], instagram_posts: instagram_side[:rows], posts_error: failed ? READ_ERROR : nil }
  end

  # O post escolhido, relido na hora: só um da Página ou do Instagram dela, e que a Meta deixa impulsionar.
  def find!(page, source, post_id)
    raise Crm::MetaAds::Creation::Error, 'invalid_post' unless SOURCES.include?(source) && post_id.present?

    post = read_side!(page, source).find { |row| row[:id] == post_id } || raise(Crm::MetaAds::Creation::Error, 'invalid_post')
    post[:eligible] ? post : raise(Crm::MetaAds::Creation::Error, 'post_not_eligible')
  end

  private

  def read_side!(page, source)
    side = source == 'facebook' ? read_page_posts(page[:id]) : read_instagram(page.dig(:instagram, :id))
    raise side[:error] unless side[:ok]

    side[:rows]
  end

  def read_page_posts(page_id)
    token = page_token(page_id)
    return failure(token) if token.is_a?(Meta::AdsGraphClient::Result)

    result = Meta::AdsGraphClient.new(access_token: token).boost_page_posts(page_id)
    result.ok ? { ok: true, rows: rows(result).map { |post| page_post(post) } } : failure(result)
  end

  # O token da Página, ou a resposta da Meta quando não veio.
  def page_token(page_id)
    result = @client.page_access_token(page_id)
    token = result.data.to_h['access_token'].presence if result.ok
    token || result
  end

  def read_instagram(instagram_user_id)
    return { ok: true, rows: [] } if instagram_user_id.blank?

    result = @client.boost_instagram_media(instagram_user_id)
    result.ok ? { ok: true, rows: rows(result).map { |media| instagram_post(media) } } : failure(result)
  end

  def failure(result)
    { ok: false, rows: [], error: Crm::MetaAds::Creation::Error.from_result(result) }
  end

  def rows(result)
    Array(result.data.to_h['data']).select { |row| row.is_a?(Hash) && row['id'].present? }
  end

  def page_post(post)
    profile_or_cover = Array(post.dig('attachments', 'data')).any? { |item| PROFILE_OR_COVER.include?(item.to_h['type']) }
    {
      id: post['id'].to_s, message: post['message'].to_s, created_time: utc_time(post['created_time']), image_url: post['full_picture'],
      reactions: post.dig('reactions', 'summary', 'total_count').to_i, comments: post.dig('comments', 'summary', 'total_count').to_i,
      eligible: post['is_eligible_for_promotion'] == true && !profile_or_cover, reason: profile_or_cover ? 'profile_or_cover' : nil
    }
  end

  # A Meta manda "+0000", que nem todo navegador lê; a tela recebe ISO 8601 em UTC e mostra o dia no fuso da conta.
  def utc_time(value)
    Time.zone.parse(value.to_s)&.utc&.iso8601
  end

  # A imagem que representa a mídia: a capa do vídeo, ou a própria foto.
  def cover_of(media)
    media['media_type'] == 'VIDEO' ? media['thumbnail_url'] : media['media_url']
  end

  def instagram_post(media)
    {
      id: media['id'].to_s, caption: media['caption'].to_s, timestamp: utc_time(media['timestamp']),
      image_url: cover_of(media) || cover_of(Array(media.dig('children', 'data')).first.to_h),
      likes: media['like_count'].to_i, comments: media['comments_count'].to_i,
      eligible: media.dig('boost_eligibility_info', 'eligible_to_boost') == true, reason: nil
    }
  end
end
