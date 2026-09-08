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
  # QUEM ESCREVE ESTE TEXTO É O CÓDIGO, e não o modelo — de propósito: preço redigido por modelo é
  # preço que ele pode arredondar, trocar de seguradora ou inventar. O custo dessa escolha é que a
  # instrução ("negrito no nome e no valor") não alcança aqui; a formatação tem que ser feita nesta
  # linha. Até 08/09/2026 não era, e o cliente lia `Usebens: R$ 2837,70` numa lista corrida.
  #
  # NEGRITO DO WHATSAPP É ASTERISCO SIMPLES. Não há conversão de markdown na saída (a mensagem vai
  # crua em `outgoing_content`), então `**nome**` chegaria com os asteriscos à mostra.
  def self.describe(offers, first:, aviso: nil)
    corpo = "#{abertura(first, offers.size)}\n\n#{offers.map { |offer| item(offer) }.join("\n\n")}"
    aviso ? "#{corpo}\n\n#{aviso}" : corpo
  end

  # Um item por oferta: nome e valor na primeira linha, o que qualifica aquele valor na segunda.
  def self.item(offer)
    premium = ::Autonomia::Insurance::PremiumText.new(offer['premium'])
    linha = "• *#{nome(offer)}* — #{premium.resumo}"
    detalhe = premium.detalhe
    detalhe ? "#{linha}\n  #{detalhe}" : linha
  end

  # O NOME VEM DO PORTAL e é interpolado dentro do negrito. Um `*` no meio fecha o negrito cedo e o
  # resto do nome vaza com asterisco à mostra; uma quebra de linha desmonta o marcador. Nenhuma das
  # duas apareceu ainda — e nenhuma das duas é nossa para garantir que não apareça.
  def self.nome(offer)
    offer.dig('insurer', 'name').to_s.tr("*\n\r", ' ').squeeze(' ').strip
  end

  # Sem telegrafar o mecanismo. "Primeiros preços que chegaram" e "Chegaram mais opções" descrevem
  # a nossa fila de entrega, que não é assunto de quem está comprando seguro.
  def self.abertura(first, quantas)
    return first ? 'Primeiros preços:' : 'Mais uma opção:' if quantas == 1

    first ? 'Primeiros preços:' : "Mais #{quantas} opções:"
  end
end
