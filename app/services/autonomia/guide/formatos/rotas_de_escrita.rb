# As ações do catálogo do Guia, cada uma com o controller e a action que a
# atendem (#900).
#
# O critério é o MESMO de `Acoes#catalogo` — verbos de escrita e
# `Rotas.recurso` —, para o formato nunca falar de uma ação que o Guia não vê,
# nem deixar de fora uma que ele vê. A diferença é guardar o que o catálogo
# joga fora: o controller#action e os segmentos que vêm do endereço, que não
# são corpo.
module Autonomia::Guide::Formatos::RotasDeEscrita
  Rota = Struct.new(:acao, :controller, :action, :partes, keyword_init: true)

  module_function

  def todas
    Rails.application.routes.routes.filter_map { |rota| montar(rota) }.uniq(&:acao).sort_by(&:acao)
  end

  def montar(rota)
    verbo = rota.verb.to_s
    return unless ::Autonomia::Guide::Acoes::VERBOS.include?(verbo)
    return if rota.defaults[:controller].blank?

    recurso = ::Autonomia::Guide::Rotas.recurso(rota.path.spec.to_s.sub('(.:format)', ''))
    return unless recurso

    Rota.new(acao: "#{verbo} #{recurso}", controller: rota.defaults[:controller], action: rota.defaults[:action],
             partes: rota.required_parts.map(&:to_s))
  end
end
