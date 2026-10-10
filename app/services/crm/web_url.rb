# Link que vai parar num href público (link do agente, local da reunião): só http/https com host e tamanho limitado,
# para que `javascript:`, `data:` e afins nunca cheguem à tela.
module Crm::WebUrl
  def self.valid?(value, max: 500)
    text = value.to_s
    return false if text.empty? || text.length > max

    uri = URI.parse(text)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
