# Seus posts (#2302): os números do perfil do Instagram, os mesmos da aba de Anúncios (#2199), sem os melhores posts:
# a página lê todos os posts em SeusPosts::Posts e não precisa das chamadas de alcance por post daquela lista.
class SeusPosts::NumerosInstagram < Crm::MetaAds::Organico::Instagram
  include SeusPosts::Orcamento

  private

  def top_posts
    []
  end
end
