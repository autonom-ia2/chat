require 'rails_helper'

# TERMO 5 DA ENTREGA 7 — NADA AQUI VIRA FREIO.
#
# A medida informa; quem decide volume é a corretora que paga. O jeito de a medida virar freio é
# banal e silencioso: alguém a chama de dentro do aceite, do `start` ou do job "só para conferir" e,
# do dia seguinte em diante, a corretora que cota mais é a que o agente para de atender. Foi assim
# que nasceu o teto de "8 por hora" removido em 10/09/2026.
#
# A guarda é por ALCANCE: a medida só pode ser NOMEADA pelas superfícies de leitura. Uma referência
# nova em qualquer outro lugar reprova aqui, e quem a escrever é obrigado a encarar a decisão em vez
# de repetir o acidente.
#
# POR AST (Prism), como a varredura de recusas: busca textual acusaria o comentário que EXPLICA a
# decisão — e uma guarda que reprova a explicação apaga o motivo junto com a regra.
RSpec.describe Autonomia::Insurance::Medida do
  # Onde a medida PODE aparecer: ela mesma, a porta da conta (a corretora vê o retorno) e a página do
  # Super Admin (a operação cobra). Nenhum arquivo de ferramenta, job ou aceite.
  let(:leitores) do
    ['app/controllers/api/v1/accounts/autonomia/insurance/measurement_controller.rb',
     'app/controllers/super_admin/insurance_measurements_controller.rb',
     'app/services/autonomia/insurance/medida.rb',
     'app/views/super_admin/insurance_measurements/show.html.erb']
  end

  let(:escritas_proibidas) do
    %w[update update! update_all create create! destroy destroy_all save save! delete_all insert]
  end

  # Tudo que roda no caminho da cotação: a ferramenta, o aceite, o job, o especialista.
  let(:caminho_da_cotacao) do
    relativos(%w[app/services/autonomia/agents app/jobs/autonomia/agents app/services/autonomia/insurance]
                .flat_map { |raiz| Dir[Rails.root.join("#{raiz}/**/*.rb").to_s] })
  end

  def relativos(caminhos)
    caminhos.map { |caminho| Pathname(caminho).relative_path_from(Rails.root).to_s }.sort
  end

  # O nome da medida ESCRITO COMO CÓDIGO. Em `.rb`, uma constante na árvore; em `.erb`, texto (a
  # única superfície ERB desta entrega é a página do Super Admin, que é leitura declarada).
  def nomeiam_a_medida(caminhos)
    caminhos.select do |caminho|
      caminho.end_with?('.erb') ? File.read(Rails.root.join(caminho)).include?('Insurance::Medida') : constante_em?(caminho)
    end
  end

  def constante_em?(caminho)
    achou = false
    VarreduraDeRecusas.cada_no(VarreduraDeRecusas.arvore(caminho)) do |nodo, _metodo|
      achou ||= nodo.is_a?(Prism::ConstantPathNode) && nodo.slice.end_with?('Insurance::Medida')
    end
    achou
  end

  it 'so e nomeada pelas superficies de leitura' do
    # Arrange
    todos = relativos(Dir[Rails.root.join('app/**/*.rb').to_s] + Dir[Rails.root.join('app/**/*.erb').to_s])

    # Act
    citam = nomeiam_a_medida(todos)

    # Assert
    expect(citam).to eq(leitores),
                     "a medida virou dependência de quem não só lê — isto é o freio entrando pela porta dos fundos:\n" \
                     "#{(citam - leitores).join("\n")}"
  end

  # O mesmo invariante dito onde ele dói: nenhum arquivo que roda durante uma cotação alcança a
  # medida. Sem isto, "quanto você já cotou este mês" acaba virando condição para cotar.
  it 'nao e alcancada de dentro do caminho da cotação' do
    citam = nomeiam_a_medida(caminho_da_cotacao) - ['app/services/autonomia/insurance/medida.rb']

    expect(citam).to be_empty, "a medida entrou no caminho da cotação:\n#{citam.join("\n")}"
  end

  # E ela não escreve: é consulta. Uma medida que gravasse estado teria como marcar quem "já usou
  # demais" — e a partir daí o freio é uma linha.
  it 'nao escreve nada' do
    escritas = []
    VarreduraDeRecusas.cada_no(VarreduraDeRecusas.arvore('app/services/autonomia/insurance/medida.rb')) do |nodo, _m|
      escritas << nodo.name.to_s if nodo.is_a?(Prism::CallNode) && escritas_proibidas.include?(nodo.name.to_s)
    end

    expect(escritas).to be_empty, "a medida passou a escrever: #{escritas.uniq.join(', ')}"
  end
end
