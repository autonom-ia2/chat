require 'rails_helper'

# O CHECKLIST DO RAMO (receita v3): todo especialista de `Builder::ESPECIALISTAS` fora auto tem o
# `docs/insurance/receita-de-ramo/piloto-<ramo>.md` com a seção "## Checklist", e nela uma tabela com os itens da
# receita, cada um `ok` com evidência ou `aberto` com motivo. É o que o Rodrigo lê para liberar o ramo na conta.
#
# A TABELA. Uma linha por item, na ordem de `ITENS`; o id na primeira coluna, o estado na penúltima e a evidência (ou
# o motivo) na última. As colunas do meio (o item, a fase) são livres:
#
#   | # | Item | Estado | Evidência ou motivo |
#   |---|---|---|---|
#   | R1 | Decisão do Rodrigo | ok | chat#641, 24/09/2026 |
#   | R2 | Jornada de auto preenchida | aberto | falta a linha do fecho |
#
# Lida com método de string: a linha que começa com "|" é quebrada em "|".
module ChecklistDoRamo
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  PASTA = Rails.root.join('docs/insurance/receita-de-ramo')
  TITULO = '## Checklist'.freeze
  # Os itens da receita v3. Os títulos vêm com a receita (chat#642); por ora, só os ids.
  ITENS = (1..26).map { "R#{it}" }.freeze
  ESTADOS = %w[ok aberto].freeze

  Linha = Struct.new(:id, :estado, :evidencia)

  module_function

  def especialistas
    BUILDER::ESPECIALISTAS.reject { |dados| dados[:ramo] == 'auto' }
  end

  def piloto(ramo)
    PASTA.join("piloto-#{ramo}.md")
  end

  # As linhas da tabela da seção "## Checklist", até a próxima seção de nível 2. Cabeçalho e separador ficam de fora.
  # -> nil sem a seção.
  def linhas(texto)
    secao = secao(texto)
    return nil if secao.nil?

    secao.filter_map do |linha|
      next unless linha.strip.start_with?('|')

      celulas = linha.strip.delete_prefix('|').delete_suffix('|').split('|', -1).map(&:strip)
      next if celulas.first == '#' || celulas.first.to_s.start_with?('-')

      Linha.new(celulas.first, celulas[-2], celulas.last)
    end
  end

  def secao(texto)
    todas = texto.lines
    inicio = todas.index { |linha| linha.strip == TITULO }
    return nil if inicio.nil?

    depois = todas.drop(inicio + 1)
    fim = depois.index { |linha| linha.start_with?('## ') } || depois.size
    depois.take(fim)
  end
end

RSpec.describe 'O checklist do ramo' do # rubocop:disable RSpec/DescribeClass
  ChecklistDoRamo.especialistas.each do |dados|
    describe "o piloto de #{dados[:ramo]}" do
      let(:caminho) { ChecklistDoRamo.piloto(dados[:ramo]) }
      let(:linhas) { caminho.exist? ? ChecklistDoRamo.linhas(caminho.read) : nil }

      it 'existe, com a seção de checklist' do
        expect(caminho).to exist, "falta #{caminho.relative_path_from(Rails.root)} (a receita manda copiá-lo no primeiro dia)"
        expect(linhas).not_to be_nil, "#{caminho.relative_path_from(Rails.root)} sem a seção \"#{ChecklistDoRamo::TITULO}\""
      end

      it 'tem os itens da receita, na ordem, sem faltar nem sobrar' do
        expect(linhas&.map(&:id)).to eq(ChecklistDoRamo::ITENS)
      end

      it 'cada item está ok com evidência, ou aberto com motivo' do
        expect(linhas).not_to be_nil, "sem #{caminho.relative_path_from(Rails.root)} ou sem a seção #{ChecklistDoRamo::TITULO}"

        linhas.each do |linha|
          expect(ChecklistDoRamo::ESTADOS).to include(linha.estado), "#{linha.id}: estado \"#{linha.estado}\""
          expect(linha.evidencia.to_s).not_to be_empty, "#{linha.id} #{linha.estado} sem evidência nem motivo"
        end
      end
    end
  end

  # AUTOTESTE: a leitura da tabela, num piloto de mentira.
  describe 'a leitura' do
    let(:piloto) do
      <<~MD
        # Piloto

        ## Checklist

        | # | Item | Estado | Evidência ou motivo |
        |---|---|---|---|
        | R1 | Decisão | ok | chat#641 |
        | R2 | Jornada | aberto |  |

        ## Outra seção

        | R3 | fora da seção | ok | x |
      MD
    end

    it 'lê só a tabela da seção, com id, estado e evidência' do
      linhas = ChecklistDoRamo.linhas(piloto)

      expect(linhas.map(&:to_a)).to eq([%w[R1 ok chat#641], ['R2', 'aberto', '']])
    end

    it 'sem a seção, nada' do
      expect(ChecklistDoRamo.linhas("# Piloto\n\n| R1 | x | ok | y |\n")).to be_nil
    end
  end
end
