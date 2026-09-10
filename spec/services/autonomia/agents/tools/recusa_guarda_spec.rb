require 'rails_helper'
require 'prism'

# A GUARDA DA ENTREGA 6: saída de recusa nova que não deixe registro REPROVA A SUÍTE.
#
# A varredura de 10/09/2026 achou onze saídas de recusa onde a memória dizia "são duas". Uma lista
# escrita à mão envelhece no dia seguinte; o que não envelhece é a varredura virar teste. Por AST
# (Prism), não por texto: busca textual de `error:` acusa comentário e string, e não acha o que
# importa — um Hash literal com a chave `error` sendo montado fora do produtor único.
#
# Três regras:
#   1. Nenhum `{ error: ... }` literal fora de `Tools::Recusa`. Quem precisa recusar chama
#      `Recusa.para_modelo` ou `Bound#recusar`, e a linha de registro sai junto.
#   2. Todo código de recusa escrito como literal — primeiro argumento de `recusar`, `registrar`,
#      `para_modelo`, `recusa`, `conferencia`, ou um `return 'codigo'` em `bound.rb` — está em
#      `MOTIVOS`, ou seja, tem a frase em português e o exemplo em `recusa_registro_spec`.
#   3. A varredura enxerga o que já existe. Um visitador quebrado devolveria lista vazia e o teste
#      passaria elogiando o silêncio; aqui ele reprova.
#
# PROVA POR MUTAÇÃO, feita em 10/09/2026: um `{ error: 'x' }.to_json` a mais em `bound.rb` reprova a
# regra 1 com o arquivo e a linha; um `return 'motivo_novo' if false` em `async_refusal` reprova a 2.
RSpec.describe Autonomia::Agents::Tools::Recusa do
  let(:arquivos_varridos) do
    %w[
      app/services/autonomia/agents/tools/bound.rb
      app/services/autonomia/agents/answerer.rb
      app/services/autonomia/agents/specialists/runner.rb
      app/services/autonomia/agents/tools/native/insurance_quote.rb
      app/jobs/autonomia/agents/tools/async_run_job.rb
    ]
  end
  let(:produtor_unico) { 'app/services/autonomia/agents/tools/recusa.rb' }
  let(:bound) { 'app/services/autonomia/agents/tools/bound.rb' }
  # Chamadas cujo PRIMEIRO argumento é o código da recusa.
  let(:registradores) { %i[recusar registrar para_modelo recusa conferencia] }
  # Abaixo disto a varredura não está enxergando o código que existia em 10/09/2026 (eram 14).
  let(:minimo_conhecido) { 8 }

  def arvore(caminho)
    Prism.parse_file(Rails.root.join(caminho).to_s).value
  end

  def cada_no(nodo, &)
    return if nodo.nil?

    yield(nodo)
    nodo.compact_child_nodes.each { |filho| cada_no(filho, &) }
  end

  def achado(caminho, nodo, texto)
    "#{caminho}:#{nodo.location.start_line}  #{texto}"
  end

  # `error:` e `'error' =>` são a mesma chave depois do `to_json`; a guarda vê as duas.
  def chave_error?(elemento)
    return false unless elemento.is_a?(Prism::AssocNode)

    chave = elemento.key
    (chave.is_a?(Prism::SymbolNode) || chave.is_a?(Prism::StringNode)) && chave.unescaped == 'error'
  end

  # Hash LITERAL com a chave `error` (`{ error: ... }`). Argumento nomeado de método
  # (`Result.new(error: 'ai_unavailable')`) é `KeywordHashNode`, não `HashNode`, e fica de fora de
  # propósito: não é saída de ferramenta.
  def hashes_de_erro(caminho)
    achados = []
    cada_no(arvore(caminho)) do |nodo|
      next unless nodo.is_a?(Prism::HashNode) && nodo.elements.any? { |elemento| chave_error?(elemento) }

      achados << achado(caminho, nodo, nodo.slice)
    end
    achados
  end

  # -> [[achado, código], ...]
  def codigos_em_chamadas(caminho)
    achados = []
    cada_no(arvore(caminho)) do |nodo|
      next unless nodo.is_a?(Prism::CallNode) && registradores.include?(nodo.name)

      primeiro = nodo.arguments&.arguments&.first
      achados << [achado(caminho, nodo, primeiro.unescaped), primeiro.unescaped] if primeiro.is_a?(Prism::StringNode)
    end
    achados
  end

  # `return 'codigo' if ...` — a forma de `Bound#async_refusal`.
  def codigos_em_returns(caminho)
    achados = []
    cada_no(arvore(caminho)) do |nodo|
      next unless nodo.is_a?(Prism::ReturnNode)

      valor = nodo.arguments&.arguments&.first
      next unless valor.is_a?(Prism::StringNode) && valor.unescaped.match?(described_class::CODIGO)

      achados << [achado(caminho, nodo, valor.unescaped), valor.unescaped]
    end
    achados
  end

  def codigos_literais
    arquivos_varridos.flat_map { |caminho| codigos_em_chamadas(caminho) } + codigos_em_returns(bound)
  end

  describe 'guarda estática (entrega 6)' do
    it 'regra 1: nenhum { error: ... } literal fora do produtor unico' do
      fora = arquivos_varridos.flat_map { |caminho| hashes_de_erro(caminho) }

      expect(fora).to be_empty,
                      "saída de recusa sem registro — troque por Recusa.para_modelo / Bound#recusar:\n#{fora.join("\n")}"
    end

    it 'regra 1 (autoteste): o visitador enxerga o Hash do produtor unico' do
      expect(hashes_de_erro(produtor_unico).size).to eq(1)
    end

    it 'regra 2: todo codigo de recusa escrito no codigo tem frase no catalogo' do
      fora = codigos_literais.reject { |_achado, codigo| described_class::MOTIVOS.key?(codigo) }

      expect(fora).to be_empty,
                      "código de recusa fora de MOTIVOS (sem frase e sem exemplo):\n#{fora.map(&:first).join("\n")}"
    end

    it 'regra 3 (autoteste): a varredura enxerga as chamadas que existem' do
      literais = codigos_literais

      expect(literais.size).to be >= minimo_conhecido
      expect(literais.map(&:last)).to include('invalid_tool_arguments', 'faltam_dados', 'async_desligado')
    end
  end
end
