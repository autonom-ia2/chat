require 'rails_helper'

# NÃO EXISTE TETO DE COTAÇÃO, E ISSO É DECISÃO DE PRODUTO (termo 6 da entrega 7).
#
# Havia um: 8 execuções por hora. Entrou sem aprovação e contava a unidade errada — uma execução
# aciona todas as seguradoras habilitadas (dezessete nas três cotações reais de 11/09/2026), então
# "8 por hora" eram até 136 consultas, e o número 8 não dizia nada sobre dinheiro. Rodrigo o removeu
# em 10/09/2026: quem paga é a corretora, e estrangular quem paga mais é o oposto do produto.
#
# ESTE ARQUIVO É A GUARDA PELO NOME, e o `async_config.rb` aponta para ele. O que pega qualquer
# forma de teto é o exemplo de COMPORTAMENTO, em `bound_async_spec`: vinte execuções na última hora
# e a vigésima primeira é aceita ("there is NO ceiling"). Os dois juntos cobrem os dois jeitos de o
# acidente voltar — a constante copiada de volta de um diff antigo, e a contagem escrita do zero.
#
# O que continua impedindo desperdício NÃO é teto: `opened_for_turn?` (o retry do mesmo turno não
# abre execução nova), a dedup por (conversa, ferramenta), e o pedido repetido da entrega 10, que
# compara os DADOS.
RSpec.describe Autonomia::Agents::Tools::AsyncConfig do
  # Tudo que decide se uma execução de ferramenta pode ser aberta ou seguir adiante.
  let(:caminho_da_execucao) do
    %w[app/services/autonomia/agents/tools app/jobs/autonomia/agents/tools
       app/models/autonomia/agents/tool_run.rb]
      .flat_map { |raiz| raiz.end_with?('.rb') ? [Rails.root.join(raiz).to_s] : Dir[Rails.root.join("#{raiz}/**/*.rb").to_s] }
  end

  # Os nomes que o acidente teve e os que ele teria. Comentário não conta: estes arquivos EXPLICAM a
  # decisão em prosa, e uma varredura que reprovasse a explicação apagaria o motivo junto com a regra.
  let(:nomes_de_teto) do
    /^\s*(?!#)[^#\n]*\b(MAX_RUNS[A-Z_]*|RUNS_PER_[A-Z_]+|[A-Z_]*PER_HOUR|TETO_DE_EXECUCOES|MAX_EXECUCOES)\b/
  end

  it 'nenhum teto de execuções foi reintroduzido no caminho da cotação' do
    # Arrange / Act
    achados = caminho_da_execucao.flat_map do |caminho|
      File.readlines(caminho).each_with_index
          .select { |linha, _| linha.match?(nomes_de_teto) }
          .map { |linha, i| "#{Pathname(caminho).relative_path_from(Rails.root)}:#{i + 1}  #{linha.strip}" }
    end

    # Assert
    expect(achados).to be_empty, 'teto de execuções de volta — quem paga a cotação é a corretora, e frear ' \
                                 "quem paga mais é o oposto do produto (10/09/2026):\n#{achados.join("\n")}"
  end
end
