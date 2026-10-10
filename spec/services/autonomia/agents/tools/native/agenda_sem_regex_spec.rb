require 'rails_helper'
require 'prism'

# RA-09 / J6-A2 (#1196): a agenda da IA não interpreta o que a pessoa escreveu com expressão regular nem lista de
# palavras. Quem entende "a de quarta" é o modelo; as ferramentas recebem dados estruturados e conferem por parser.
# Pela árvore (Prism), não por texto: comentário que fala de regex não reprova; um `/x/`, `Regexp.new`, `match?`,
# `=~` ou `scan` no código reprova com arquivo e linha.
RSpec.describe 'Agenda da IA sem regex' do # rubocop:disable RSpec/DescribeClass
  let(:arquivos_da_agenda) do
    %w[
      app/services/autonomia/agents/tools/native/agenda.rb
      app/services/autonomia/agents/tools/native/horarios_disponiveis.rb
      app/services/autonomia/agents/tools/native/agendar_reuniao.rb
    ]
  end
  let(:nos_de_regex) do
    [Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode, Prism::MatchLastLineNode,
     Prism::InterpolatedMatchLastLineNode, Prism::MatchWriteNode, Prism::MatchPredicateNode, Prism::MatchRequiredNode]
  end
  let(:chamadas_de_regex) { %i[=~ !~ match match? scan] }

  def achados(caminho)
    lista = []
    visitar(Prism.parse_file(Rails.root.join(caminho).to_s).value) do |nodo|
      lista << "#{caminho}:#{nodo.location.start_line} #{nodo.slice.lines.first.strip}" if regex?(nodo)
    end
    lista
  end

  def visitar(nodo, &)
    return if nodo.nil?

    yield nodo
    nodo.compact_child_nodes.each { |filho| visitar(filho, &) }
  end

  def regex?(nodo)
    return true if nos_de_regex.any? { |tipo| nodo.is_a?(tipo) }
    return false unless nodo.is_a?(Prism::CallNode)

    chamadas_de_regex.include?(nodo.name) || (nodo.receiver.respond_to?(:name) && nodo.receiver.name == :Regexp)
  end

  it 'nenhum arquivo da agenda usa expressão regular' do
    expect(arquivos_da_agenda.flat_map { |caminho| achados(caminho) }).to be_empty
  end

  it 'a varredura enxerga regex quando ela existe (autoteste)' do
    arvore = Prism.parse("x = 'a'.match?(/b/)\ny = Regexp.new('c')\nz = 'd' =~ /e/").value
    encontrados = []
    visitar(arvore) { |nodo| encontrados << nodo if regex?(nodo) }

    expect(encontrados.size).to be >= 4
  end
end
