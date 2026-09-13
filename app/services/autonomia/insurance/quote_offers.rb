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

  # SÓ quem cotou. Todas. Em TRÊS blocos, nesta ordem: os totais, da mais barata para a mais cara;
  # depois as assinaturas mensais, da mais barata para a mais cara ENTRE SI; por fim as sem período,
  # na ordem em que o portal as devolveu.
  #
  # ENTREGA 13, termo 5: preços de períodos diferentes NUNCA se ordenam pelo número cru entre si. A
  # Bp Assinatura (351,59, sem parcelamento no payload) abria a lista na frente da Porto (1.321,25 no
  # total) como se fosse a mais barata — e, sendo mensalidade, não é comparável ao total sem um
  # período comum. Mensal e total não se comparam sem uma conta nossa (×12 seria um número que o portal não deu, e é decisão de produto
  # pendente); então cada período é um bloco, e o sem período nem entra na comparação — a ressalva
  # colada na oferta diz por quê.
  #
  # UM PREDICADO SÓ para "tem período": o mesmo `PremiumText#indefinido?` que dispara a ressalva no
  # texto e o registro no handle. Havia dois critérios em dois lugares (`basis == 'total'` aqui,
  # `!total?` lá) sem nada que os prendesse; bastava um `basis` nil (conector que não seja o Http do
  # AGGER, payload sem `basis`) e a oferta era ordenada entre os totais pelo número cru enquanto o
  # cliente lia a ressalva e o handle a registrava como sem período — a lista e a frase discordando
  # sobre a mesma oferta. Pela mesma razão, "é mensal" também vem do `PremiumText`, e não de uma
  # leitura própria de `basis` aqui.
  def quoted
    @quoted ||= begin
      cotadas = Array(@result['offers'])
                .select { |offer| offer['status'] == 'quoted' && offer.dig('premium', 'amount').present? }
      sem_periodo, com_periodo = cotadas.partition { |offer| self.class.sem_periodo?(offer) }
      mensais, totais = com_periodo.partition { |offer| self.class.mensal?(offer) }
      por_valor(totais) + por_valor(mensais) + sem_periodo
    end
  end

  def self.sem_periodo?(offer)
    ::Autonomia::Insurance::PremiumText.new(offer['premium']).indefinido?
  end

  def self.mensal?(offer)
    ::Autonomia::Insurance::PremiumText.new(offer['premium']).mensal?
  end

  # -> { codigo da seguradora => motivo }. ENTREGA 13, termo 1: quando não sabemos o período, o
  # motivo fica registrado por oferta e diz qual campo do portal faltou ou veio ambíguo. É o
  # `basis_evidence` do adapter, sem tradução — traduzir seria pôr palavra nossa no lugar do dado.
  # A assinatura mensal TEM período (`monthly`) e fica de fora: registrá-la aqui diria ao handle que
  # o portal não informou o que ele informou em `packageType=1`.
  def sem_periodo
    quoted.select { |offer| self.class.sem_periodo?(offer) }.each_with_object({}) do |offer, motivos|
      motivos[self.class.code(offer)] = ::Autonomia::Insurance::PremiumText.new(offer['premium']).motivo
    end
  end

  # TODAS as seguradoras que o portal pôs nesta cotação, por código, sem repetir. É a unidade que a
  # corretora paga — "uma cotação" não diz nada sobre dinheiro, e o teto de "8 por hora" que saiu em
  # 10/09/2026 contava justamente a unidade errada (8 execuções eram até 136 consultas).
  #
  # QUALQUER STATUS CONTA, e isso foi MEDIDO, não escolhido. Em 11/09/2026, lendo por `agger quote
  # result` as três cotações reais da conta de teste: renovação 11 `quoted` + 6 `declined` = 17; moto
  # 2 + 15 = 17; caminhão 1 `quoted` + 15 `declined` + 1 `auth_required` = 17. Somar só
  # `quoted` + `declined` diria dezesseis no caminhão — uma seguradora a menos do que a corretora
  # acionou, e justamente a que ela precisa ver (credencial recusada, critério 4.5).
  #
  # Código vazio não entra: uma string vazia contaria como seguradora a mais na conta de quem paga.
  def acionadas
    Array(@result['offers']).filter_map { |offer| self.class.code(offer).presence }.uniq
  end

  # OS STATUS DE OFERTA QUE CONTAM COMO DESFECHO DA SEGURADORA, lidos em `toOffer` do adapter
  # (autonomia-adapters, `src/platforms/agger/http/quote.ts`): `quoted` sai com preço; `declined` e
  # `auth_required` saem assim que o cálculo traz erro; `error` só sai depois de o portal declarar o
  # negócio pronto. Sem preço e sem erro, com o negócio aberto, a oferta sai `running`. O contrato do
  # adapter lista outros status (`queued`, `timeout`, `not_configured`) que o AGGER não produz; eles
  # ficam fora desta lista, e uma oferta com um deles faz `todas_com_desfecho?` responder falso.
  DESFECHOS = %w[quoted declined auth_required error].freeze

  # -> true quando as três condições valem, nesta ordem:
  #   1. `ja_acionadas` (a lista que as leituras ANTERIORES gravaram no handle) não está vazia;
  #   2. todo código de `ja_acionadas` aparece nesta leitura (`acionadas`);
  #   3. toda oferta desta leitura tem status em `DESFECHOS`.
  # A 1 faz a primeira leitura responder falso. A 1 e a 2 juntas fazem a lista de ofertas vazia
  # responder falso: sem leitura anterior não passa a 1, e com ela nenhum código anterior está aqui.
  def todas_com_desfecho?(ja_acionadas)
    anteriores = Array(ja_acionadas).map(&:to_s)
    return false if anteriores.empty? || (anteriores - acionadas).any?

    Array(@result['offers']).all? { |offer| DESFECHOS.include?(offer['status']) }
  end

  # Seguradoras que recusaram a credencial que a corretora cadastrou NO PORTAL (critério 4.5).
  def credencial_pendente
    Array(@result['offers']).select { |offer| offer['status'] == 'auth_required' }
  end

  def self.code(offer)
    offer.dig('insurer', 'code').to_s
  end

  # AS TRÊS ABERTURAS, E NENHUMA DELAS DIZ QUANTAS. Sem telegrafar o mecanismo: "Primeiros preços que
  # chegaram" e "Chegaram mais opções" descrevem a nossa fila de entrega, que não é assunto de quem
  # está comprando seguro.
  #
  # `MAIS_PRECOS` nasceu nesta entrega. A abertura de um lote seguinte com mais de uma oferta era
  # `"Mais #{quantas} opções:"`, e a decisão do CEO de 12/09/2026 tirou número de toda frase que o
  # cliente lê. Sem uma constante sem número, o recuo do papel publicaria justamente o que a decisão
  # proíbe (`InsuranceQuote::Frases`).
  #
  # SÃO CONSTANTES DE RECUO, e quem escolhe entre as três é quem sabe o lote (`InsuranceQuote#precos`:
  # é o primeiro lote? quantas ofertas vieram?). Em produção quem as escreve é o especialista, no
  # pedido; estas são o que sai quando a frase dele não passa na peneira.
  PRIMEIROS_PRECOS = 'Primeiros preços:'.freeze
  MAIS_UM_PRECO = 'Mais uma opção:'.freeze
  MAIS_PRECOS = 'Mais opções:'.freeze

  # Texto pronto para o cliente: a abertura que quem chama resolveu, os itens, e o aviso quando há.
  # A segunda mensagem se anuncia como complemento — sem isso ela parece uma cotação nova e o cliente
  # não sabe qual vale.
  #
  # QUEM ESCREVE O ITEM É O CÓDIGO, e não o modelo — de propósito: preço redigido por modelo é preço
  # que ele pode arredondar, trocar de seguradora ou inventar. O custo dessa escolha é que a
  # instrução ("negrito no nome e no valor") não alcança aqui; a formatação tem que ser feita nesta
  # linha. Até 08/09/2026 não era, e o cliente lia `Usebens: R$ 2837,70` numa lista corrida.
  #
  # A ABERTURA E O AVISO CHEGAM PRONTOS, e é por isso que `first:` saiu daqui: desde 12/09/2026 as
  # duas são escritas pelo especialista no pedido, e este método não tem como saber qual papel é
  # qual. Ele compõe; quem escolhe o texto é `InsuranceQuote::Frases`.
  def self.describe(offers, abertura:, aviso: nil)
    corpo = "#{abertura}\n\n#{offers.map { |offer| item(offer) }.join("\n\n")}"
    aviso ? "#{corpo}\n\n#{aviso}" : corpo
  end

  # Um item por oferta: nome e valor na primeira linha, o que qualifica aquele valor na segunda.
  #
  # DOIS PONTOS, E NÃO TRAVESSÃO (decisão do CEO, 12/09/2026): o travessão sai do texto que chega ao
  # cliente, e aqui ele separava duas colunas — o nome e o valor.
  def self.item(offer)
    premium = ::Autonomia::Insurance::PremiumText.new(offer['premium'])
    linha = "• *#{nome(offer)}*: #{premium.resumo}"
    detalhe = premium.detalhe
    detalhe ? "#{linha}\n  #{detalhe}" : linha
  end

  # O NOME VEM DO PORTAL e é interpolado dentro do negrito. Um `*` no meio fecha o negrito cedo e o
  # resto do nome vaza com asterisco à mostra; uma quebra de linha desmonta o marcador. Nenhuma das
  # duas apareceu ainda — e nenhuma das duas é nossa para garantir que não apareça.
  def self.nome(offer)
    offer.dig('insurer', 'name').to_s.tr("*\n\r", ' ').squeeze(' ').strip
  end

  private

  # Da mais barata para a mais cara — só faz sentido DENTRO de um bloco de mesmo período.
  def por_valor(offers)
    offers.sort_by { |offer| offer.dig('premium', 'amount').to_f }
  end
end
