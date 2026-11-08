# Seus posts (#2199): o que os posts da Página do Facebook e do Instagram alcançam, sem anúncio (Crm::MetaAds::Organico::Tela).
module Crm::MetaAds::Organico
  # A Meta falhou por outro motivo que não permissão nem token (rede, 5xx, limite, métrica recusada): a tela mostra
  # "Tentar de novo". `codigo`: o código de erro da Meta (ou o motivo nosso, como "recorte"), o que vai para o log, no
  # lugar da mensagem da Meta.
  class Indisponivel < StandardError
    attr_reader :codigo

    def initialize(message = nil, codigo: nil)
      super(message)
      @codigo = codigo
    end
  end

  # Versão da Graph em que as chamadas foram provadas com conta real (27/10/2026), na Página e no Instagram.
  API_VERSION = 'v23.0'.freeze
  INSTAGRAM_BASE_URI = 'https://graph.instagram.com'.freeze
end
