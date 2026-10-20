require 'rails_helper'

# #1593 — o parágrafo dos agentes de IA no prefixo do classificador só entra quando a lista de elegíveis tem um agente
# de IA (a Fase 2). Sem ele, o prefixo é o TEXT de sempre, byte a byte: o cache de prompt das contas fora do piloto não
# muda.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:partes_de_antes) do
    [described_class::ROLE_AND_TASK, described_class::METHODOLOGY, described_class::CONFIDENCE, described_class::VALUE,
     described_class::HANDOFF, described_class::CALLBACK, described_class::ATTR_EXTRACTION, described_class::KNOWN_ATTRS,
     described_class::OTHER_SUBJECTS, described_class::OUTPUT_DISCIPLINE, described_class::EXAMPLES]
  end

  # Pega: o parágrafo novo vazando para o prefixo de quem não tem agente de IA (muda o prompt e quebra o cache).
  it 'sem agente de IA entre os elegíveis: o mesmo prefixo de antes, sem o parágrafo', :aggregate_failures do
    [[], ['Ana Souza', 'Bruno Lima'], nil].each do |elegiveis|
      expect(described_class.para(elegiveis)).to equal(described_class::TEXT)
    end
    # #1140: o aviso de dados entra no fim, depois de todas as partes de antes; #1922: a regra "não é negócio" depois dele.
    expect(described_class::TEXT).to eq([*partes_de_antes, described_class::DADOS_NAO_INSTRUCOES, described_class::NAO_E_NEGOCIO].join("\n\n"))
    expect(described_class::TEXT).not_to include('(agente de IA)')
    expect(described_class::HANDOFF).to end_with('Não invente nomes fora da lista.')
  end

  # Pega: o classificador voltar a mandar sempre o TEXT (a explicação do rótulo sumiria no piloto em silêncio).
  it 'o StageClassifier manda o prefixo certo para a lista de elegíveis', :aggregate_failures do
    instrucoes = lambda do |elegiveis|
      Crm::Ai::StageClassifier.new(card: nil, client: nil, stages: [], context: nil, eligible_agents: elegiveis)
                              .send(:instructions)
    end

    expect(instrucoes.call(['Lia (agente de IA)'])).to equal(described_class::TEXT_COM_AGENTES_IA)
    expect(instrucoes.call([])).to equal(described_class::TEXT)
  end

  # Pega: o rótulo "(agente de IA)" chegando ao modelo sem a explicação de que é um atendente.
  it 'com um agente de IA entre os elegíveis: o parágrafo entra logo depois do HANDOFF', :aggregate_failures do
    prefixo = described_class.para(['Ana Souza', 'Lia (agente de IA)'])

    expect(prefixo).to equal(described_class::TEXT_COM_AGENTES_IA)
    expect(prefixo).to eq(described_class::TEXT.sub(described_class::HANDOFF, "#{described_class::HANDOFF}\n\n#{described_class::AGENTES_IA}"))
  end
end
