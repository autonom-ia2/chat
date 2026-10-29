# Parâmetros que vão no endereço de quem clica num anúncio da Meta (#1011, #2345). As chaves {{...}} são macros da
# Meta, preenchidas por ela em cada clique. Fonte única: a tela Conexão › Destino manda colar este texto nos anúncios
# feitos fora daqui, e o anúncio de site que o Chat2You cria já sai com ele em `url_tags`. A doc da Meta não lista
# `url_tags` entre os campos que se atualizam no criativo: por isso vai na criação.
module Crm::MetaAds::UrlTags
  TEXT = 'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}' \
         '&utm_content={{ad.name}}&utm_id={{campaign.id}}'.freeze
end
