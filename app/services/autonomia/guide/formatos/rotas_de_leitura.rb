# As leituras do catálogo do Guia (`ler_da_conta`), cada uma com o controller e a action que a
# atendem (#942). O critério é o MESMO de `Consulta#catalogo` — GET e `Rotas.recurso` —, para os
# parâmetros nunca falarem de uma leitura que o Guia não vê, nem deixarem de fora uma que ele vê.
module Autonomia::Guide::Formatos::RotasDeLeitura
  Rota = ::Autonomia::Guide::Formatos::RotasDeEscrita::Rota

  module_function

  def todas
    Rails.application.routes.routes.filter_map { |rota| montar(rota) }.uniq(&:acao).sort_by(&:acao)
  end

  def montar(rota)
    return unless rota.verb.to_s == 'GET'

    recurso = ::Autonomia::Guide::Rotas.recurso(rota.path.spec.to_s.sub('(.:format)', ''))
    return unless recurso

    Rota.new(acao: recurso, controller: rota.defaults[:controller].to_s, action: rota.defaults[:action].to_s,
             partes: rota.required_parts.map(&:to_s))
  end
end
