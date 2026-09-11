# A MEDIDA DA COTAÇÃO (entrega 7): quantas cotações e quantas SEGURADORAS foram acionadas, por
# corretora e por período.
#
# DOIS NÚMEROS, NUNCA UM. Uma cotação aciona todas as seguradoras que a corretora habilitou — nas
# três cotações reais lidas em 11/09/2026 foram dezessete em cada uma. Contar execuções e chamá-las
# de consultas foi exatamente o erro do teto de "8 por hora" que saiu em 10/09/2026: oito execuções
# eram até 136 consultas, e o número 8 não dizia nada sobre dinheiro.
#
# ISTO NÃO É FREIO, E NÃO PODE VIRAR UM. Quem decide volume é a corretora que paga: ela cota mais,
# fecha mais negócio e tem retorno maior. A medida serve para cobrar pelo que foi consumido e para
# mostrar o retorno; nenhum caminho de cotação a consulta, e `medida_nao_e_freio_spec` reprova quem
# a chamar de dentro da ferramenta, do job ou do aceite.
#
# O QUE ELA NÃO SABE, ELA DIZ. Três números separados guardam o que seria fácil somar errado:
#   - `cotacoes_sem_medida`: a cotação existe no portal e o número de seguradoras nunca foi lido (a
#     execução morreu antes da primeira consulta, ou é anterior a esta entrega). Somar zero faria o
#     total parecer completo — e o total serve para cobrar;
#   - `cotacoes_sem_confirmacao`: o job decidiu submeter e o número nunca chegou (entrega 5). A
#     cotação PODE existir no portal. Não entra em `cotacoes` (afirmaria o que não se sabe);
#   - `cotacoes_possivelmente_duplicadas`: pode haver UMA A MAIS no portal do que a contada
#     (`ToolRun.possivelmente_duplicadas` lista quais).
#
# A FONTE É A LINHA DA EXECUÇÃO (`autonomia_agent_tool_runs`), que já é o registro do que aconteceu:
# o número da cotação no portal, quem cotou e — desde esta entrega — quem foi acionado. O índice
# `idx_autonomia_tool_runs_account_slug (account_id, slug, created_at)` é exatamente o desta consulta.
class Autonomia::Insurance::Medida
  # Data que não se lê NÃO vira "os últimos 30 dias" em silêncio: um número de cobrança de uma janela
  # que o operador não pediu é pior do que erro nenhum.
  PeriodoInvalido = Class.new(StandardError)

  Run = ::Autonomia::Agents::ToolRun
  Quote = ::Autonomia::Agents::Tools::Native::InsuranceQuote

  DIAS_PADRAO = 30

  # A data vem SÓ neste formato, e o texto tem de ser exatamente ele: "qualquer ISO 8601" aceitaria
  # data-hora e a truncaria em silêncio.
  FORMATO_DA_DATA = '%Y-%m-%d'.freeze

  # Os fusos vão de UTC-12 a UTC+14: a meia-noite de uma mesma data em dois fusos quaisquer dista no
  # máximo 26 horas. É a folga com que a lista do Super Admin enumera as corretoras antes de ler cada
  # uma no fuso dela — folga a mais só custa uma leitura vazia; a menos, esconde corretora da fatura.
  FOLGA_DE_FUSO = 26.hours

  # A cotação EXISTE NO PORTAL quando o número dela voltou. `autonomia_submitted` não serve: ele
  # marca "o retorno do start foi registrado", e uma recusa do `start` também o recebe — a linha da
  # recusa fica `{pedido, motivo, faltando, autonomia_intencoes: 1, autonomia_submitted: true}`, sem
  # `quote_id`, e cobrá-la seria cobrar por trabalho que não houve. Os exemplos usam essa linha REAL
  # (a que o job grava), não uma inventada sem a marca.
  COTACAO = "handle->>'quote_id' IS NOT NULL".freeze

  # A COTAÇÃO VIROU PROPOSTA quando a lista de propostas dela tem pelo menos um código. Conta
  # COTAÇÕES (termo 3: "quantas cotações viraram proposta individual"), não códigos: uma cotação com
  # duas propostas é UMA cotação que virou proposta. A soma dos códigos existe em separado
  # (`propostas_emitidas`) e não é a linha da fatura.
  def self.com_proposta
    "jsonb_typeof(handle->'#{Quote::PROPOSTAS_KEY}') = 'array' AND jsonb_array_length(handle->'#{Quote::PROPOSTAS_KEY}') > 0"
  end

  # Quantos itens a lista daquela chave tem, por linha. `jsonb` é livre: chave ausente ou de outra
  # forma vale zero em vez de derrubar a consulta — quem conta a linha de forma inesperada como
  # cotação SEM medida é a coluna `cotacoes_sem_medida`, logo abaixo.
  def self.tamanho_da_lista(chave)
    "CASE WHEN jsonb_typeof(handle->'#{chave}') = 'array' THEN jsonb_array_length(handle->'#{chave}') ELSE 0 END"
  end

  # As colunas saem dos MESMOS nomes de chave que a ferramenta e o job escrevem. Digitá-las aqui
  # faria a consulta devolver zero em silêncio no dia de um rename — e zero é o número que ninguém
  # questiona. Interpolação de constante nossa, nunca de entrada.
  COLUNAS = <<~SQL.squish.freeze
    account_id,
    COUNT(*) FILTER (WHERE #{COTACAO}) AS cotacoes,
    COALESCE(SUM(#{tamanho_da_lista(Quote::ACIONADAS_KEY)}), 0) AS seguradoras_acionadas,
    COALESCE(SUM(#{tamanho_da_lista(Quote::DELIVERED_KEY)}), 0) AS seguradoras_com_preco,
    COUNT(*) FILTER (WHERE #{com_proposta}) AS cotacoes_com_proposta,
    COALESCE(SUM(#{tamanho_da_lista(Quote::PROPOSTAS_KEY)}), 0) AS propostas_emitidas,
    COUNT(*) FILTER (
      WHERE #{COTACAO} AND jsonb_typeof(handle->'#{Quote::ACIONADAS_KEY}') IS DISTINCT FROM 'array'
    ) AS cotacoes_sem_medida,
    COUNT(*) FILTER (
      WHERE COALESCE((handle->>'#{Run::INTENCOES}')::int, 0) > 0 AND handle->>'#{Run::SUBMITTED_KEY}' IS NULL
    ) AS cotacoes_sem_confirmacao,
    COUNT(*) FILTER (WHERE handle->>'#{Run::POSSIVELMENTE_DUPLICADA}' IS NOT NULL) AS cotacoes_possivelmente_duplicadas
  SQL

  NUMEROS = %i[cotacoes seguradoras_acionadas seguradoras_com_preco cotacoes_com_proposta propostas_emitidas
               cotacoes_sem_medida cotacoes_sem_confirmacao cotacoes_possivelmente_duplicadas].freeze

  attr_reader :conta, :inicio, :fim, :fuso

  # O slug vem da FERRAMENTA, não de um literal aqui.
  def self.slug
    Quote.slug
  end

  # O FUSO É DA CORRETORA quando ela configurou um (`reporting_timezone`, o mesmo dos relatórios do
  # Chatwoot). "Setembro" da corretora termina às 23h59 DELA: cobrar pelo nosso fuso jogaria para
  # outubro toda cotação feita depois das 21h de 30/09 em São Paulo — o nosso valor no lugar do dela,
  # numa conta de dinheiro. Sem configuração (ou com uma que não resolve), o fuso da instalação — e o
  # resultado sempre diz qual foi, para ninguém ter de adivinhar.
  def self.fuso_de(conta)
    nome = conta.try(:reporting_timezone).presence
    nome && ActiveSupport::TimeZone[nome] ? nome : Time.zone.name
  end

  # -> [início, fim]. `inicio`/`fim` são datas (`2026-09-01`); nil vira a janela padrão. Fora disso,
  # recusa dita: `PeriodoInvalido`, com o que estava errado.
  #
  # A JANELA PADRÃO É A QUE TERMINA NO `fim` PEDIDO: sem `inicio`, os `DIAS_PADRAO` dias que acabam em
  # `fim` (e, sem os dois, os que acabam hoje). Ancorar o início em HOJE quando o operador só pediu o
  # fim (rodada 4) fazia `fim=2026-06-30` ser recusado como "data inicial posterior à final" — a
  # recusa culpava um dado que ele não escreveu, e o valor no lugar do dele era nosso.
  #
  # A INVERSÃO SÓ EXISTE ENTRE DUAS DATAS PEDIDAS. Com o fim em aberto, o fim é "agora", e uma
  # abertura depois dele quer dizer que a data inicial ainda não chegou NESTE fuso — o que é recusa
  # para quem pediu (`call`, `por_conta`) e janela vazia para a corretora cujo dia não começou
  # (rodada 5). Levantar aqui, na construção, fazia a página do Super Admin cair inteira por causa de
  # uma corretora em fuso atrás do da instalação, nas primeiras horas UTC do dia, culpando uma
  # "final" que ninguém mandou.
  def self.periodo(inicio:, fim:, fuso:)
    zona = ActiveSupport::TimeZone[fuso.to_s] || Time.zone
    final = data(zona, fim, 'fim')&.end_of_day
    abertura = data(zona, inicio, 'inicio')&.beginning_of_day
    recusar_inversao!(abertura, final)

    final ||= zona.now
    [abertura || (final - DIAS_PADRAO.days).beginning_of_day, final]
  end

  # Duas datas PEDIDAS, a primeira depois da segunda. Com qualquer uma em aberto não há inversão.
  def self.recusar_inversao!(abertura, final)
    return unless abertura && final && abertura > final

    raise PeriodoInvalido, 'a data inicial é posterior à final'
  end

  # SÓ DATA, E SÓ A DATA. `Date.iso8601` aceitava `2026-09-01T10:00:00` e descartava a hora: quem
  # pediu "a partir das 10h" recebia a partir da meia-noite sem aviso (rodada 4). `Date.strptime`
  # com formato fechado faz o MESMO — lê o que casa e ignora a sobra (conferido em Ruby puro) —, por
  # isso a guarda é a ida e volta: o texto tem de ser exatamente a data que foi lida, ou é pedido
  # que a consulta não atende, e a recusa é dita como a da data ilegível.
  # `Date::Error` é subclasse de `ArgumentError`: um `rescue` com as duas sombrearia a primeira.
  def self.data(zona, valor, nome)
    texto = valor.to_s.strip
    return nil if texto.empty?

    dia = Date.strptime(texto, FORMATO_DA_DATA)
    raise ArgumentError, 'sobra no texto da data' unless dia.strftime(FORMATO_DA_DATA) == texto

    zona.parse(dia.to_s)
  rescue ArgumentError
    raise PeriodoInvalido, "#{nome}: informe uma data no formato AAAA-MM-DD"
  end

  def initialize(inicio:, fim:, conta: nil)
    @conta = conta
    @pedido = { inicio: inicio, fim: fim }
    @fuso = self.class.fuso_de(conta)
    @inicio, @fim = self.class.periodo(inicio: inicio, fim: fim, fuso: @fuso)
  end

  # A medida de UMA corretora. Sem execução no período, zeros — e zero aqui é verdade, não "não sei".
  def call
    raise ArgumentError, 'a medida de uma conta exige a conta' if conta.nil?

    recusar_data_inicial_no_futuro!
    linha_da_conta || zerada(conta.id)
  end

  # Uma linha por corretora que teve execução no período, da que mais acionou para a que menos.
  # Corretora sem execução não aparece: inventar linha zerada para toda conta da instalação faria a
  # tela do Super Admin falar de quem nunca cotou.
  #
  # CADA LINHA É LIDA NO FUSO DA PRÓPRIA CORRETORA — a mesma `Medida.new(conta:)` que a API da conta
  # usa, e por isso os dois números batem por construção. Até a rodada 4 esta lista era UMA consulta
  # agrupada no fuso da instalação: a cotação das 23h de 30/09 em São Paulo (02h de 01/10 em UTC)
  # caía na fatura de outubro na tela que COBRA e em setembro na tela da corretora — dois números
  # para o mesmo mês, que é exatamente o que a página do Super Admin promete não fazer.
  #
  # A data inicial no futuro é recusada AQUI, no fuso de quem pediu a lista — e só aqui. A corretora
  # cujo dia ainda não começou (fuso atrás do da instalação, `from=hoje` sem `to` nas primeiras horas
  # UTC) não é pedido inválido: é janela vazia para ela, e a linha dela é pulada como a de qualquer
  # corretora sem execução no período (rodada 5).
  def por_conta
    recusar_data_inicial_no_futuro!
    @por_conta ||= corretoras_com_execucao
                   .filter_map { |corretora| self.class.new(conta: corretora, **pedido).linha_da_conta }
                   .sort_by { |linha| [-linha[:seguradoras_acionadas], -linha[:cotacoes], linha[:conta_id]] }
  end

  protected

  # A linha DESTA corretora, lida na janela do fuso DELA — ou nil, quando ela não teve execução nessa
  # janela. É a única leitura que toca o banco; `call` e `por_conta` passam por aqui.
  #
  # PROTEGIDA, não pública: sem conta, o escopo é a instalação inteira e `take` devolveria a linha de
  # uma corretora qualquer com o nome de nenhuma — numa consulta de dinheiro (rodada 5). `por_conta`
  # a chama numa instância da MESMA classe, e é o único lugar de fora desta instância que precisa.
  def linha_da_conta
    # `take`, não `first`: `first` numa relação agrupada acrescenta `ORDER BY id`, que o GROUP BY recusa.
    registro = escopo.group(:account_id).select(COLUNAS).take
    registro && linha_de(registro)
  end

  private

  attr_reader :pedido

  # A JANELA COMEÇA DEPOIS DE TERMINAR só com `inicio` pedido e `fim` em aberto (o fim é "agora"): a
  # data inicial ainda não chegou neste fuso. Para quem PEDIU a medida é recusa dita — e a frase culpa
  # a data que foi escrita, não uma "final" que ninguém mandou. Para a corretora enumerada por
  # `por_conta`, a mesma janela é só vazia: `created_at: inicio..fim` com o início depois do fim não
  # casa linha nenhuma, e ela é pulada.
  def recusar_data_inicial_no_futuro!
    raise PeriodoInvalido, 'a data inicial está no futuro' if inicio > fim
  end

  # POR FERRAMENTA, não por conta inteira: a linha de outra ferramenta assíncrona com um `quote_id` no
  # handle não é cotação de seguro, e somá-la cobraria a corretora por outra coisa.
  def escopo
    linhas = Run.where(slug: self.class.slug, created_at: inicio..fim)
    conta ? linhas.where(account_id: conta.id) : linhas
  end

  # QUEM PODE ter execução no período, em qualquer fuso. A janela desta instância está no fuso da
  # instalação; a de cada corretora pode começar até `FOLGA_DE_FUSO` antes ou terminar até isso
  # depois. Alargar dos dois lados garante que nenhuma corretora fique de fora da enumeração; quem
  # entrou a mais é lido na janela DELA em `linha_da_conta` e cai fora se não tiver nada lá.
  def corretoras_com_execucao
    return [conta] if conta

    ids = Run.where(slug: self.class.slug, created_at: (inicio - FOLGA_DE_FUSO)..(fim + FOLGA_DE_FUSO))
             .distinct.pluck(:account_id)
    Account.where(id: ids).order(:id)
  end

  def linha_de(registro)
    zerada(registro.account_id).merge(NUMEROS.index_with { |campo| registro[campo].to_i })
  end

  def zerada(conta_id)
    { conta_id: conta_id, inicio: inicio, fim: fim, fuso: fuso }.merge(NUMEROS.index_with { 0 })
  end
end
