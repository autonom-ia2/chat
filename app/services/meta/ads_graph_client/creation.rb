# Gerenciador simples (#2198), parte do Meta::AdsGraphClient: criar campanha, grupo, criativo e anúncio, subir foto e
# vídeo, ler e mudar orçamento e datas, e desfazer o que foi criado. Mesmas regras de token, versão e limpeza de erro
# (usa o `get`/`post`/`delete` privados dele). IDs de conta de anúncios entram sem o prefixo `act_`.
module Meta::AdsGraphClient::Creation
  # O anúncio com o grupo e a campanha: o orçamento fica num dos dois (no grupo, ou na campanha quando ela divide o
  # dinheiro entre os grupos). As datas ficam sempre no grupo.
  AD_BUDGET_FIELDS = 'id,account_id,adset{id,name,daily_budget,lifetime_budget,start_time,end_time,effective_status},' \
                     'campaign{id,name,daily_budget,lifetime_budget,effective_status}'.freeze
  PAGES_FIELDS = 'id,name,instagram_business_account{id,username}'.freeze
  IMAGE_FIELDS = 'hash,url,width,height'.freeze
  IMAGES_LIMIT = 30
  CAMPAIGNS_LIMIT = 25
  OBJECT_STATUS_FIELDS = 'status,effective_status'.freeze
  # Posts para impulsionar (PR 2, #2339): os mais recentes de cada lado, com o que diz se a Meta deixa promover. O tipo
  # do anexo separa a foto de perfil (`profile_media`) e a de capa (`cover_photo`), que a Meta recusa no criar.
  BOOST_POSTS_LIMIT = 25
  BOOST_PAGE_POST_FIELDS = 'id,message,created_time,full_picture,is_eligible_for_promotion,attachments{type},' \
                           'reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0)'.freeze
  # Carrossel pode vir sem `media_url`: a imagem do primeiro filho serve de capa.
  BOOST_INSTAGRAM_MEDIA_FIELDS = 'id,caption,timestamp,media_type,media_url,thumbnail_url,like_count,comments_count,' \
                                 'children{media_type,media_url,thumbnail_url},boost_eligibility_info'.freeze

  def create_campaign(ad_account_id, params)
    post("act_#{ad_account_id}/campaigns", params)
  end

  def create_adset(ad_account_id, params)
    post("act_#{ad_account_id}/adsets", params)
  end

  def create_creative(ad_account_id, params)
    post("act_#{ad_account_id}/adcreatives", params)
  end

  def create_ad(ad_account_id, params)
    post("act_#{ad_account_id}/ads", params)
  end

  # Foto em base64 → { images: { <nome>: { hash, url, width, height } } }.
  def upload_image(ad_account_id, bytes)
    post("act_#{ad_account_id}/adimages", bytes: bytes)
  end

  # Vídeo por endereço que a Meta consegue ler (o arquivo fica no nosso armazenamento) → { id }.
  def upload_video(ad_account_id, file_url)
    post("act_#{ad_account_id}/advideos", file_url: file_url)
  end

  # { status: { video_status: ready | processing | error } }
  def video_status(video_id)
    get(video_id.to_s, fields: 'status')
  end

  # Fotos já usadas na conta de anúncios, as mais recentes.
  def ad_images(ad_account_id)
    get("act_#{ad_account_id}/adimages", fields: IMAGE_FIELDS, limit: IMAGES_LIMIT)
  end

  # Páginas que a pessoa concedeu, com a conta do Instagram ligada a cada uma (todas as páginas da lista).
  def pages_with_instagram
    paged('me/accounts', fields: PAGES_FIELDS)
  end

  # Posts publicados da Página: pede o token da Página (pages_read_engagement).
  def boost_page_posts(page_id)
    get("#{page_id}/published_posts", fields: BOOST_PAGE_POST_FIELDS, limit: BOOST_POSTS_LIMIT)
  end

  # Mídias da conta do Instagram ligada à Página, com o token do Facebook (instagram_basic).
  def boost_instagram_media(instagram_user_id)
    get("#{instagram_user_id}/media", fields: BOOST_INSTAGRAM_MEDIA_FIELDS, limit: BOOST_POSTS_LIMIT)
  end

  def ad_budget(ad_id)
    get(ad_id.to_s, fields: AD_BUDGET_FIELDS)
  end

  # Anúncios de um grupo ou de uma campanha, só com a situação de entrega.
  def ads_of(object_id)
    paged("#{object_id}/ads", fields: 'effective_status')
  end

  def update_object(object_id, params)
    post(object_id.to_s, params)
  end

  def delete_object(object_id)
    request(:delete, object_id.to_s)
  end

  # Campanhas da conta cujo nome contém `text` (a marca da tentativa de criar), inclusive as que nunca ativaram.
  def campaigns_named(ad_account_id, text)
    get("act_#{ad_account_id}/campaigns", fields: 'id,name,effective_status', limit: CAMPAIGNS_LIMIT,
                                          filtering: [{ field: 'name', operator: 'CONTAIN', value: text }].to_json)
  end

  # Situação de uma campanha, grupo ou anúncio: a escolhida (`status`) e a de entrega (`effective_status`).
  def object_status(object_id)
    get(object_id.to_s, fields: OBJECT_STATUS_FIELDS)
  end

  # Estados do Brasil como a Meta os chama no público (`regions: [{ key }]`).
  def search_regions(name)
    get('search', type: 'adgeolocation', location_types: '["region"]', q: name, country_code: 'BR')
  end
end
