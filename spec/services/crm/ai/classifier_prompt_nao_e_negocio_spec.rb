require 'rails_helper'

# #1922: a regra "não é negócio" e o campo `nao_e_negocio` só vão ao modelo com a flag `crm_ia_arquiva_lixo`. Com ela, a
# regra entra logo depois do prefixo de sempre (o cache de tudo antes dela não muda); sem ela, prompt e schema são os de
# antes, byte a byte.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL')
  end
  let(:fim) { "\n\n#{described_class::NAO_E_NEGOCIO}" }

  def classificador(memoria: false)
    contexto = { current_stage: { id: card.stage_id, name: 'Novo' } }
    contexto = contexto.merge(memoria_refs: {}) if memoria
    Crm::Ai::StageClassifier.new(card: card, client: nil, stages: [], context: contexto)
  end

  def conjunta(memoria: false)
    Crm::Ai::ClassificacaoConjunta.new(client: nil, classificadores: [classificador(memoria: memoria)], model: 'm')
  end

  def campo(schema) = schema[:schema][:properties][:nao_e_negocio]

  def itens(schema) = schema[:schema][:properties][:cards][:items]

  describe 'sem a flag (padrão)' do
    # Pega: a regra ou o campo vazarem para as contas sem a flag (prompt, cache e resposta mudariam em todas).
    it 'prompt e schema são os de antes, de um card e da conjunta', :aggregate_failures do
      expect(described_class::TEXT).not_to include('NÃO É NEGÓCIO')
      expect(described_class.para([])).to equal(described_class::TEXT)
      expect(described_class.para_varios([])).to equal(described_class::TEXT_VARIOS)
      expect(classificador.esquema).to equal(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA)
      expect(classificador(memoria: true).esquema).to equal(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA_MEMORIA)
      expect(classificador.send(:instructions)).to equal(described_class::TEXT)
      expect(conjunta.send(:esquema)).to equal(Crm::Ai::ClassificacaoConjunta::SCHEMA)
      expect(conjunta.send(:instructions)).to eq(described_class::TEXT_VARIOS)
      expect(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA[:schema][:properties]).not_to have_key(:nao_e_negocio)
    end
  end

  describe 'com a flag `crm_ia_arquiva_lixo`' do
    before { account.enable_features!(Crm::Ai::NaoENegocio::FLAG) }

    # Pega: a regra entrar no meio do prefixo (o cache de tudo antes dela se perderia) ou sumir da conjunta.
    it 'a regra vem logo depois do prefixo de sempre, de um card e da conjunta', :aggregate_failures do
      expect(classificador.send(:instructions)).to eq("#{described_class::TEXT}#{fim}")
      expect(described_class.para(['Lia (agente de IA)'], nao_e_negocio: true)).to eq("#{described_class::TEXT_COM_AGENTES_IA}#{fim}")
      expect(conjunta.send(:instructions)).to eq("#{described_class::TEXT}#{fim}\n\n#{described_class::VARIOS}")
      expect(described_class.para([], memoria: true, nao_e_negocio: true))
        .to eq("#{described_class::TEXT}#{fim}\n\n#{described_class::MEMORIA}")
    end

    # Pega: o campo faltar no schema de um card ou da conjunta (o modelo não teria como dizer "não é negócio").
    it 'o campo é obrigatório e anulável no schema de um card, com e sem memória, e da conjunta', :aggregate_failures do
      [classificador.esquema, classificador(memoria: true).esquema].each do |schema|
        expect(schema[:schema][:required]).to include('nao_e_negocio')
        expect(campo(schema)).to eq(Crm::Ai::NaoENegocio::CAMPO)
      end
      expect(classificador(memoria: true).esquema[:schema][:required].last(2)).to eq(%w[nao_e_negocio memoria_ops])
      item = itens(conjunta.send(:esquema))
      expect(item[:required]).to include('card_id', 'nao_e_negocio')
      expect(item[:properties][:nao_e_negocio][:type]).to eq(%w[object null])
      expect(itens(conjunta(memoria: true).send(:esquema))[:required]).to include('nao_e_negocio', 'memoria_ops')
    end

    # Pega: a flag do e-mail (#1828) e esta se atropelarem: uma das duas sumir do schema ou do prompt.
    it 'junto com a flag `email_autoria`, os dois campos e as duas regras vão ao modelo', :aggregate_failures do
      account.enable_features!(Crm::Email::Autoria::FLAG)

      expect(classificador.esquema[:schema][:required]).to include('nao_e_negocio', Crm::Email::SaidaDaCopia::CAMPO)
      expect(conjunta.send(:esquema)[:schema][:required]).to include(Crm::Email::SaidaDaCopia::CAMPO)
      expect(itens(conjunta.send(:esquema))[:required]).to include('nao_e_negocio')
      expect(conjunta.send(:instructions)).to start_with("#{described_class::TEXT}#{fim}\n\n#{described_class::VARIOS}")
      expect(conjunta.send(:instructions)).to include(Crm::Email::Autoria::LEGENDA)
    end
  end

  # Pega: a regra deixar de proteger perda, silêncio de prospecção e começo de conversa (casos que não são lixo).
  it 'separa lixo de perda, de silêncio e de começo de conversa' do
    expect(described_class::NAO_E_NEGOCIO).to include('isso é perda', 'é silêncio, não lixo', 'a conversa está começando')
  end

  # Pega: o lead que chega por anúncio (link, texto do anúncio) ou mostrando o que quer (foto, áudio) e some sem responder
  # ser tratado como lixo; e o repetido sem dizer qual card fica.
  it 'mídia ou link sozinho nunca é lixo, e o repetido aponta o card que fica' do
    expect(described_class::NAO_E_NEGOCIO).to include('chegou por um anúncio', '"duplicado_de"', 'funis diferentes')
  end
end
