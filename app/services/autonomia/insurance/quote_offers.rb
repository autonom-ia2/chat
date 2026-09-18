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
  # Havia um: as 3 mais baratas, `.first(3)` sobre a lista inteira. Rodrigo removeu em 10/09/2026: a
  # corretora paga por todas as seguradoras, e esconder o que ela pagou é jogar fora valor comprado.
  # Desde a fatia 3 do #420 (18/09/2026) o recorte é do cliente, e quem o faz é a Lia: a ferramenta
  # `ver_resultado_da_cotacao` devolve todas, e ela escreve só as que ele pediu.
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
      cotadas = Array(@result['offers']).select { |offer| self.class.cotada?(offer) }
      sem_periodo, com_periodo = cotadas.partition { |offer| self.class.sem_periodo?(offer) }
      mensais, totais = com_periodo.partition { |offer| self.class.mensal?(offer) }
      por_valor(totais) + por_valor(mensais) + sem_periodo
    end
  end

  # -> a oferta cotou e trouxe valor? É o critério de `quoted` e o de "com preço" do resultado guardado
  # por seguradora (`Insurance::ResultadoPorSeguradora`).
  def self.cotada?(offer)
    offer['status'] == 'quoted' && offer.dig('premium', 'amount').present?
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

  # -> os códigos desta leitura, em ordem, quando ela tem oferta e TODA oferta tem status em `DESFECHOS`;
  # nil quando não. É o que a ferramenta grava no handle a cada leitura (`InsuranceQuote::LEITURA_ASSENTADA_KEY`).
  def assentada
    ofertas = Array(@result['offers'])
    return nil if ofertas.empty? || ofertas.any? { |offer| DESFECHOS.exclude?(offer['status']) }

    acionadas.sort
  end

  # -> true quando as três condições valem (rodada 2 da fatia 1 do PDF rápido, 13/09/2026):
  #   1. esta leitura está assentada (`assentada`);
  #   2. a leitura IMEDIATAMENTE anterior também estava, com o MESMO conjunto de códigos
  #      (`assentada_anterior`, o que a ferramenta gravou no handle na passada anterior);
  #   3. todo código que alguma leitura anterior listou (`ja_acionadas`, a união) aparece nesta.
  # A 2 faz a primeira leitura, e a primeira leitura assentada depois de uma com seguradora em andamento
  # ou de uma lista diferente, responderem falso: a lista precisa se repetir, com desfecho, em duas leituras
  # seguidas.
  #
  # A REGRA DEPENDE DE O PORTAL JÁ TER LISTADO TODAS AS SEGURADORAS quando a lista se repete. Duas leituras
  # assentadas iguais com parte delas listada fecham a cotação, e a seguradora que o portal listar depois fica
  # de fora (sonda C2 da revisão da rodada 2). Nos brutos da medição de 13/09/2026, as duas linhas do tempo
  # completas tinham todos os cálculos listados já na primeira leitura; o contrário não foi observado.
  def todas_com_desfecho?(ja_acionadas, assentada_anterior)
    atual = assentada
    return false if atual.nil? || Array(assentada_anterior).map(&:to_s).sort != atual

    (Array(ja_acionadas).map(&:to_s) - acionadas).empty?
  end

  # -> true quando esta leitura está assentada e lista todo código que alguma leitura anterior listou
  # (`ja_acionadas`, a união). Chamado só na passada em que `todas_com_desfecho?` respondeu falso
  # (`InsuranceQuote::Resultado#em_andamento`, fatia 2 do #420): ali, verdade quer dizer que a próxima
  # leitura, se repetir esta, fecha a cotação, e a ferramenta pede a consulta seguinte no primeiro intervalo
  # da progressão.
  #
  # A leitura assentada que perdeu uma seguradora já listada responde falso: a próxima leitura igual também
  # não fecharia a cotação.
  def confirma_na_proxima?(ja_acionadas)
    assentada.present? && (Array(ja_acionadas).map(&:to_s) - acionadas).empty?
  end

  # Seguradoras que recusaram a credencial que a corretora cadastrou NO PORTAL (critério 4.5).
  def credencial_pendente
    Array(@result['offers']).select { |offer| offer['status'] == 'auth_required' }
  end

  def self.code(offer)
    offer.dig('insurer', 'code').to_s
  end

  # O NOME VEM DO PORTAL e vai ao modelo, que o escreve ao cliente: sem `*`, que o WhatsApp lê como
  # marcador de negrito, e sem quebra de linha, que partiria a linha de dados da seguradora.
  def self.nome(offer)
    offer.dig('insurer', 'name').to_s.tr("*\n\r", ' ').squeeze(' ').strip
  end

  private

  # Da mais barata para a mais cara — só faz sentido DENTRO de um bloco de mesmo período.
  def por_valor(offers)
    offers.sort_by { |offer| offer.dig('premium', 'amount').to_f }
  end
end
