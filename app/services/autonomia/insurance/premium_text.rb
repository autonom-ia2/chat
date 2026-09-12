# O VALOR VIRA FRASE — critério 5.5 (valor com tipo, unidade e moeda exatos).
#
# "Porto Seguro: R$ 2.167,00" não diz se são R$ 2.167 no período inteiro ou por mês, e o cliente lê
# pelo que lhe convém. Errar isso para baixo é o lado que fecha venda e vira reclamação depois.
#
# O significado NÃO é decidido aqui: quem deriva é o adapter, olhando o que o portal devolveu — o
# parcelamento, que prova `total`; o marcador `packageType=1`, que marca assinatura mensal
# (`monthly`) —, e manda em `basis`, com o campo do portal nomeado em `basis_evidence`. Aqui só se
# traduz o que veio — e quando não veio, não se inventa.
class Autonomia::Insurance::PremiumText
  # Colada no item a que pertence, e curta de propósito: é uma linha secundária debaixo de um
  # preço. Era um parágrafo no fim do bloco, que aparecia mesmo valendo para UMA oferta e ficava
  # maior que os próprios preços.
  SEM_BASE = 'a seguradora não informou se é o total ou uma parcela'.freeze

  def initialize(premium)
    @premium = premium.to_h
  end

  # A PRIMEIRA LINHA DO ITEM: só o valor e o que se sabe dele. O parcelamento e a ressalva descem
  # para a linha de baixo, porque tudo na mesma linha é o que fazia o preço competir com a
  # explicação — e quem lê no celular perde os dois.
  #
  # "NO TOTAL" SÓ QUANDO O ADAPTER DISSE `total`; "POR MÊS" SÓ QUANDO DISSE `monthly`. Até a entrega
  # 13 o parcelamento sozinho também dizia "no total" — uma segunda derivação, aqui, por cima da do
  # adapter. O `monthly` entrou na noite de 11/09/2026: o PDF do comparativo do próprio portal,
  # anexado na mesma conversa, imprimia "R$ 298,43 por mês" para a Bp Assinatura enquanto o cliente
  # lia aqui a ressalva de valor sem período. O marcador é `packageType=1` do portal, lido pelo
  # adapter e nomeado em `basis_evidence`; a assinatura não tem parcelamento (`parcelamentos=[]`).
  # Qualquer outro `basis` sai só com o valor: é o adapter que tem de explicar, não este texto que
  # tem de adivinhar.
  def resumo
    return "#{valor} no total" if total?
    return "#{valor} por mês" if mensal?

    valor
  end

  # -> String ou nil. O que vale para ESTE preço, e não para o bloco: parcelamento quando o portal
  # informou, e a ressalva quando ele mandou o número sem dizer do que se trata. Como parágrafo
  # solto no fim, a ressalva aparecia mesmo quando valia para uma opção só, e ficava maior que os
  # preços.
  #
  # A RESSALVA VEM ANTES DO PARCELAMENTO. Sem período, o parcelamento não tem o que parcelar: "R$
  # 351,59 / ou 2x de R$ 175,80" sem a ressalva diz ao cliente, por omissão, que 351,59 é o total —
  # exatamente o que `basis: 'unknown'` nega. O adapter hoje só manda `installments` junto de
  # `total` (a assinatura mensal vem com `parcelamentos=[]`); se um dia mandar sem período, o
  # cliente ouve a ressalva, e o motivo registrado no handle (entrega 13, termo 1) é que explica o
  # parcelamento que ficou de fora. E SÓ O TOTAL PARCELA: "R$ 298,43 por mês / ou 10x de R$ 29,84"
  # seria parcelar uma mensalidade — se o adapter mandar `installments` com `monthly`, a linha não
  # sai; o motivo no `basis_evidence` é que registra o que veio.
  def detalhe
    return SEM_BASE if indefinido?

    "ou #{parcelas['count']}x de #{money(parcelas['amount'])}" if total? && parcelas.present?
  end

  # true quando o preço saiu sem unidade — nem `total` nem `monthly`. É o ÚNICO predicado de "tem
  # período": dispara a ressalva colada na oferta, o registro no handle e a ordem no lote.
  def indefinido?
    !(total? || mensal?)
  end

  # true quando o adapter disse `monthly` (assinatura mensal, marcada pelo portal em `packageType=1`).
  # Público porque a ordem no lote precisa separar mensais de totais sem reler `basis` por conta própria.
  def mensal?
    @premium['basis'] == 'monthly'
  end

  # POR QUE o período não saiu: o `basis_evidence` do adapter, que nomeia o campo do portal que
  # faltou ou veio ambíguo (`parcelamentos=[]`, `premioMensal` derivado, plano fora do contrato).
  # Sem ele, o que veio é descrito — não substituído por uma frase nossa (entrega 13, termo 1).
  def motivo
    @premium['basis_evidence'].presence || "basis=#{@premium['basis'].inspect} sem basis_evidence"
  end

  # SEPARADOR DE MILHAR. Sem ele o portal virava `R$ 2837,70` na tela do cliente — quatro dígitos
  # colados, que é onde a leitura de preço tropeça. `number_with_delimiter` faz a troca dos dois
  # separadores de uma vez; `tr` sozinho não tem como, porque precisa inserir o ponto antes.
  def self.money(amount)
    inteiro, centavos = format('%.2f', amount.to_f).split('.')
    "R$ #{ActiveSupport::NumberHelper.number_to_delimited(inteiro.to_i, delimiter: '.')},#{centavos}"
  end

  private

  def total?
    @premium['basis'] == 'total'
  end

  def parcelas
    @premium['installments']
  end

  def valor
    money(@premium['amount'])
  end

  def money(amount)
    self.class.money(amount)
  end
end
