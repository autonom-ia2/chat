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
  # NÃO EXISTE TETO DE OFERTAS, E ISSO É DECISÃO DE PRODUTO.
  #
  # Havia um: as 3 mais baratas. E não eram 3 por lote — era `.first(3)` sobre a lista inteira, então
  # de 17 seguradoras que cotam, o cliente via 3 e as outras 14 nunca apareciam. A corretora paga
  # pelas 17.
  #
  # Rodrigo removeu em 10/09/2026, pela mesma régua que tirou o teto de execuções: quem paga é a
  # corretora, e esconder o que ela pagou é jogar fora valor que já foi comprado. Também tirava do
  # cliente a opção de escolher pela marca que ele conhece, e não só pelo preço.
  #
  # A entrega em lotes continua fazendo o trabalho de não afogar ninguém: `build_progress` só manda
  # o que CHEGOU desde a última vez, então o cliente recebe aos poucos, na ordem em que as
  # seguradoras respondem, e não uma tabela de 17 linhas de uma vez.
  #
  # `quote_offers_spec` guarda a decisão: 17 ofertas entram, 17 saem.

  def initialize(result)
    @result = result.to_h
  end

  # SÓ quem cotou. Todas. Da mais barata para a mais cara ENTRE AS QUE TÊM PERÍODO; as sem período
  # vêm depois, na ordem em que o portal as devolveu.
  #
  # ENTREGA 13, termo 5: preço de período desconhecido não se ordena pelo número cru. A Bp Assinatura
  # (351,59, sem parcelamento no payload) abria a lista na frente da Porto (1.321,25 no total) como
  # se fosse a mais barata — e se 351,59 for mensalidade, é a mais cara. Não há como normalizar o que
  # não tem período; então ele não entra na comparação, e a ressalva colada na oferta diz por quê.
  #
  # UM PREDICADO SÓ para "tem período": o mesmo `PremiumText#indefinido?` que dispara a ressalva no
  # texto e o registro no handle. Havia dois critérios em dois lugares (`basis == 'total'` aqui,
  # `!total?` lá) sem nada que os prendesse; bastava um `basis` nil (conector que não seja o Http do
  # AGGER, payload sem `basis`) e a oferta era ordenada entre os totais pelo número cru enquanto o
  # cliente lia a ressalva e o handle a registrava como sem período — a lista e a frase discordando
  # sobre a mesma oferta.
  def quoted
    @quoted ||= begin
      cotadas = Array(@result['offers'])
                .select { |offer| offer['status'] == 'quoted' && offer.dig('premium', 'amount').present? }
      sem_periodo, com_periodo = cotadas.partition { |offer| self.class.sem_periodo?(offer) }
      com_periodo.sort_by { |offer| offer.dig('premium', 'amount').to_f } + sem_periodo
    end
  end

  def self.sem_periodo?(offer)
    ::Autonomia::Insurance::PremiumText.new(offer['premium']).indefinido?
  end

  # -> { codigo da seguradora => motivo }. ENTREGA 13, termo 1: quando não sabemos o período, o
  # motivo fica registrado por oferta e diz qual campo do portal faltou ou veio ambíguo. É o
  # `basis_evidence` do adapter, sem tradução — traduzir seria pôr palavra nossa no lugar do dado.
  def sem_periodo
    quoted.select { |offer| self.class.sem_periodo?(offer) }.each_with_object({}) do |offer, motivos|
      motivos[self.class.code(offer)] = ::Autonomia::Insurance::PremiumText.new(offer['premium']).motivo
    end
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
