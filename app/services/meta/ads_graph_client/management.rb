# Gestão mínima do anúncio (#2161), parte do Meta::AdsGraphClient: mesmas regras de token, versão e limpeza de erro
# (usa o `get`/`post` privados dele). A situação do próprio anúncio (`status`: ACTIVE, PAUSED…), a entrega de fato
# (`effective_status`: também CAMPAIGN_PAUSED, ADSET_PAUSED…), a conta de anúncios dona dele e o post da Página por
# trás do criativo. Do criativo também vêm a mídia do anúncio no Instagram e a conta do Instagram que o publica
# (comentários do Instagram, #2196). O nome vem sempre; quem usa é o detalhe do anúncio sem números, na confirmação de
# pausar e ativar (#2335).
module Meta::AdsGraphClient::Management
  AD_MANAGEMENT_FIELDS = 'id,name,account_id,status,effective_status,' \
                         'creative{effective_object_story_id,effective_instagram_media_id,instagram_permalink_url,instagram_user_id}'.freeze
  PAGE_POST_FIELDS = 'message,created_time,permalink_url,from{name},shares,' \
                     'reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0)'.freeze
  PAGES_LIMIT = 100

  def ad_management(ad_id)
    get(ad_id.to_s, fields: AD_MANAGEMENT_FIELDS)
  end

  # Pausar ou ativar o anúncio (ads_management).
  def update_ad_status(ad_id, status)
    post(ad_id.to_s, status: status)
  end

  # Post da Página (pages_read_engagement). O token da Página só quando o do cliente não lê o post direto.
  def page_post(post_id)
    get(post_id.to_s, fields: PAGE_POST_FIELDS)
  end

  def page_access_token(page_id)
    get(page_id.to_s, fields: 'access_token')
  end

  # Páginas que a pessoa concedeu ao entrar com o Facebook (pages_show_list).
  def pages
    get('me/accounts', fields: 'id,name', limit: PAGES_LIMIT)
  end
end
