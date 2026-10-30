# Seus posts (#2302): os números da Página, os mesmos da aba de Anúncios (#2199), sem os melhores posts (a página lê
# todos os posts em SeusPosts::Posts).
class SeusPosts::NumerosPagina < Crm::MetaAds::Organico::Pagina
  include SeusPosts::Orcamento

  private

  def top_posts
    []
  end
end
