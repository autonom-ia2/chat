# O que muda numa cotação de auto quando o cliente JÁ TEM seguro.
#
# Até a entrega 2 (10/09/2026) esta classe traduzia três parâmetros planos (`renovacao`, `bonus`,
# `sinistros`) para o bloco `quotation` do adapter, e ensinava a regra do bônus na descrição de
# cada um. Agora o bloco `quotation` chega inteiro do modelo, na forma do adapter — com a
# seguradora anterior, o número e a vigência da apólice, que antes não tinham onde ser escritos e
# faziam toda renovação voltar vazia (17 recusas, medido) —, e quem ensina e quem valida é o
# adapter. O que sobra aqui é o que só o chat2you decide: o AVISO de renovação sem bônus, que sai
# junto do primeiro preço.
class Autonomia::Insurance::AutoRenewal
  def initialize(params)
    @quotation = params.to_h.deep_stringify_keys['quotation'].to_h
  end

  def renovacao?
    ActiveModel::Type::Boolean.new.cast(@quotation['isRenewal']).present?
  end

  def bonus
    @quotation['bonusClass']
  end

  # Renovação sem a classe de bônus: cota como quem faz o primeiro seguro. O aviso ao cliente é
  # da ferramenta (`AVISO_SEM_BONUS`); aqui é só o fato.
  def sem_bonus?
    renovacao? && bonus.nil?
  end
end
