require 'rails_helper'

# #2428 (F6.7 do #2414): a IA do funil respeita o card que uma automação moveu. Pega a avaliação seguinte devolvendo o
# card para onde estava, desfazendo em silêncio a automação que alguém configurou. O modelo é simulado.
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
  let(:proposta) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1) }
  let(:alvo) do
    create_crm_stage(account: account, pipeline: pipeline, name: 'Fechamento', position: 2).tap do |etapa|
      etapa.update!(metadata: { 'ai_criteria' => 'Cliente aceitou' })
    end
  end
  let(:conversa) { create(:conversation, account: account) }
  let(:card) { account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL', primary_conversation: conversa) }
  let(:janela) { described_class::RESPEITO_AO_MOVIMENTO }

  def ia_responde(resposta = { suggested_stage_id: alvo.id, confidence: 0.95 })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(Crm::Ai::StageClassifier, perform: { reasoning: 'x', model_used: 'm' }.merge(resposta).with_indifferent_access)
    )
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  def movido_pela_automacao(tempo:, origem: 'regra', id: 7, actor: nil)
    travel_to(tempo.ago) { Crm::Cards::Mover.new(card: card, actor: actor, target_stage: proposta, automacao: { origem: origem, id: id }).perform }
    ia_responde
  end

  def mensagem_do_cliente(tempo:)
    travel_to(tempo.ago) { create(:message, account: account, conversation: conversa, message_type: :incoming, content: 'Fechado!') }
  end

  def avaliar(trigger: 'message') = described_class.new(card: card, trigger: trigger).perform

  def expect_sem_mexer
    result = avaliar

    expect(result).to have_attributes(status: :skipped, error: 'automacao_mexeu_na_etapa')
    expect(account.crm_ai_stage_suggestions.where(card: card, status: %i[pending auto_applied])).to be_empty
    expect(card.reload.stage).to eq(proposta)
  end

  %w[regra etapa livre].each do |origem|
    it "movido por automação (#{origem}) há pouco: a IA não move nem sugere" do
      movido_pela_automacao(tempo: 1.hour, origem: origem)

      expect_sem_mexer
    end
  end

  # O passo da Automação livre move como quem ligou: o ator é a pessoa, a escolha é da automação.
  it 'movido pela Automação livre com quem ligou como ator: vale a regra da automação, não a da pessoa' do
    movido_pela_automacao(tempo: 1.hour, origem: 'livre', actor: admin)

    expect_sem_mexer
  end

  it 'a mensagem que chega dentro da janela não solta o card' do
    movido_pela_automacao(tempo: 1.hour)
    mensagem_do_cliente(tempo: 30.minutes)

    expect_sem_mexer
  end

  it 'passada a janela, sem mensagem nova do cliente (card parado, reavaliação): segue respeitando' do
    movido_pela_automacao(tempo: janela + 1.hour)
    mensagem_do_cliente(tempo: janela + 2.hours)

    expect_sem_mexer
  end

  it 'passada a janela, com mensagem nova do cliente depois do movimento: a IA volta a mover' do
    movido_pela_automacao(tempo: janela + 1.hour)
    mensagem_do_cliente(tempo: 10.minutes)

    expect(avaliar.status).to eq(:auto_moved)
    expect(card.reload.stage).to eq(alvo)
  end

  it 'a mensagem nova vale em qualquer conversa do card' do
    movido_pela_automacao(tempo: janela + 1.hour)
    outra = create(:conversation, account: account)
    Crm::CardConversation.create!(account: account, card: card, conversation: outra)
    create(:message, account: account, conversation: outra, message_type: :incoming, content: 'Oi')

    expect(avaliar.status).to eq(:auto_moved)
  end

  it 'mensagem do atendente não conta como mensagem nova do cliente' do
    movido_pela_automacao(tempo: janela + 1.hour)
    create(:message, account: account, conversation: conversa, message_type: :outgoing, content: 'Tudo certo?')

    expect_sem_mexer
  end

  it 'a sugestão de etapa pendente de antes do movimento sai' do
    antiga = account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: alvo, confidence: 0.6,
                                                      model_used: 'm', status: :pending)
    movido_pela_automacao(tempo: 1.hour)

    expect_sem_mexer
    expect(antiga.reload).to be_expired
  end

  it 'o movimento da própria IA não ganha respeito' do
    sugestao = account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: proposta, confidence: 0.95,
                                                        model_used: 'm', status: :auto_applied)
    travel_to(1.hour.ago) { Crm::Ai::SuggestionApplier.new(card: card, suggestion: sugestao, actor: nil, auto: true).perform }
    ia_responde

    expect(avaliar.status).to eq(:auto_moved)
  end

  it 'uma pessoa moveu depois da automação: vale a regra da pessoa, não a da automação' do
    movido_pela_automacao(tempo: janela + 2.hours)
    travel_to((janela + 1.hour).ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: stage).perform }

    expect(avaliar.status).to eq(:auto_moved)
  end

  it '"Avaliar agora": move' do
    movido_pela_automacao(tempo: 1.hour)

    expect(avaliar(trigger: 'manual').status).to eq(:auto_moved)
    expect(card.reload.stage).to eq(alvo)
  end

  it 'card sem movimento de automação: nada muda' do
    ia_responde

    expect(avaliar.status).to eq(:auto_moved)
  end

  # Barrar o fim deixaria o lixo aberto por horas: o respeito é só da etapa.
  describe 'o fim do card segue' do
    before { account.enable_features!(Crm::Ai::FecharCard::FLAG, Crm::Ai::NaoENegocio::FLAG) }

    it 'o pedido de fechar vira sugestão, mesmo com a automação mexendo há pouco (também a livre, com ator)' do
      movido_pela_automacao(tempo: 1.hour, origem: 'livre', actor: admin)
      ia_responde(fechar_card: { resultado: 'perdido', motivo: 'recusou', retorno_em: nil, confidence: 0.99, reasoning: 'Não quer.' },
                  suggested_stage_id: proposta.id, confidence: 0.9)

      result = avaliar

      expect(result.status).to eq(:suggested)
      expect(result.suggestion.fechar).to be_present
    end

    it '"não é negócio" vira sugestão de arquivar, mesmo com a automação mexendo há pouco' do
      movido_pela_automacao(tempo: 1.hour)
      ia_responde(nao_e_negocio: { motivo: 'teste', confidence: 0.99, reasoning: 'Era teste.', duplicado_de: nil },
                  suggested_stage_id: proposta.id, confidence: 0.9)

      result = avaliar

      expect(result.status).to eq(:suggested)
      expect(result.suggestion.fechar).to eq('resultado' => 'arquivado', 'motivo' => 'teste')
    end
  end
end
