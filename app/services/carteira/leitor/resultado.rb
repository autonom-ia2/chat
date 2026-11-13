# O que o leitor de apólice devolve (E6, #2899). O leitor não grava nada: quem recebe decide o que fazer (mostrar o que
# mudou, pôr no Conferir, chamar Carteira::Guardar).
#
# Cada um dos NOMES que o leitor procura sai em UM de três lugares, nunca em dois:
# - `campos`: o que foi achado e pode ser gravado. Traz os nomes de CAMPOS, cada um com o valor na forma do banco
#   (texto, AAAA-MM-DD, centavos, só dígitos no documento) ou nil. O nome que saiu a confirmar NÃO aparece aqui, nem
#   como chave com nil (e por isso também não aparece em `dados_da_apolice`);
# - `valores_a_confirmar`: o que foi achado, mas só vale depois de uma pessoa confirmar. É um objeto à parte, que não
#   se mistura com `campos` nem com `dados_da_apolice`: quem grava iterando `campos` não o alcança por engano. Quem
#   recebe (o Conferir, o "o que mudou") mostra cada um para a pessoa confirmar e só então grava. `a_confirmar` são os
#   nomes deles. Entram aqui:
#   - `segurado_telefone` (só dígitos) e `segurado_email`, SEMPRE: a apólice traz o telefone do corretor ao lado do CPF
#     do segurado, e nenhuma conferência de valor separa um do outro. Eles nunca estão em `campos`;
#   - `valor_centavos`, quando o valor está escrito na página mas sem "R$" antes: pode ser outra medida. Com o "R$"
#     ele sai em `campos`;
# - `duvidas`: os nomes que ficaram sem valor nenhum ("não achei"). O leitor nunca chuta.
#
# - `lido?`: o arquivo é uma apólice e foi lido.
# - `recusa`: por que não leu. `leitura_desligada` (a conta não tem a leitura liberada), `nao_e_apolice` (o arquivo não
#   é uma apólice de seguro) ou `nao_deu_para_ler` (arquivo ilegível, sem texto, conta sem a IA configurada ou falha
#   do modelo; o detalhe fica em `motivo`, que é para registro, não para a tela).
# - `paginas_total` e `paginas_enviadas` (os números das páginas que foram ao modelo): só contagem, podem ir para log
#   e para `totais`.
#
# `campos` e `valores_a_confirmar` são dado de cliente: não vão para log, argumento de job nem cache. O `inspect` e o
# `as_json` (e o `to_json`) não os mostram: trazem só a recusa, o motivo, as contagens e os NOMES das dúvidas e do que
# está a confirmar. Os dois são congelados.
class Carteira::Leitor::Resultado
  DESLIGADA = 'leitura_desligada'.freeze
  NAO_E_APOLICE = 'nao_e_apolice'.freeze
  NAO_DEU = 'nao_deu_para_ler'.freeze
  RECUSAS = [DESLIGADA, NAO_E_APOLICE, NAO_DEU].freeze
  DA_APOLICE = %w[tipo ramo_original seguradora numero inicio_vigencia fim_vigencia valor_centavos bem].freeze
  # `corretora` é a corretora que aparece na apólice (serve ao seguro de outra corretora).
  CAMPOS = (DA_APOLICE + %w[corretora segurado_nome segurado_documento]).freeze
  CONTATO = %w[segurado_telefone segurado_email].freeze
  # O que pode sair como "a confirmar": o contato, sempre; o valor, quando não vem depois de "R$".
  A_CONFIRMAR = (CONTATO + %w[valor_centavos]).freeze
  NOMES = (CAMPOS + CONTATO).freeze
  SEM_ACHADOS = { campos: {}, a_confirmar: {} }.freeze

  attr_reader :recusa, :motivo, :campos, :valores_a_confirmar, :paginas_total, :paginas_enviadas

  def self.lido(campos:, paginas_total:, paginas_enviadas:, a_confirmar: {})
    new(achados: { campos: campos, a_confirmar: a_confirmar }, paginas_total: paginas_total, paginas_enviadas: paginas_enviadas)
  end

  def self.recusado(recusa, motivo: nil, paginas_total: nil, paginas_enviadas: [])
    raise ArgumentError, 'recusa' unless RECUSAS.include?(recusa)

    new(recusa: recusa, motivo: motivo, paginas_total: paginas_total, paginas_enviadas: paginas_enviadas)
  end

  # Use `lido` ou `recusado`. O que vem em `a_confirmar` nunca fica em `campos`, mesmo que quem chama mande nos dois.
  def initialize(paginas_total:, paginas_enviadas:, recusa: nil, motivo: nil, achados: SEM_ACHADOS)
    @recusa = recusa
    @motivo = motivo
    @valores_a_confirmar = achados[:a_confirmar].slice(*A_CONFIRMAR).compact.transform_values { |valor| valor.dup.freeze }.freeze
    @campos = (recusa ? {} : (CAMPOS - a_confirmar).index_with { |campo| achados[:campos][campo] }).freeze
    @paginas_total = paginas_total
    @paginas_enviadas = paginas_enviadas
  end

  def lido?
    recusa.nil?
  end

  def a_confirmar
    valores_a_confirmar.keys
  end

  def duvidas
    return [] unless lido?

    NOMES.reject { |nome| campos[nome] || valores_a_confirmar.key?(nome) }
  end

  # Os dados da apólice como Carteira::Guardar recebe, com as chaves de comparação.
  def dados_da_apolice
    campos.slice(*DA_APOLICE).symbolize_keys.merge(
      seguradora_chave: Carteira::Chave.seguradora(campos['seguradora']).presence,
      numero_chave: Carteira::Chave.numero(campos['numero']).presence
    )
  end

  def inspect
    "#<#{self.class.name} recusa=#{recusa.inspect} motivo=#{motivo.inspect} duvidas=#{duvidas.size} " \
      "a_confirmar=#{a_confirmar.size} paginas=#{paginas_enviadas.size}/#{paginas_total.inspect}>"
  end

  # O que pode ir para log e para `totais`: nomes e contagens, nunca um valor lido.
  def as_json(*)
    { 'recusa' => recusa, 'motivo' => motivo&.to_s, 'paginas_total' => paginas_total, 'paginas_enviadas' => paginas_enviadas,
      'duvidas' => duvidas, 'a_confirmar' => a_confirmar }
  end
end
