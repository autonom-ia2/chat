# O QUE O CLIENTE LÊ de uma cotação — e o que ele nunca lê.
#
# Separado da ferramenta porque é a regra de PRODUTO, e não de orquestração: decidir que uma recusa
# de risco não vira texto é decisão do PO, e ela não deveria mudar de lugar toda vez que o fluxo de
# polling muda.
#
# O que NÃO vai para o cliente (decisão do PO):
#   - seguradora que recusou o risco: não por iniciativa nossa. O cliente pediu preço, não
#     auditoria, e a recusa fala do bem e da região dele;
#   - credencial da corretora inválida numa seguradora: NUNCA, nem se perguntado. É problema nosso,
#     constrangedor e inútil para quem quer comprar. Vai para a tela de Conexões.
class Autonomia::Insurance::QuoteOffers
  # Quantas opções o cliente vê. O fluxo de referência mostra as 3 mais baratas; mais que isso vira
  # tabela e para de ajudar a decidir.
  MAX_OFFERS = 3

  def initialize(result)
    @result = result.to_h
  end

  # SÓ quem cotou, da mais barata para a mais cara, no máximo três.
  def quoted
    @quoted ||= Array(@result['offers'])
                .select { |offer| offer['status'] == 'quoted' && offer.dig('premium', 'amount').present? }
                .sort_by { |offer| offer.dig('premium', 'amount').to_f }
                .first(MAX_OFFERS)
  end

  # Seguradoras que recusaram a credencial que a corretora cadastrou NO PORTAL (critério 4.5).
  def credencial_pendente
    Array(@result['offers']).select { |offer| offer['status'] == 'auth_required' }
  end

  def self.code(offer)
    offer.dig('insurer', 'code').to_s
  end

  # Texto pronto para o cliente. A segunda mensagem se anuncia como complemento — sem isso ela
  # parece uma cotação nova e o cliente não sabe qual vale.
  def self.describe(offers, first:, aviso: nil)
    linhas = offers.map do |offer|
      "#{offer.dig('insurer', 'name')}: #{::Autonomia::Insurance::PremiumText.new(offer['premium'])}"
    end
    abertura = first ? 'Primeiros preços que chegaram:' : 'Chegaram mais opções:'
    corpo = "#{abertura}\n#{linhas.join("\n")}"
    corpo = "#{corpo}\n\n#{::Autonomia::Insurance::PremiumText::SEM_SIGNIFICADO}" if algum_indefinido?(offers)
    aviso ? "#{corpo}\n\n#{aviso}" : corpo
  end

  def self.algum_indefinido?(offers)
    offers.any? { |offer| ::Autonomia::Insurance::PremiumText.new(offer['premium']).indefinido? }
  end
end
