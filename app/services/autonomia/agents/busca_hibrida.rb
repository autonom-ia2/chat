# #2810 (Refs #1431) — busca híbrida da base do agente, atrás da flag `rag_busca_hibrida` (o Retriever decide).
#
# Por que existe: o vetor sozinho deixa para trás o trecho que repete as palavras da pergunta quando outro trecho
# parecido no sentido está perto (no placar do #2807, o item do aviso de sinistro ficou em 26º e o do rastreador, com o
# mesmo telefone, em 1º). E o bônus por metadado, que reordenava os candidatos, derrubava o certo quando as distâncias
# estavam próximas (a garagem caiu de 5º para 28º).
#
# Como: os candidatos do vetor (já ordenados por distância) e os da busca por palavra (texto em português, `ts_rank_cd`,
# pelo índice GIN de expressão da migration do #2810) entram juntos, e a ordem sai da fusão por posição (RRF): cada
# lista dá 1 / (60 + posição) a cada trecho. Os termos da pergunta entram com OU (a pergunta do cliente não repete todas
# as palavras do trecho). Todo candidato leva a distância real do vetor, também o que veio só pela palavra, e o teto de
# distância continua valendo: trecho que só casa a palavra e está longe no sentido fica fora (isolamento de assunto).
class Autonomia::Agents::BuscaHibrida
  FLAG = 'rag_busca_hibrida'.freeze
  RRF_K = 60
  TABELA = Autonomia::Agents::KnowledgeEntry.table_name
  TEXTO = "to_tsvector('portuguese', #{TABELA}.content)".freeze

  def initialize(escopo:, vector:, model:, query:)
    @escopo = escopo
    @vector = vector
    @large = Autonomia::Agents::Config.embedding_large?(model)
    @query = query.to_s
  end

  # vetoriais: os candidatos do vetor, na ordem do vetor. Devolve a fusão, dentro do teto, do mais forte ao mais fraco.
  def fundir(vetoriais, limite)
    pontos = Hash.new(0.0)
    trechos = {}
    [vetoriais, por_palavra(limite)].each do |lista|
      lista.each_with_index do |trecho, posicao|
        pontos[trecho.id] += 1.0 / (RRF_K + posicao + 1)
        trechos[trecho.id] ||= trecho
      end
    end
    trechos.values.select { |trecho| dentro_do_teto?(trecho) }.sort_by { |trecho| [-pontos[trecho.id], trecho.neighbor_distance.to_f] }
  end

  private

  def dentro_do_teto?(trecho)
    !trecho.neighbor_distance.nil? && trecho.neighbor_distance.to_f <= Autonomia::Agents::Config::RETRIEVAL_HARD_CEILING
  end

  def por_palavra(limite)
    consulta = sanitizar(["replace(plainto_tsquery('portuguese', ?)::text, '&', '|')::tsquery", @query])
    @escopo.where.not(coluna => nil)
           .where(Arel.sql("#{TEXTO} @@ #{consulta}"))
           .select(Arel.sql("#{TABELA}.*, #{distancia} AS neighbor_distance"))
           .order(Arel.sql("ts_rank_cd(#{TEXTO}, #{consulta}) DESC, #{TABELA}.id ASC"))
           .limit(limite)
           .to_a
  end

  # A mesma escala do vetor (distância de cosseno), na coluna do modelo ativo.
  def distancia
    sanitizar(["(#{TABELA}.#{coluna} <=> ?::#{@large ? 'halfvec' : 'vector'})", "[#{@vector.join(',')}]"])
  end

  def coluna
    @large ? 'embedding_large' : 'embedding'
  end

  def sanitizar(partes)
    Autonomia::Agents::KnowledgeEntry.sanitize_sql_array(partes)
  end
end
