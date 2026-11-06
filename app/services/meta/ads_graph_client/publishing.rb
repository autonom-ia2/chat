# Criar post (#2198 PR 3, #2653), parte do Meta::AdsGraphClient: publicar foto ou vídeo na Página e no Instagram.
# Mesmas regras de token, versão e limpeza de erro (usa o `get`/`post` privados dele).
#
# - Página: com o token da Página (pages_manage_posts). A Meta busca a mídia no endereço temporário (`url`/`file_url`).
# - Instagram: com o token do Facebook (instagram_content_publish). Dois passos: o contêiner (`/media`), que a Meta
#   processa, e o `media_publish`. Foto só JPEG; vídeo vai como Reels (o tipo VIDEO saiu da API).
module Meta::AdsGraphClient::Publishing
  INSTAGRAM_LIMIT_FIELDS = 'quota_usage,config'.freeze

  # Foto publicada na hora → { id, post_id }.
  def publish_page_photo(page_id, url:, message:)
    post("#{page_id}/photos", url: url, message: message, published: true)
  end

  # Vídeo comum na Página → { id }.
  def publish_page_video(page_id, file_url:, description:)
    post("#{page_id}/videos", file_url: file_url, description: description)
  end

  # Contêiner do post do Instagram → { id }.
  def instagram_container(instagram_user_id, params)
    post("#{instagram_user_id}/media", params)
  end

  # { status_code: IN_PROGRESS | FINISHED | ERROR | EXPIRED | PUBLISHED }
  def instagram_container_status(container_id)
    get(container_id.to_s, fields: 'status_code')
  end

  # Publica o contêiner → { id } (a mídia do Instagram).
  def instagram_publish(instagram_user_id, container_id)
    post("#{instagram_user_id}/media_publish", creation_id: container_id)
  end

  # Quantos posts a conta já publicou nas últimas 24 horas e o teto → { data: [{ quota_usage, config: { quota_total } }] }.
  def instagram_publishing_limit(instagram_user_id)
    get("#{instagram_user_id}/content_publishing_limit", fields: INSTAGRAM_LIMIT_FIELDS)
  end

  # O endereço público do que foi publicado (`permalink` no Instagram, `permalink_url` na Página).
  def permalink(object_id, field)
    get(object_id.to_s, fields: field)
  end
end
