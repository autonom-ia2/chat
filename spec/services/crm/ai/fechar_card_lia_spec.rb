require 'rails_helper'

# IA entende a conversa F3 (revisão adversarial, item 1): enquanto o agente de cotação (o protegido, `instrucao_mantida?`)
# atende a conversa, a IA do CRM não fecha o card, não sugere fechar nem sugere "era teste" por cima dele. A guarda é a
# mesma da F1 (Crm::Ai::FatosDaConversa.agente_protegido?). O comportamento do agente de cotação não muda.
RSpec.describe Crm::Ai::FecharCard do
  include_context 'with crm responsible agent'

  let(:card) { create_card(pipeline: comercial) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  before do
    comercial.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
    account.enable_features!(described_class::FLAG, Crm::Ai::NaoENegocio::FLAG)
  end

  def ia_responde(fechar_card: nil, nao_e_negocio: nil)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    resposta = { suggested_stage_id: card.stage_id, confidence: 0.9, reasoning: 'x', model_used: 'm', fechar_card: fechar_card,
                 nao_e_negocio: nao_e_negocio, handoff: nil }.with_indifferent_access
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(instance_double(Crm::Ai::StageClassifier, perform: resposta))
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  def fim(confidence:) = { resultado: 'perdido', motivo: 'recusou', retorno_em: nil, confidence: confidence, reasoning: 'Não quer.' }

  def avaliar = Crm::Ai::Evaluator.new(card: card, trigger: 'message').perform

  def sugestoes = account.crm_ai_stage_suggestions.where(card: card)

  describe 'com o agente de cotação no nome da conversa' do
    # A porta da caixa (dona da conversa, no shared context) é o agente de cotação. O tipo só nasce assim pelo banco: a API
    # e o modelo recusam trocar o tipo de um agente para o de cotação.
    before { agente_da_porta.update_columns(agent_type: 'insurance_quote') } # rubocop:disable Rails/SkipsModelValidations

    it 'a guarda reconhece o agente de cotação atendendo' do
      expect(Crm::Ai::FatosDaConversa.agente_protegido_atendendo?(card)).to be(true)
    end

    it 'não fecha sozinho, nem com confiança alta', :aggregate_failures do
      ia_responde(fechar_card: fim(confidence: 0.99))

      avaliar

      expect(card.reload).to be_open
      expect(sugestoes).to be_empty
    end

    it 'não sugere fechar' do
      ia_responde(fechar_card: fim(confidence: 0.8))

      avaliar

      expect(sugestoes).to be_empty
    end

    it 'não sugere "era teste"' do
      ia_responde(nao_e_negocio: { motivo: 'teste', confidence: 0.99, reasoning: 'Era teste.', duplicado_de: nil })

      avaliar

      expect(sugestoes).to be_empty
    end
  end

  describe 'sem o agente de cotação atendendo' do
    it 'outro agente nosso no nome: fecha como sempre', :aggregate_failures do
      expect(Crm::Ai::FatosDaConversa.agente_protegido_atendendo?(card)).to be(false)
      ia_responde(fechar_card: fim(confidence: 0.99))

      avaliar

      expect(card.reload).to be_lost
    end

    it 'outro agente nosso no nome: sugere fechar e "era teste" como sempre', :aggregate_failures do
      ia_responde(fechar_card: fim(confidence: 0.8))
      avaliar
      expect(sugestoes.pending.sole.fechar).to include('resultado' => 'perdido')

      card.update!(metadata: {})
      ia_responde(nao_e_negocio: { motivo: 'teste', confidence: 0.99, reasoning: 'Era teste.', duplicado_de: nil })
      avaliar
      expect(sugestoes.pending.sole.fechar).to include('resultado' => described_class::ARQUIVADO)
    end

    it 'conversa já resolvida com o agente de cotação no nome: ele não está atendendo' do
      agente_da_porta.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
      conversation.update!(status: :resolved)

      expect(Crm::Ai::FatosDaConversa.agente_protegido_atendendo?(card)).to be(false)
    end
  end
end
