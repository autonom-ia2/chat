# Login único (#2338), parte do Meta::AdsGraphClient: o que o mesmo "Entrar com o Facebook" dos Anúncios traz além da
# conta de anúncios. As Páginas que a pessoa marcou na janela da Meta, cada uma com o Instagram ligado (só para mostrar:
# o Instagram continua no login dele). As permissões concedidas e recusadas vêm do `permissions` do próprio cliente.
module Meta::AdsGraphClient::LoginUnico
  LOGIN_PAGES_FIELDS = 'id,name,category,followers_count,instagram_business_account{id,username,followers_count}'.freeze

  def login_pages
    paged('me/accounts', fields: LOGIN_PAGES_FIELDS)
  end
end
