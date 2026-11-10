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
#
# #2867 — com peso igual nas duas listas, todo trecho presente nas duas (mesmo no 48º lugar de cada: 2/108) passava na
# frente do 1º do vetor que não casava a palavra (1/61): o trecho certo caía para o 5º–11º lugar e o MRR do placar da
# F0 caiu de 0,58 para 0,39. Agora o 1º do vetor fica na frente, e a palavra vale um quarto do vetor: sobe o trecho que
# casa a palavra e está perto no sentido; o que só repete palavras comuns e está longe fica onde o vetor o pôs. O trecho
# que só a palavra achou (fora dos candidatos do vetor) fica atrás de todos eles: 0,25/61 é menos que 1/108. O peso
# saiu do placar das 2 bases nos 2 gabaritos (0,2 a 0,3 cumprem o critério do #2867; 0,1 e 0,35 não).
class Autonomia::Agents::BuscaHibrida
  FLAG = 'rag_busca_hibrida'.freeze
  RRF_K = 60
  PESO_DA_PALAVRA = 0.25
  TABELA = Autonomia::Agents::KnowledgeEntry.table_name
  TEXTO = "to_tsvector('portuguese', #{TABELA}.content)".freeze

  def initialize(escopo:, vector:, model:, query:)
    @escopo = escopo
    @vector = vector
    @large = Autonomia::Agents::Config.embedding_large?(model)
    # O Postgres não aceita o byte nulo num literal; vira espaço, para não colar as palavras dos dois lados.
    @query = query.to_s.tr("\u0000", ' ')
  end

  # vetoriais: os candidatos do vetor, na ordem do vetor. Devolve a fusão, dentro do teto, com o 1º do vetor na frente e
  # o resto do mais forte ao mais fraco.
  def fundir(vetoriais, limite)
    pontos = Hash.new(0.0)
    trechos = {}
    [[vetoriais, 1.0], [por_palavra(limite), PESO_DA_PALAVRA]].each do |lista, peso|
      lista.each_with_index do |trecho, posicao|
        pontos[trecho.id] += peso / (RRF_K + posicao + 1)
        trechos[trecho.id] ||= trecho
      end
    end
    ordenados = trechos.values.select { |trecho| dentro_do_teto?(trecho) }
                       .sort_by { |trecho| [-pontos[trecho.id], trecho.neighbor_distance.to_f, trecho.id] }
    primeiro_do_vetor_na_frente(ordenados, vetoriais)
  end

  # Os trechos que casam as palavras da pergunta, do mais forte ao mais fraco, com a distância do vetor e dentro do teto.
  # #2850 — sem o vetor da pergunta (o embedding falhou), sem distância (nil) e sem o teto, que mede o vetor.
  def por_palavra(limite)
    return trechos_da_palavra.limit(limite).to_a if @vector.nil?

    # O teto entra antes do LIMIT: trecho longe no sentido não ocupa a vaga de um que está dentro dele.
    trechos_da_palavra(distancia)
      .where(Arel.sql("#{distancia} <= #{Autonomia::Agents::Config::RETRIEVAL_HARD_CEILING.to_f}"))
      .limit(limite)
      .to_a
  end

  private

  def primeiro_do_vetor_na_frente(ordenados, vetoriais)
    primeiro = vetoriais.find { |trecho| dentro_do_teto?(trecho) }
    return ordenados if primeiro.nil?

    [primeiro] + ordenados.reject { |trecho| trecho.id == primeiro.id }
  end

  def dentro_do_teto?(trecho)
    !trecho.neighbor_distance.nil? && trecho.neighbor_distance.to_f <= Autonomia::Agents::Config::RETRIEVAL_HARD_CEILING
  end

  def trechos_da_palavra(distancia_do_trecho = 'NULL::float')
    # Os termos da pergunta, cada um entre aspas, ligados por OU. Montado termo a termo: o `&` de dentro de um termo
    # (um endereço, por exemplo) fica como está.
    consulta = sanitizar(["(SELECT string_agg(quote_literal(termo), ' | ') FROM unnest(tsvector_to_array(" \
                          "to_tsvector('portuguese', ?))) termo)::tsquery", @query])
    @escopo.where.not(coluna => nil)
           .where(Arel.sql("#{TEXTO} @@ #{consulta}"))
           .select(Arel.sql("#{TABELA}.*, #{distancia_do_trecho} AS neighbor_distance"))
           .order(Arel.sql("ts_rank_cd(#{TEXTO}, #{consulta}) DESC, #{TABELA}.id ASC"))
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
