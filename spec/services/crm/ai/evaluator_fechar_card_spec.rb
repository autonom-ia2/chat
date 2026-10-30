require 'rails_helper'

# IA entende a conversa F3 (flag `crm_ia_fecha_card`), o caminho do Crm::Ai::Evaluator quando a IA decide fechar o card:
# vira sugestão e o card segue aberto (a IA nunca fecha sozinha, #2389); aceito, o "adiou" ganha o lembrete de retorno
# (regra a); "era teste" vira sugestão (regra k); e, com uma pessoa mexendo na etapa há pouco, VOLTAR vira sugestão
# (regra h, D1). O modelo é simulado.
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

  # O card só fecha (e o retorno do "adiou" só nasce) quando a pessoa aceita a sugestão.
  def avaliar_e_aceitar
    sugestao = avaliar.suggestion
    expect(retornos).to be_empty
    Crm::Ai::SuggestionApplier.new(card: card, suggestion: sugestao, actor: admin).perform
  end

  describe 'a decisão de fechar' do
    # Pega (#2389): a IA fechar sozinha com confiança alta. O card segue aberto e a avaliação segue como a de card aberto.
    it 'vira sugestão; o card segue aberto, pontua e a memória segue; nenhum lembrete antes do aceite', :aggregate_failures do
      score = instance_double(Crm::Ai::ScoreApplier, perform: nil)
      allow(Crm::Ai::ScoreApplier).to receive(:new).and_return(score)
      allow(Crm::Memoria::Pendente).to receive(:aplicar!)
      ia_responde(fechar_card: { resultado: 'perdido', motivo: 'recusou', retorno_em: nil, confidence: 0.99, reasoning: 'Não quer.' },
                  suggested_stage_id: stage.id)

      expect(avaliar.status).to eq(:suggested)
      expect(card.reload).to be_open
      expect(Crm::Ai::ScoreApplier).to have_received(:new)
      expect(Crm::Memoria::Pendente).to have_received(:aplicar!).with(card)
      expect(retornos).to be_empty
    end
  end

  describe 'retorno do "adiou" (regra a)' do
    it 'aceito, sem data do cliente: lembrete em 30 dias, às 9 h do fuso, marcado como adiou', :aggregate_failures do
      ia_responde(adiou)

      avaliar_e_aceitar

      lembrete = retornos.sole
      expect(lembrete.due_at).to eq(as_nove(fuso.today + 30))
      expect(lembrete).to be_reminder_only
      expect(lembrete.metadata).to include('source' => 'ai_callback', 'motivo' => 'adiou')
      expect(lembrete.title).to eq(I18n.t('crm.ai_fechar_card.retorno', locale: :en))
      expect(card.reload).to be_lost
    end

    it 'aceito, com a data dita pelo cliente: o lembrete é nela' do
      ia_responde(adiou(retorno_em: (fuso.today + 45).iso8601))

      avaliar_e_aceitar

      expect(retornos.sole.due_at).to eq(as_nove(fuso.today + 45))
    end

    # Pega: uma data lida errado (longe demais) virar lembrete para daqui a anos.
    it 'data fora do horizonte do retorno: cai nos 30 dias' do
      ia_responde(adiou(retorno_em: (fuso.today + 400).iso8601))

      avaliar_e_aceitar

      expect(retornos.sole.due_at).to eq(as_nove(fuso.today + 30))
    end

    # Pega: criar retorno num funil em que a equipe desligou o retorno da IA.
    it 'funil com o retorno desligado: o aceite fecha e não cria lembrete', :aggregate_failures do
      pipeline.update!(metadata: pipeline.metadata.deep_merge('ai' => { 'callback_enabled' => false }))
      ia_responde(adiou)

      avaliar_e_aceitar

      expect(card.reload).to be_lost
      expect(retornos).to be_empty
    end

    # #2389: a sugestão de fechar segue o caminho de qualquer sugestão de hoje (abaixo de 0,95 já era assim): o pedido de
    # retorno da mesma leitura vira o lembrete na hora, e o aceite troca a data dele pela do "adiou" (um pendente por card).
    [0.86, 0.99].each do |confianca|
      it "confiança #{confianca}, com pedido de retorno detectado: lembrete na hora pedida; o aceite move para as 9 h", :aggregate_failures do
        dia = fuso.today + 10
        pedido = { detected: true, confidence: 0.9, requested_at: "#{dia.iso8601}T14:00", requested_at_text: 'dia tal à tarde' }
        ia_responde(adiou.deep_merge(fechar_card: { confidence: confianca }, callback_request: pedido))

        sugestao = avaliar.suggestion

        expect(card.reload).to be_open
        expect(retornos.sole.due_at).to eq(fuso.parse("#{dia.iso8601} 14:00"))
        Crm::Ai::SuggestionApplier.new(card: card, suggestion: sugestao, actor: admin).perform
        expect(card.reload).to be_lost
        expect(retornos.sole).to have_attributes(due_at: as_nove(dia))
        expect(retornos.sole.metadata).to include('motivo' => 'adiou')
      end
    end

    it 'recusou aceito: fecha sem lembrete' do
      ia_responde(adiou.deep_merge(fechar_card: { motivo: 'recusou' }))

      avaliar_e_aceitar

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

  # #2396 (decisão do Rodrigo, 30/10): quem desistiu ou chegou sem querer é perda, que vira sugestão; nunca o arquivamento
  # automático do "não é negócio", que tira o lead do relatório de anúncios.
  describe '"não é negócio" e "fechar" na mesma resposta' do
    before { account.enable_features!(Crm::Ai::NaoENegocio::FLAG) }

    let(:os_dois) do
      { nao_e_negocio: { motivo: 'fora_do_negocio', confidence: 0.95, reasoning: 'Clicou sem querer.', duplicado_de: nil },
        fechar_card: { resultado: 'perdido', motivo: 'recusou', retorno_em: nil, confidence: 0.95, reasoning: 'Não tem interesse.' },
        suggested_stage_id: stage.id }
    end

    # Pega: o lead que desistiu sair arquivado (some do relatório de anúncios) em vez de virar sugestão de perdido.
    it 'vale a sugestão de perdido; nada é arquivado', :aggregate_failures do
      ia_responde(os_dois)

      resultado = avaliar

      expect(resultado.status).to eq(:suggested)
      expect(resultado.suggestion.fechar).to eq('resultado' => 'perdido', 'motivo' => 'recusou')
      expect(card.reload).to be_open
      expect(Crm::Activity.where(card: card, event_type: 'archive')).to be_empty
    end

    # Pega: a regra derrubar o arquivamento do lixo de verdade, que vem sem pedido de fechar.
    it 'só o "não é negócio": arquiva como antes' do
      ia_responde(os_dois.merge(fechar_card: nil))

      avaliar

      expect(card.reload).to be_archived
    end

    # Pega (revisão do #2412): o lixo ficar aberto, sem ninguém saber, quando o pedido de fechar veio mas não virou
    # sugestão. A guarda é pelo resultado do fechar, não pela presença do campo.
    it 'o pedido de fechar abaixo do limiar de sugestão: arquiva' do
      ia_responde(os_dois.deep_merge(fechar_card: { confidence: 0.3 }))

      avaliar

      expect(card.reload).to be_archived
    end

    it 'na avaliação do card parado (fechar nunca sugere): arquiva' do
      ia_responde(os_dois)

      avaliar(trigger: Crm::Ai::FecharCard::TRIGGER_CARD_PARADO)

      expect(card.reload).to be_archived
    end

    it 'sem a flag do fechar: arquiva' do
      account.disable_features!(Crm::Ai::FecharCard::FLAG)
      ia_responde(os_dois)

      avaliar

      expect(card.reload).to be_archived
    end

    # Pega: um "era teste" virar perda. Segue a sugestão de arquivar, como antes do #2396.
    it '"teste" com fechar: segue a sugestão de arquivar como teste', :aggregate_failures do
      ia_responde(os_dois.deep_merge(nao_e_negocio: { motivo: 'teste' }))

      resultado = avaliar

      expect(resultado.suggestion.fechar).to eq('resultado' => 'arquivado', 'motivo' => 'teste')
      expect(Crm::AiStageSuggestion.where(card: card).filter_map(&:fechar).pluck('resultado')).not_to include('perdido')
    end

    # Pega: o repetido contar a perda duas vezes (no card que fica e neste).
    it '"duplicado" com fechar: arquiva o repetido' do
      account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Pedido', currency: 'BRL', primary_conversation: conversa)
      ia_responde(os_dois.deep_merge(nao_e_negocio: { motivo: 'duplicado', duplicado_de: account.crm_cards.order(:id).first.id }))

      avaliar

      expect(card.reload).to be_archived
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
