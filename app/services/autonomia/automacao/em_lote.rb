# A troca em lote pela Lista do CRM (Crm::Cards::BulkAction) grava card a card, e cada card commita sozinho: o gate do
# emissor (Escuta.assinante?) e a conta do Crm::Webhooks::Emitter rodariam uma vez por card, dentro do pedido (#2750,
# revisão). Dentro de `durante`, a resposta de cada um é lembrada pela chave e vale para os cards seguintes do mesmo
# lote; o lote é um pedido só, e nele ninguém liga nem desliga automação. Fora de `durante`, nada é lembrado: o gate
# continua sem cache, porque a lista muda a cada automação ligada ou desligada.
class Autonomia::Automacao::EmLote < ActiveSupport::CurrentAttributes
  attribute :lembrado

  def self.durante(&)
    return yield if lembrado

    set(lembrado: {}, &)
  end

  def self.lembrar(chave)
    return yield unless lembrado

    lembrado.fetch(chave) { lembrado[chave] = yield }
  end
end
