# IA cuida dos comentários (#2454): os endereços das imagens de um post, na ordem, para a leitura da foto (Foto). Só a
# imagem: o vídeo vai pela capa. Só endereço https, que é como a Meta entrega a mídia.
# - Instagram (`media_type`, `media_url`, `thumbnail_url` e `children` no carrossel);
# - Facebook (`attachments` com `subattachments` no álbum; sem anexo, a `full_picture`), até LIMITE, como o carrossel do
#   Instagram: proteção contra defeito (um álbum enorme não vira uma chamada enorme à IA).
module Crm::MetaAds::ComentariosIa::Imagens
  LIMITE = 10

  module_function

  def do_instagram(dados)
    filhos = Array(dados.dig('children', 'data'))
    (filhos.presence || [dados]).filter_map { |item| https(item['media_type'] == 'VIDEO' ? item['thumbnail_url'] : item['media_url']) }
  end

  def do_facebook(dados)
    urls = Array(dados.dig('attachments', 'data')).flat_map do |anexo|
      dentro = Array(anexo.dig('subattachments', 'data'))
      (dentro.presence || [anexo]).filter_map { |item| https(item.dig('media', 'image', 'src')) }
    end
    (urls.presence || [https(dados['full_picture'])].compact).first(LIMITE)
  end

  def https(url)
    url.to_s.start_with?('https://') ? url.to_s : nil
  end
end
