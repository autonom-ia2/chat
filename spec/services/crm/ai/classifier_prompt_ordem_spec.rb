require 'rails_helper'

# IA entende a conversa F1: a ordem da conversa e a promessa do nosso assistente só vão ao modelo com a flag
# `crm_ia_fatos_da_conversa`, no FIM do prefixo (o cache das contas sem a flag não muda), e o `handoff` ganha
# `promised_by_our_assistant`. Sem a flag, prompt e schema são os de antes, byte a byte.
RSpec.describe Crm::Ai::ClassifierPrompt do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL')
  end
  let(:fim) { "\n\n#{Crm::Ai::FatosDaConversa::ORDEM}" }

  def classificador(memoria: false)
    contexto = { current_stage: { id: card.stage_id, name: 'Novo' } }
    contexto = contexto.merge(memoria_refs: {}) if memoria
    Crm::Ai::StageClassifier.new(card: card, client: nil, stages: [], context: contexto)
  end

  def conjunta = Crm::Ai::ClassificacaoConjunta.new(client: nil, classificadores: [classificador], model: 'm')

  def handoff(schema) = schema[:schema][:properties][:handoff]

  it 'sem a flag, prompt e schema de sempre', :aggregate_failures do
    expect(described_class::TEXT).not_to include('ORDEM DA CONVERSA')
    expect(classificador.send(:instructions)).to equal(described_class::TEXT)
    expect(classificador.esquema).to equal(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA)
    expect(conjunta.send(:esquema)).to equal(Crm::Ai::ClassificacaoConjunta::SCHEMA)
    expect(conjunta.send(:instructions)).to eq(described_class::TEXT_VARIOS)
    expect(handoff(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA)[:properties]).not_to have_key(:promised_by_our_assistant)
  end

  context 'with the flag on' do
    before { account.enable_features!(Crm::Ai::FatosDaConversa::FLAG) }

    it 'o bloco vem no fim do prefixo, de um card e da conjunta, depois das outras flags', :aggregate_failures do
      expect(classificador.send(:instructions)).to eq("#{described_class::TEXT}#{fim}")
      expect(conjunta.send(:instructions)).to eq("#{described_class::TEXT_VARIOS}#{fim}")
      expect(described_class.para([], memoria: true, nao_e_negocio: true, fatos: true))
        .to eq("#{described_class::TEXT}\n\n#{described_class::NAO_E_NEGOCIO}\n\n#{described_class::MEMORIA}#{fim}")
    end

    it 'o handoff ganha a promessa no schema de um card (com e sem memória) e da conjunta', :aggregate_failures do
      [classificador.esquema, classificador(memoria: true).esquema].each do |schema|
        expect(handoff(schema)[:required]).to include('promised_by_our_assistant')
      end
      item = conjunta.send(:esquema)[:schema][:properties][:cards][:items]
      expect(handoff(schema: item)[:properties]).to have_key(:promised_by_our_assistant)
      expect(item[:required]).to include('card_id')
    end

    it 'com "não é negócio" também, os dois campos convivem' do
      account.enable_features!(Crm::Ai::NaoENegocio::FLAG)
      schema = classificador.esquema

      expect(schema[:schema][:required]).to include('nao_e_negocio')
      expect(handoff(schema)[:required]).to include('promised_by_our_assistant')
    end
  end
end
