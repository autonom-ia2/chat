# #1430 — o `Idempotency-Key` de cada chamada da ferramenta HTTP. Não é o `call_id` do modelo: refazer o turno (o
# retry do `ReplyJob`) pede a ferramenta de novo com outro `call_id`, e o sistema do dono gravaria o pedido duas vezes.
# A chave é o resumo de conta, conversa, turno (a mensagem do cliente que o abriu — `Delivery#turno`), ferramenta e
# argumentos com as chaves em ordem: o mesmo pedido no mesmo turno dá a mesma chave; outra conversa, outra
# mensagem, outra ferramenta ou outro valor dão outra. Resumo, e não o texto: os argumentos não vão em claro.
# Sem turno (o botão Testar), cada chamada é um pedido novo.
module Autonomia::Agents::Tools::ChaveDeIdempotencia
  module_function

  def para(tool:, delivery:, params:)
    return nova if delivery&.conversation.nil?

    partes = [tool.account_id, delivery.conversation.id, delivery.turno, tool.id, em_ordem(params.to_h)]
    OpenSSL::Digest::SHA256.hexdigest(JSON.generate(partes))
  end

  def nova
    SecureRandom.hex(32)
  end

  def em_ordem(valor)
    case valor
    when Hash then valor.to_h { |chave, item| [chave.to_s, em_ordem(item)] }.sort.to_h
    when Array then valor.map { |item| em_ordem(item) }
    else valor
    end
  end
end
