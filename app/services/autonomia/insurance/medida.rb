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

  # A cotação EXISTE NO PORTAL quando o número dela voltou. `autonomia_submitted` não serve: ele
  # marca "o retorno do start foi registrado", e uma recusa de conferência também o recebe.
  COTACAO = "handle->>'quote_id' IS NOT NULL".freeze

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
    COALESCE(SUM(#{tamanho_da_lista(Quote::PROPOSTAS_KEY)}), 0) AS propostas,
    COUNT(*) FILTER (
      WHERE #{COTACAO} AND jsonb_typeof(handle->'#{Quote::ACIONADAS_KEY}') IS DISTINCT FROM 'array'
    ) AS cotacoes_sem_medida,
    COUNT(*) FILTER (
      WHERE COALESCE((handle->>'#{Run::INTENCOES}')::int, 0) > 0 AND handle->>'#{Run::SUBMITTED_KEY}' IS NULL
    ) AS cotacoes_sem_confirmacao,
    COUNT(*) FILTER (WHERE handle->>'#{Run::POSSIVELMENTE_DUPLICADA}' IS NOT NULL) AS cotacoes_possivelmente_duplicadas
  SQL

  NUMEROS = %i[cotacoes seguradoras_acionadas seguradoras_com_preco propostas cotacoes_sem_medida
               cotacoes_sem_confirmacao cotacoes_possivelmente_duplicadas].freeze

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
  def self.periodo(inicio:, fim:, fuso:)
    zona = ActiveSupport::TimeZone[fuso.to_s] || Time.zone
    final = data(zona, fim, 'fim')&.end_of_day || zona.now
    abertura = data(zona, inicio, 'inicio')&.beginning_of_day || (zona.now - DIAS_PADRAO.days).beginning_of_day
    raise PeriodoInvalido, 'a data inicial é posterior à final' if abertura > final

    [abertura, final]
  end

  # `Date::Error` é subclasse de `ArgumentError`: um `rescue` com as duas sombrearia a primeira.
  def self.data(zona, valor, nome)
    texto = valor.to_s.strip
    return nil if texto.empty?

    zona.parse(Date.iso8601(texto).to_s)
  rescue ArgumentError
    raise PeriodoInvalido, "#{nome}: informe uma data no formato AAAA-MM-DD"
  end

  def initialize(inicio:, fim:, conta: nil)
    @conta = conta
    @fuso = self.class.fuso_de(conta)
    @inicio, @fim = self.class.periodo(inicio: inicio, fim: fim, fuso: @fuso)
  end

  # A medida de UMA corretora. Sem execução no período, zeros — e zero aqui é verdade, não "não sei".
  def call
    raise ArgumentError, 'a medida de uma conta exige a conta' if conta.nil?

    por_conta.first || zerada(conta.id)
  end

  # Uma linha por corretora que teve execução no período, da que mais acionou para a que menos.
  # Corretora sem execução não aparece: inventar linha zerada para toda conta da instalação faria a
  # tela do Super Admin falar de quem nunca cotou.
  def por_conta
    @por_conta ||= escopo.group(:account_id).select(COLUNAS)
                         .map { |linha| linha_de(linha) }
                         .sort_by { |linha| [-linha[:seguradoras_acionadas], -linha[:cotacoes], linha[:conta_id]] }
  end

  private

  def escopo
    linhas = Run.where(slug: self.class.slug, created_at: inicio..fim)
    conta ? linhas.where(account_id: conta.id) : linhas
  end

  def linha_de(registro)
    zerada(registro.account_id).merge(NUMEROS.index_with { |campo| registro[campo].to_i })
  end

  def zerada(conta_id)
    { conta_id: conta_id, inicio: inicio, fim: fim, fuso: fuso }.merge(NUMEROS.index_with { 0 })
  end
end
