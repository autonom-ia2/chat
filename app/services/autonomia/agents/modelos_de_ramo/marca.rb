# A MARCA DO MODELO PRONTO (#2881): o que a conversa do Construtor guarda em `state['modelo_pronto']` e o agente em
# `config['modelo_pronto']`, sem migration:
#
#   { 'chave' => 'seguro_garantia',
#     'perguntas'   => [{ 'id' => 'p1', 'texto' => '...', 'tirada' => false }, ...],
#     'documentos'  => [{ 'id' => 'd1', 'texto' => '...', 'tirada' => false }, ...],
#     'ferramentas' => [{ 'fonte' => 'cnpj', 'usar_quando' => 'Use quando ...' }, ...] }   # o "Já vem com"
#
# Ela nasce como cópia do arquivo do modelo e depois só muda pela mão do dono (`Edicao`): editar o arquivo num deploy
# não muda rascunho nem agente que já existe. O item que o dono tirou fica na lista com `tirada: true` (a tela pode
# desfazer) e não vai para o agente. Aqui só há leitura: toda função devolve valor novo, nada é alterado no lugar.
module Autonomia::Agents::ModelosDeRamo::Marca
  CHAVE = 'modelo_pronto'.freeze
  PREFIXOS = { 'perguntas' => 'p', 'documentos' => 'd' }.freeze
  LISTA_VAZIA = '(nenhum item nesta lista)'.freeze

  module_function

  def inicial(modelo)
    { 'chave' => modelo.chave,
      'perguntas' => numerar(modelo.perguntas, 'perguntas'),
      'documentos' => numerar(modelo.documentos, 'documentos'),
      'ferramentas' => modelo.ja_vem.map { |ferramenta| { 'fonte' => ferramenta.fonte, 'usar_quando' => ferramenta.usar_quando } } }
  end

  def numerar(textos, lista)
    textos.each_with_index.map { |texto, indice| { 'id' => "#{PREFIXOS.fetch(lista)}#{indice + 1}", 'texto' => texto, 'tirada' => false } }
  end

  # Os itens da lista como a tela os recebe: { id, texto, tirada }.
  def itens(marca, lista)
    Array(marca.to_h[lista]).grep(Hash).map do |item|
      { 'id' => item['id'].to_s, 'texto' => item['texto'].to_s, 'tirada' => item['tirada'] == true }
    end
  end

  # Só os textos que valem: fora os que o dono tirou.
  def textos(marca, lista)
    itens(marca, lista).reject { |item| item['tirada'] }.pluck('texto').compact_blank
  end

  # A lista numerada que entra no roteiro e nas instruções do agente.
  def numerada(marca, lista)
    linhas = textos(marca, lista).each_with_index.map { |texto, indice| "#{indice + 1}. #{texto}" }
    linhas.empty? ? LISTA_VAZIA : linhas.join("\n")
  end

  def ferramentas(marca)
    Array(marca.to_h['ferramentas']).grep(Hash).map do |ferramenta|
      { 'fonte' => ferramenta['fonte'].to_s, 'usar_quando' => ferramenta['usar_quando'].to_s }
    end
  end

  # O id de um item novo: o prefixo da lista e o número seguinte ao maior já usado nela.
  def proximo_id(lista, ids)
    prefixo = PREFIXOS.fetch(lista)
    maior = ids.map(&:to_s).select { |id| id.start_with?(prefixo) }.map { |id| id.delete_prefix(prefixo).to_i }.max.to_i
    "#{prefixo}#{maior + 1}"
  end
end
