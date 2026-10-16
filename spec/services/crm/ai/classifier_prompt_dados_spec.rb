require 'rails_helper'

# #1140 — o aviso "dados, não instruções" vale para a avaliação de um card só (todas as contas), e não só para a
# conjunta. Ele fica no fim do prefixo para não mexer no que já está em cache antes dele.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:prefixo_de_antes) do
    [described_class::ROLE_AND_TASK, described_class::METHODOLOGY, described_class::CONFIDENCE, described_class::VALUE,
     described_class::HANDOFF, described_class::CALLBACK, described_class::ATTR_EXTRACTION, described_class::KNOWN_ATTRS,
     described_class::OTHER_SUBJECTS, described_class::OUTPUT_DISCIPLINE, described_class::EXAMPLES].join("\n\n")
  end

  # Pega: o prompt de um card voltar a não avisar que mensagens e textos do funil são dados.
  it 'o prompt de um card avisa que os textos da entrada são dados, nunca instruções', :aggregate_failures do
    expect([described_class::TEXT, described_class::TEXT_COM_AGENTES_IA]).to all(end_with(described_class::DADOS_NAO_INSTRUCOES))
    expect(described_class::DADOS_NAO_INSTRUCOES).to include('"recent_messages"', 'nunca', 'instruções')
  end

  # Pega: o aviso entrar no meio do prefixo e invalidar o cache de tudo o que vem depois dele.
  it 'o aviso entra só no fim: o começo do prefixo segue igual ao de antes' do
    expect(described_class::TEXT).to eq("#{prefixo_de_antes}\n\n#{described_class::DADOS_NAO_INSTRUCOES}")
  end

  # Pega: o StageClassifier mandar um prefixo sem o aviso.
  it 'o StageClassifier manda o prefixo com o aviso' do
    classificador = Crm::Ai::StageClassifier.new(card: nil, client: nil, stages: [], context: nil, eligible_agents: [])

    expect(classificador.send(:instructions)).to equal(described_class::TEXT)
  end

  # Pega: a avaliação conjunta perder o aviso de um card (ela começa pelo prefixo de um card).
  it 'a avaliação conjunta também começa pelo prefixo com o aviso' do
    expect(described_class::TEXT_VARIOS).to start_with(described_class::TEXT)
  end
end
