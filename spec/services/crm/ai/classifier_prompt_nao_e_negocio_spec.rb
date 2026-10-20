require 'rails_helper'

# #1922: a regra "não é negócio" entra no fim do prefixo do classificador (o cache de tudo antes dela não muda) e o
# campo vai no schema de um card e da avaliação conjunta.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:fim) { "\n\n#{described_class::NAO_E_NEGOCIO}" }

  # Pega: a regra sumir do prompt ou entrar no meio do prefixo (todas as contas perderiam o cache de prompt).
  it 'a regra fica no fim do prefixo de um card, com e sem agentes de IA, e a conjunta começa por ele', :aggregate_failures do
    expect([described_class::TEXT, described_class::TEXT_COM_AGENTES_IA]).to all(end_with(fim))
    expect(described_class::TEXT_VARIOS).to start_with(described_class::TEXT)
  end

  # Pega: a regra deixar de proteger perda, silêncio de prospecção e começo de conversa (casos que não são lixo).
  it 'separa lixo de perda, de silêncio e de começo de conversa' do
    expect(described_class::NAO_E_NEGOCIO).to include('isso é perda', 'é silêncio, não lixo', 'a conversa está começando')
  end

  # Pega: o campo faltar no schema de um card ou da conjunta (o modelo não teria como dizer "não é negócio").
  it 'o campo é obrigatório e anulável no schema de um card e da avaliação conjunta', :aggregate_failures do
    [Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA[:schema], Crm::Ai::ClassificacaoConjunta::ITEM,
     Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA_MEMORIA[:schema]].each do |schema|
      expect(schema[:required]).to include('nao_e_negocio')
      expect(schema[:properties][:nao_e_negocio][:type]).to eq(%w[object null])
      expect(schema[:properties][:nao_e_negocio][:properties][:motivo][:enum]).to eq(Crm::Ai::NaoENegocio::MOTIVOS)
      expect(schema[:properties][:nao_e_negocio][:required]).to include('duplicado_de')
    end
  end

  # Pega: o lead que chega por anúncio (link, texto do anúncio) ou mostrando o que quer (foto, áudio) e some sem responder
  # ser tratado como lixo; e o repetido sem dizer qual card fica.
  it 'mídia ou link sozinho nunca é lixo, e o repetido aponta o card que fica' do
    expect(described_class::NAO_E_NEGOCIO).to include('chegou por um anúncio', '"duplicado_de"', 'funis diferentes')
  end
end
