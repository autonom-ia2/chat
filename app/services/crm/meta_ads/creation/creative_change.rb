# A foto ou o texto novos de um anúncio criado aqui (#2778, Fluxo 5). A Meta não muda o criativo depois de criado: o
# criativo novo sai do de agora (`object_story_spec` relido na Meta), com o texto e, se veio, a mídia trocados. O resto
# (Página, Instagram, link, botão, mensagem pronta e os parâmetros de rastreio) fica como estava.
#
# Só foto única (`link_data` com `image_hash`) ou vídeo (`video_data` com `video_id`) trocam; foto por foto e vídeo por
# vídeo. Carrossel e post impulsionado não têm uma foto para trocar: `kind_of` dá nil, e a tela não oferece.
class Crm::MetaAds::Creation::CreativeChange
  TEXT_LIMIT = Crm::MetaAds::Creation::Draft::TEXT_LIMIT
  # Endereços que a Meta devolve ao ler e que brigariam com a mídia nova.
  READ_ONLY_IMAGE = %w[picture image_url].freeze

  attr_reader :values

  # { text, media? } como a tela manda. Sem `media`, fica a foto de agora.
  def self.from_params(raw)
    params = raw.to_h.with_indifferent_access
    text = params[:text].to_s.strip
    raise Crm::MetaAds::Creation::Error, 'invalid_params' if text.empty? || text.length > TEXT_LIMIT

    new(text: text, media: params[:media].present? ? Crm::MetaAds::Creation::Draft.media!(params[:media]) : nil)
  end

  # 'image', 'video' ou nil, pelo criativo como a Meta devolve.
  def self.kind_of(spec)
    spec = spec.to_h
    link = spec['link_data'].to_h
    return 'image' if link['image_hash'].present? && link['child_attachments'].blank?

    'video' if spec.dig('video_data', 'video_id').present?
  end

  # O texto de agora, pelo criativo lido.
  def self.text_of(source)
    spec = source.to_h['object_story_spec'].to_h
    spec.dig('link_data', 'message') || spec.dig('video_data', 'message')
  end

  def initialize(text:, media:)
    @values = { text: text, media: media }
  end

  # Os parâmetros do criativo novo, a partir do criativo lido (`object_story_spec` e `url_tags`).
  def creative_params(source, name:)
    spec = source.to_h['object_story_spec'].to_h.deep_dup
    kind = self.class.kind_of(spec)
    raise Crm::MetaAds::Creation::Error, 'invalid_creative' if kind.nil?
    raise Crm::MetaAds::Creation::Error, 'invalid_media' if media && media[:kind] != kind

    kind == 'image' ? change_image(spec['link_data']) : change_video(spec['video_data'])
    { name: name, object_story_spec: spec.to_json, url_tags: source['url_tags'].presence }.compact
  end

  private

  def media
    @values[:media]
  end

  def change_image(link)
    link['message'] = @values[:text]
    return unless media

    link.except!(*READ_ONLY_IMAGE)
    link['image_hash'] = media[:hash]
  end

  def change_video(video)
    video['message'] = @values[:text]
    return unless media

    video.delete('image_url')
    video.merge!('video_id' => media[:video_id], 'image_hash' => media[:image_hash])
  end
end
