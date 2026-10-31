# #1430 — o `Idempotency-Key` de cada chamada da ferramenta HTTP. Não é o `call_id` do modelo: refazer o turno (o
# retry do `ReplyJob`) pede a ferramenta de novo com outro `call_id`, e o sistema do dono gravaria o pedido duas vezes.
# A chave junta conta, conversa, turno (a mensagem do cliente que o abriu — `Delivery#turno`), ferramenta e as
# informações JÁ TIPADAS (`ParamsTipados`), com as chaves em ordem: o mesmo pedido no mesmo turno dá a mesma chave,
# ainda que o modelo escreva `"1"` numa passada e `1` na outra; outra conversa, mensagem, ferramenta ou valor dá
# outra. A mesma chamada repetida DENTRO do turno é outro pedido ("mais um igual"): entra o número da ocorrência
# (`Delivery#ocorrencia`), que o turno refeito reproduz. HMAC com segredo da plataforma: quem vê a chave não deduz
# ids nem refaz o resumo de um CPF.
# Sem conversa (o botão Testar), cada chamada é um pedido novo.
module Autonomia::Agents::Tools::ChaveDeIdempotencia
  module_function

  # `turno`: o `Delivery` do turno (o do principal, também quando quem chama é o ajudante).
  def para(tool:, turno:, params:)
    return nova if turno.nil? || turno.conversation.nil?

    pedido = resumo([tool.account_id, turno.conversation.id, turno.turno, tool.id, em_ordem(params.to_h)])
    resumo([pedido, turno.ocorrencia(pedido)])
  end

  def resumo(partes)
    OpenSSL::HMAC.hexdigest('SHA256', segredo, JSON.generate(partes))
  end

  def nova
    SecureRandom.hex(32)
  end

  def segredo
    @segredo ||= Rails.application.key_generator.generate_key('autonomia/agents/tools/idempotency_key', 32)
  end

  def em_ordem(valor)
    case valor
    when Hash then valor.to_h { |chave, item| [chave.to_s, em_ordem(item)] }.sort.to_h
    when Array then valor.map { |item| em_ordem(item) }
    else valor
    end
  end
end
