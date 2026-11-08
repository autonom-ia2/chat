# IA cuida dos comentários (#2454): a recusa da Meta que é só limite de chamadas, decidida pelo código numérico dela (ou
# pelo HTTP 429), nunca pelo texto. Limite não é recusa do privado: passa, e o job tenta de novo.
#
# Fonte: Graph API, "Rate Limiting" (https://developers.facebook.com/docs/graph-api/overview/rate-limiting): 4 (o app
# atingiu o limite), 17 (o usuário do token), 32 (chamadas à Página com token de usuário), 613 (limite personalizado) e
# os de caso de uso das superfícies em que o privado sai: 80001 (Página, com token da Página), 80002 (Instagram) e 80006
# (Messenger). A página "Error Handling" (https://developers.facebook.com/docs/graph-api/guides/error-handling) diz o
# mesmo de 4 e 17: "um problema temporário devido à limitação".
module Crm::MetaAds::ComentariosIa::LimiteDaMeta
  CODIGOS = [4, 17, 32, 613, 80_001, 80_002, 80_006].freeze
  HTTP = 429

  module_function

  def limite?(codigo:, http: nil)
    http.to_i == HTTP || CODIGOS.include?(Integer(codigo.to_s, exception: false))
  end

  # O envio do privado que não saiu (Rede::Envio).
  def do_envio?(envio)
    limite?(codigo: envio.codigo, http: envio.http)
  end
end
