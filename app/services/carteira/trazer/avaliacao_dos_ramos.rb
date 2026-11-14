# A bateria que mede o modelo no "ramo → tipo" (E4, #2897): pega uma lista de ramos como as corretoras escrevem, com o
# tipo que cada um deveria ser, pergunta ao modelo de verdade (Carteira::Trazer::PerguntaDoRamo) e conta os acertos.
# Serve para decidir se o texto da pergunta está bom, e para comparar antes e depois de mexer nele.
#
# É chamada paga, por isso nada aqui roda sozinho: quem dispara é a tarefa `carteira:ramos:avaliar`
# (lib/tasks/carteira_ramos.rake), que só anda com a variável de ambiente e respeita o teto de chamadas. Os casos
# (lib/tasks/carteira_ramos_casos.json) são só ramos, sem dado de pessoa nem de corretora.
#
# O ramo vai ao modelo como vai na leitura da planilha: sem espaço sobrando e em minúscula
# (Carteira::Trazer::TipoDoRamo.agrupado). O ramo que o modelo não respondeu (a chamada falhou) conta como erro, na
# coluna `sem_resposta`.
class Carteira::Trazer::AvaliacaoDosRamos
  CASOS = Rails.root.join('lib/tasks/carteira_ramos_casos.json')
  SEM_RESPOSTA = 'sem_resposta'.freeze
  Resultado = Struct.new(:total, :acertos, :por_tipo, :matriz, :erros, :uso, :custo, keyword_init: true)
  class TetoDeChamadas < StandardError; end

  # [{ 'ramo' => 'RC Prof.', 'tipo' => 'empresarial' }, ...]
  def self.casos(caminho = CASOS)
    JSON.parse(File.read(caminho))
  end

  # pergunta: quem pergunta ao modelo e soma o que gastou (`uso`). teto: o máximo de chamadas que esta rodada pode fazer.
  # modelo: o nome do modelo, para estimar o custo pela tabela de preços (Crm::Ai::Pricing).
  def initialize(casos, pergunta:, teto:, modelo: TypesafeAi::Config.model)
    @casos = casos
    @pergunta = pergunta
    @teto = teto
    @modelo = modelo
  end

  # Quantas chamadas ao modelo a rodada faz: uma a cada Carteira::Trazer::PerguntaDoRamo::POR_CHAMADA ramos distintos.
  def chamadas
    (ramos.size.to_f / Carteira::Trazer::PerguntaDoRamo::POR_CHAMADA).ceil
  end

  def call
    raise TetoDeChamadas, "a rodada faria #{chamadas} chamadas e o teto é #{@teto}" if chamadas > @teto

    respostas = @pergunta.call(ramos)
    pares = @casos.map { |caso| [caso['ramo'], caso['tipo'], respostas.fetch(agrupado(caso['ramo']), SEM_RESPOSTA)] }
    Resultado.new(total: pares.size, acertos: pares.count { |_ramo, esperado, veio| esperado == veio }, por_tipo: por_tipo(pares),
                  matriz: pares.map { |_ramo, esperado, veio| [esperado, veio] }.tally,
                  erros: pares.reject { |_ramo, esperado, veio| esperado == veio }, uso: @pergunta.uso, custo: custo)
  end

  private

  def ramos
    @ramos ||= @casos.map { |caso| agrupado(caso['ramo']) }.uniq
  end

  def agrupado(ramo)
    Carteira::Trazer::TipoDoRamo.agrupado(ramo)
  end

  # { 'auto' => [acertos, casos], ... }
  def por_tipo(pares)
    pares.group_by { |_ramo, esperado, _veio| esperado }.transform_values do |do_tipo|
      [do_tipo.count { |_ramo, esperado, veio| esperado == veio }, do_tipo.size]
    end
  end

  # Em dólar, pelo que o modelo disse que consumiu.
  def custo
    Crm::Ai::Pricing.cost(model: @modelo, **@pergunta.uso.slice(:input_tokens, :output_tokens))
  end
end
