require 'rails_helper'

# IA entende a conversa F3 (flag `crm_ia_fecha_card`), o caminho do Crm::Ai::Evaluator depois de a IA fechar o card: não
# passa a conversa nem pontua; o "adiou" ganha o lembrete de retorno (regra a); "era teste" vira sugestão (regra k); e,
# com uma pessoa mexendo na etapa há pouco, VOLTAR vira sugestão (regra h, D1). O modelo é simulado.
RSpec.describe Crm::Ai::Evaluator do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil_e_etapa) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
    [pipeline, stage]
  end
  let(:pipeline) { funil_e_etapa.first }
  let(:stage) { funil_e_etapa.last }
  let(:conversa) { create(:conversation, account: account) }
  let(:card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL', primary_conversation: conversa) }
  let(:fuso) { Crm::Timezone::Resolver.new(account: account).zone_or_default }

  before { account.enable_features!(Crm::Ai::FecharCard::FLAG) }

  def ia_responde(resposta)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    classificador = instance_double(Crm::Ai::StageClassifier, perform: { confidence: 0.9, reasoning: 'x', model_used: 'm' }.merge(resposta)
                                                                                                                          .with_indifferent_access)
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  def adiou(retorno_em: nil)
    { fechar_card: { resultado: 'perdido', motivo: 'adiou', retorno_em: retorno_em, confidence: 0.96, reasoning: 'Agora não.' },
      suggested_stage_id: stage.id }
  end

  def avaliar(trigger: 'message') = described_class.new(card: card, trigger: trigger).perform

  def retornos = Crm::FollowUp.where(card: card).where("metadata ->> 'source' = ?", Crm::FollowUps::CallbackScheduler::SOURCE)

  def as_nove(dia) = fuso.parse("#{dia.iso8601} 09:00")

  describe 'depois de fechar' do
    # Pega: o card fechado pela IA passar a conversa ou mexer na pontuação (isso é de card aberto).
    it 'não passa a conversa nem pontua; os campos e a memória seguem', :aggregate_failures do
      allow(Crm::Ai::Config).to receive(:handoff_settings).and_return(enabled: true, trigger: 'quando pedir uma pessoa')
      allow(Crm::Ai::HandoffExecutor).to receive(:new)
      allow(Crm::Ai::ScoreApplier).to receive(:new)
      allow(Crm::Memoria::Pendente).to receive(:aplicar!)
      ia_responde(fechar_card: { resultado: 'perdido', motivo: 'recusou', retorno_em: nil, confidence: 0.96, reasoning: 'Não quer.' },
                  suggested_stage_id: stage.id)

      expect(avaliar.status).to eq(:closed)
      expect(Crm::Ai::HandoffExecutor).not_to have_received(:new)
      expect(Crm::Ai::ScoreApplier).not_to have_received(:new)
      expect(Crm::Memoria::Pendente).to have_received(:aplicar!).with(card)
      expect(retornos).to be_empty
    end
  end

  describe 'retorno do "adiou" (regra a)' do
    it 'sem data do cliente: lembrete em 30 dias, às 9 h do fuso, marcado como adiou', :aggregate_failures do
      ia_responde(adiou)

      avaliar

      lembrete = retornos.sole
      expect(lembrete.due_at).to eq(as_nove(fuso.today + 30))
      expect(lembrete).to be_reminder_only
      expect(lembrete.metadata).to include('source' => 'ai_callback', 'motivo' => 'adiou')
      expect(lembrete.title).to eq(I18n.t('crm.ai_fechar_card.retorno', locale: :en))
      expect(card.reload).to be_lost
    end

    it 'com a data dita pelo cliente: o lembrete é nela' do
      ia_responde(adiou(retorno_em: (fuso.today + 45).iso8601))

      avaliar

      expect(retornos.sole.due_at).to eq(as_nove(fuso.today + 45))
    end

    # Pega: uma data lida errado (longe demais) virar lembrete para daqui a anos.
    it 'data fora do horizonte do retorno: cai nos 30 dias' do
      ia_responde(adiou(retorno_em: (fuso.today + 400).iso8601))

      avaliar

      expect(retornos.sole.due_at).to eq(as_nove(fuso.today + 30))
    end

    # Pega: criar retorno num funil em que a equipe desligou o retorno da IA.
    it 'funil com o retorno desligado: fecha e não cria lembrete', :aggregate_failures do
      pipeline.update!(metadata: pipeline.metadata.deep_merge('ai' => { 'callback_enabled' => false }))
      ia_responde(adiou)

      avaliar

      expect(card.reload).to be_lost
      expect(retornos).to be_empty
    end

    it 'recusou: fecha sem lembrete' do
      ia_responde(adiou.deep_merge(fechar_card: { motivo: 'recusou' }))

      avaliar

      expect(retornos).to be_empty
    end
  end

  describe '"era teste" (regra k)' do
    before { account.enable_features!(Crm::Ai::NaoENegocio::FLAG) }

    let(:teste) do
      { nao_e_negocio: { motivo: 'teste', confidence: 0.9, reasoning: 'Era um teste.', duplicado_de: nil }, suggested_stage_id: stage.id }
    end

    # Pega (decisão do Rodrigo, 22/10): arquivar sozinho um "teste" que não era (estresse-09:1 da F5, confiança 0,99).
    it 'nunca arquiva sozinho, nem com confiança máxima: vira sugestão de arquivar', :aggregate_failures do
      ia_responde(teste.deep_merge(nao_e_negocio: { confidence: 0.99 }))

      resultado = avaliar

      expect(resultado.status).to eq(:suggested)
      expect(card.reload).to be_open
      expect(resultado.suggestion.fechar).to eq('resultado' => 'arquivado', 'motivo' => 'teste')
      expect(Crm::Activity.where(card: card, event_type: 'archive')).to be_empty
    end

    it 'aceita, arquiva como não é negócio, sem perda, com a pessoa como autora', :aggregate_failures do
      ia_responde(teste)
      sugestao = avaliar.suggestion

      Crm::Ai::SuggestionApplier.new(card: card, suggestion: sugestao, actor: admin).perform

      expect(card.reload).to have_attributes(status: 'archived', closed_at: nil)
      expect(Crm::Activity.where(card: card, event_type: 'archive').sole)
        .to have_attributes(actor_type: 'user', payload: include('motivo' => 'teste', 'sugestao_da_ia' => sugestao.id))
      expect(sugestao.reload).to be_accepted
    end

    # Revisão adversarial (item 13): o silêncio do card parado não diz que era teste.
    it 'avaliação do card parado: não sugere "era teste"' do
      ia_responde(teste)

      avaliar(trigger: Crm::Ai::FecharCard::TRIGGER_CARD_PARADO)

      expect(Crm::AiStageSuggestion.where(card: card).where("metadata ->> 'fechar' IS NOT NULL")).to be_empty
    end

    it 'funil sem movimento automático: o "era teste" ainda vira sugestão' do
      pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })
      ia_responde(teste)

      expect(avaliar.status).to eq(:suggested)
    end

    it 'sem a flag da F3: "teste" não é motivo aceito, e o card fica' do
      account.disable_features!(Crm::Ai::FecharCard::FLAG)
      ia_responde(teste)

      avaliar

      expect(card.reload).to be_open
    end
  end

  describe 'voltar de etapa com uma pessoa mexendo há pouco (regra h, D1)' do
    let!(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1) }
    let!(:fechamento) { create_crm_stage(account: account, pipeline: pipeline, name: 'Fechamento', position: 2) }

    before do
      [stage, proposta, fechamento].each { |etapa| etapa.update!(metadata: { 'ai_criteria' => "Critério de #{etapa.name}" }) }
      travel_to(1.hour.ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: proposta).perform }
      card.reload
    end

    # Pega: a IA calar quando a conversa contradiz a etapa que a pessoa escolheu (antes, nem sugeria).
    it 'voltar vira sugestão pendente, e o card fica onde a pessoa pôs', :aggregate_failures do
      ia_responde(suggested_stage_id: stage.id)

      resultado = avaliar

      expect(resultado.status).to eq(:suggested)
      expect(resultado.suggestion).to have_attributes(status: 'pending', to_stage_id: stage.id)
      expect(card.reload.stage_id).to eq(proposta.id)
    end

    it 'avançar segue o #1918: nem move nem sugere' do
      ia_responde(suggested_stage_id: fechamento.id)

      expect(avaliar).to have_attributes(status: :skipped, error: 'pessoa_mexeu_na_etapa')
    end

    it 'sem a flag: voltar também não sugere (como antes)' do
      account.disable_features!(Crm::Ai::FecharCard::FLAG)
      ia_responde(suggested_stage_id: stage.id)

      expect(avaliar).to have_attributes(status: :skipped, error: 'pessoa_mexeu_na_etapa')
    end

    # Pega: a pessoa que acabou de mexer ver o card fechado pela IA.
    it 'fechar também não acontece' do
      ia_responde(adiou)

      avaliar

      expect(card.reload).to be_open
    end
  end
end
