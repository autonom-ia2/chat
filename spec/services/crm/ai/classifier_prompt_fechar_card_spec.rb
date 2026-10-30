require 'rails_helper'

# IA entende a conversa F3: a regra de fechar o card só vai ao modelo com a flag `crm_ia_fecha_card`, no FIM do prefixo
# (o cache das contas sem a flag não muda); o schema ganha `fechar_card` e o "não é negócio" ganha o motivo "teste".
# Sem a flag, prompt e schema são os de antes, byte a byte.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL')
  end
  let(:fim) { "\n\n#{Crm::Ai::FecharCard::INSTRUCAO}" }

  def classificador(memoria: false)
    contexto = { current_stage: { id: card.stage_id, name: 'Novo' } }
    contexto = contexto.merge(memoria_refs: {}) if memoria
    Crm::Ai::StageClassifier.new(card: card, client: nil, stages: [], context: contexto)
  end

  def conjunta = Crm::Ai::ClassificacaoConjunta.new(client: nil, classificadores: [classificador], model: 'm')

  def motivos(schema) = schema[:schema][:properties][:nao_e_negocio][:properties][:motivo][:enum]

  it 'sem a flag, prompt e schema de sempre', :aggregate_failures do
    expect(described_class::TEXT).not_to include('FECHAR O CARD')
    expect(classificador.send(:instructions)).to equal(described_class::TEXT)
    expect(classificador.esquema).to equal(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA)
    expect(conjunta.send(:esquema)).to equal(Crm::Ai::ClassificacaoConjunta::SCHEMA)
    expect(conjunta.send(:instructions)).to eq(described_class::TEXT_VARIOS)
  end

  it 'sem a flag, o "não é negócio" segue sem o motivo "teste"' do
    account.enable_features!(Crm::Ai::NaoENegocio::FLAG)

    expect(motivos(classificador.esquema)).to eq(Crm::Ai::NaoENegocio::MOTIVOS)
    expect(classificador.send(:instructions)).to eq("#{described_class::TEXT}\n\n#{described_class::NAO_E_NEGOCIO}")
  end

  context 'with the flag on' do
    before { account.enable_features!(Crm::Ai::FecharCard::FLAG) }

    it 'o bloco vem no fim do prefixo, de um card e da conjunta, depois das outras flags', :aggregate_failures do
      expect(classificador.send(:instructions)).to eq("#{described_class::TEXT}#{fim}")
      expect(conjunta.send(:instructions)).to eq("#{described_class::TEXT_VARIOS}#{fim}")
      expect(described_class.para([], memoria: true, fatos: true, fecha_card: true))
        .to eq("#{described_class::TEXT}\n\n#{described_class::MEMORIA}\n\n#{Crm::Ai::FatosDaConversa::ORDEM}#{fim}")
    end

    it 'o campo vai ao schema de um card (com e sem memória) e ao item da conjunta', :aggregate_failures do
      [classificador.esquema, classificador(memoria: true).esquema].each do |schema|
        expect(schema[:schema][:required]).to include('fechar_card')
        expect(schema[:schema][:properties][:fechar_card]).to eq(Crm::Ai::FecharCard::CAMPO)
      end
      item = conjunta.send(:esquema)[:schema][:properties][:cards][:items]
      expect(item[:required]).to include('card_id', 'fechar_card')
    end

    # Pega (regra c): o schema oferecer "ganho" ao modelo.
    it 'o resultado nunca é ganho' do
      expect(Crm::Ai::FecharCard::CAMPO[:properties][:resultado][:enum]).to contain_exactly('perdido', 'resolvido')
    end

    it 'com "não é negócio": o motivo "teste" no enum e a regra dele depois do bloco', :aggregate_failures do
      account.enable_features!(Crm::Ai::NaoENegocio::FLAG)

      expect(motivos(classificador.esquema)).to eq([*Crm::Ai::NaoENegocio::MOTIVOS, 'teste'])
      expect(classificador.send(:instructions))
        .to eq("#{described_class::TEXT}\n\n#{described_class::NAO_E_NEGOCIO}#{fim}\n\n#{Crm::Ai::FecharCard::TESTE}")
      expect(Crm::Ai::NaoENegocio::CAMPO[:properties][:motivo][:enum]).to eq(Crm::Ai::NaoENegocio::MOTIVOS)
    end
  end
end
