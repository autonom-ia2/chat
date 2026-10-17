require 'rails_helper'

# Os pontos onde a memória (#1601) entra no que já existe: a avaliação de card (ids locais, schema, carona), o campo do
# card editado à mão (A14), o fim do already_filled, o resultado de ferramenta (W5) e o pedido encerrado (D6).
RSpec.describe 'Memória das IAs: integrações' do # rubocop:disable RSpec/DescribeClass
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:card) { create_card(pipeline: suporte, title: 'Seguro auto') }

  before do
    ligar_memoria!(account)
    conversation.reload
    CustomAttributeDefinition.create!(account: account, attribute_key: 'placa', attribute_display_name: 'Placa',
                                      attribute_display_type: :text, attribute_model: :card_attribute)
  end

  describe 'ContextBuilder e StageClassifier' do
    it 'com a memória, cada mensagem ganha um id local e o mapa fica fora do que vai ao modelo; sem ela, nada muda' do
      mensagem = mensagem!(conversation, :incoming, content: 'placa ABC1D23')
      card

      com = Crm::Ai::ContextBuilder.new(card: card, memoria: true).perform
      sem = Crm::Ai::ContextBuilder.new(card: card).perform

      expect(com[:recent_messages].last).to include(ref: "m#{com[:memoria_refs].size}")
      expect(com[:memoria_refs].values).to include(mensagem.id)
      expect(sem[:recent_messages].last).not_to have_key(:ref)
      expect(sem.keys).not_to include(:memoria_refs, :memoria_fatos)
    end

    it 'o schema e o prefixo só mudam com a memória (o cache das contas sem a flag fica igual)' do
      expect(Crm::Ai::ClassifierPrompt.para([])).to equal(Crm::Ai::ClassifierPrompt::TEXT)
      expect(Crm::Ai::ClassifierPrompt.para([], memoria: true)).to end_with(Crm::Ai::ClassifierPrompt::MEMORIA)
      expect(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA[:schema][:required]).not_to include('memoria_ops')
      expect(Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA_MEMORIA[:schema][:required]).to include('memoria_ops')
    end
  end

  describe 'avaliação de card (W4 de carona)' do
    let(:cliente_ia) { instance_double(Crm::Ai::ResponsesClient) }

    before do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      credencial = instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: 'chave')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(credencial)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_ia)
      allow(Crm::Ai::Config).to receive(:pipeline_attribute_extraction_enabled?).and_return(false)
    end

    def resposta(ops)
      { suggested_stage_id: card.stage_id, confidence: 0.2, reasoning: 'x', value: nil, handoff: nil, callback_request: nil,
        extracted_attributes: { contact: [], conversation: [], card: [] }, score_signals: nil, memoria_ops: ops }
    end

    it 'uma chamada paga: o retry do job aplica o que ficou pendente sem chamar o modelo de novo (invariante 11)' do
      mensagem!(conversation, :incoming, content: 'a placa é ABC1D23')
      card
      ops = [{ op: 'adicionar', grupo: 'pedido', chave: 'placa', item_ref: nil, valor: 'ABC1D23', alvo_fato_id: nil, base_versao: nil,
               provas: ['m1'] }]
      allow(cliente_ia).to receive(:create).and_return(text: resposta(ops).to_json, usage: {}, response_id: 'r1')
      allow(Crm::Memoria::Pendente).to receive(:aplicar!).and_call_original
      allow(Crm::Memoria::Pendente).to receive(:aplicar!).once.and_raise(StandardError, 'caiu')

      expect { Crm::Ai::Evaluator.new(card: card, trigger: 'manual').perform }.to raise_error(StandardError, 'caiu')
      expect(card.reload.metadata.dig('ai', 'memoria_pendente')).to be_present

      allow(Crm::Memoria::Pendente).to receive(:aplicar!).and_call_original
      Crm::Ai::EvaluateCardJob.perform_now(card.id)

      expect(cliente_ia).to have_received(:create).once
      expect(Crm::MemoriaFato.where(card_id: card.id).pluck(:valor)).to eq(['ABC1D23'])
    end
  end

  describe 'avaliação conjunta (#1693) com a memória' do
    it 'cada card grava só o que a prova dele sustenta, com os ids locais da conversa enviada' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
      credencial = instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: 'chave')
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(credencial)
      cliente_ia = instance_double(Crm::Ai::ResponsesClient)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente_ia)
      card_a = create_card(pipeline: suporte, title: 'Auto A')
      card_b = create_card(pipeline: suporte, title: 'Auto B', focused_at: 1.minute.ago)
      [['placa do A: ABC1D23', card_a], ['placa do B: XYZ9W87', card_b]].each do |texto, alvo|
        mensagem = mensagem!(conversation, :incoming, content: texto)
        Crm::SubjectDecision.create!(account: account, conversation: conversation, message_id: mensagem.id, card_id: alvo.id,
                                     touched_card_ids: [alvo.id], action: 'focus', state: 'applied', mode: 'auto')
      end
      allow(cliente_ia).to receive(:create) do |args|
        entrada = JSON.parse(args[:input])
        ref = ->(trecho) { entrada['recent_messages'].find { |item| item['content'].include?(trecho) }['ref'] }
        cards = entrada['cards'].map do |pacote|
          placa = pacote.dig('card', 'title') == 'Auto A' ? 'ABC1D23' : 'XYZ9W87'
          { card_id: pacote.dig('card', 'id'), suggested_stage_id: pacote.dig('card', 'current_stage_id'), confidence: 0.2, reasoning: 'x',
            value: nil, handoff: nil, callback_request: nil, extracted_attributes: { contact: [], conversation: [], card: [] },
            score_signals: nil, memoria_ops: [{ op: 'adicionar', grupo: 'pedido', chave: 'placa', item_ref: nil, valor: placa,
                                                alvo_fato_id: nil, base_versao: nil, provas: [ref.call(placa)] }] }
        end
        { text: { cards: cards }.to_json, usage: {}, response_id: 'r' }
      end
      allow(Crm::Ai::Config).to receive(:pipeline_ai_settings).and_return({ enabled: true }.with_indifferent_access)

      Crm::Ai::AvaliacaoConjunta.new(cards: [card_a.reload, card_b.reload], principal: card_a).perform

      expect(cliente_ia).to have_received(:create).once
      expect(Crm::MemoriaFato.vigentes.where(card_id: card_a.id).pluck(:valor)).to eq(['ABC1D23'])
      expect(Crm::MemoriaFato.vigentes.where(card_id: card_b.id).pluck(:valor)).to eq(['XYZ9W87'])
    end
  end

  describe 'A14 e o fim do already_filled' do
    it 'a pessoa edita o campo do card: vira correção travada e é o que a IA lê' do
      Current.user = ana
      card.update!(custom_attributes: { 'placa' => 'NOVA123' })
      Current.reset

      fato = Crm::MemoriaFato.where(card_id: card.id, chave: 'placa').sole
      expect(fato).to have_attributes(fonte: 'pessoa_corrigiu', status: 'confirmado', travado: true)
      leitura = Crm::Memoria::Leitor.para(finalidade: :responder, account: account, conversation: conversation)
      expect(leitura.agora_fatos.map(&:valor)).to eq(['NOVA123'])
    end

    it 'a integração edita o campo: sugestão fraca, não correção' do
      integracao = create(:user, account: account)
      AccountUser.find_by(account: account, user: integracao).update!(integration: true)
      Current.user = integracao
      card.update!(custom_attributes: { 'placa' => 'API999' })
      Current.reset

      expect(Crm::MemoriaFato.where(card_id: card.id).sole).to have_attributes(situacao: 'sugestao', fonte: 'sistema', status: 'alegado')
    end

    it 'a gravação da IA no campo, mesmo com alguém logado e numa transação de fora, não vira correção nem sugestão' do
      Current.user = ana
      extraido = { card: [{ key: 'placa', value: 'IA12345', confidence: 0.9, evidence: 'placa IA12345' }] }
      ActiveRecord::Base.transaction do
        Crm::Ai::AttributeExtractorApplier.new(card: card, extracted_attributes: extraido, prefix: '').perform
      end
      Current.reset

      expect(card.reload.custom_attributes['placa']).to eq('IA12345')
      expect(Crm::MemoriaFato.where(card_id: card.id)).to be_empty
    end

    it 'com a flag, a IA corrige o campo já preenchido; travado pela pessoa, não' do
      card.update!(custom_attributes: { 'placa' => 'VELHA11' })
      extraido = { card: [{ key: 'placa', value: 'NOVA222', confidence: 0.9, evidence: 'placa NOVA222' }] }
      Crm::Ai::AttributeExtractorApplier.new(card: card, extracted_attributes: extraido, prefix: '').perform
      expect(card.reload.custom_attributes['placa']).to eq('NOVA222')

      Crm::Memoria::Correcao.corrigir!(card: card, grupo: 'pedido', chave: 'placa', valor: 'NOVA222', user: ana)
      outro = { card: [{ key: 'placa', value: 'TERC333', confidence: 0.9, evidence: 'placa TERC333' }] }
      resultado = Crm::Ai::AttributeExtractorApplier.new(card: card, extracted_attributes: outro, prefix: '').perform
      expect(resultado.rejected.pluck(:reason)).to eq(['already_filled'])
    end
  end

  describe 'W5 e D6' do
    it 'W5: a execução concluída grava o RESULTADO como confirmado no card que estava em foco na abertura' do
      card
      run = Autonomia::Agents::ToolRun.open!(agent: Autonomia::Agents::Agent.find(area.id), slug: 'cotar_seguro', arguments: { 'cpf' => '123' },
                                             scope: { conversation_id: conversation.id, faixa: 'auto' })
      expect(run.card_id).to eq(card.id)
      allow(Crm::Memoria::DaFerramenta).to receive(:leitura).and_return(valor: 'Cotação auto: Porto R$ 1.000', valor_json: { 'a' => 1 })
      run.update!(status: 'running')

      perform_enqueued_jobs { run.finish!('done') }

      fato = Crm::MemoriaFato.where(card_id: card.id).sole
      expect(fato).to have_attributes(fonte: 'ferramenta_resultado', status: 'confirmado', item_ref: 'cotar_seguro:auto')
      expect(Crm::MemoriaFato.where(chave: 'cpf')).to be_empty
    end

    it 'D6: o pedido ganho vira fato do cliente por 360 dias, sem título nem motivo; reaberto, sai' do
      card.update!(status: :lost, lost_reason: 'MOTIVO-SECRETO')
      perform_enqueued_jobs { Crm::Memoria::FechamentoJob.perform_later(card.id) }

      fato = Crm::MemoriaFato.where(contact_id: contact.id, tipo: 'pedido_encerrado').sole
      expect(fato).to have_attributes(escopo: 'contato', fonte: 'sistema', status: 'confirmado')
      expect(fato.valor).to start_with('perdido · Suporte')
      expect(fato.valor).not_to include('MOTIVO-SECRETO', 'Seguro auto')
      expect(fato.vence_em).to be_within(1.day).of(360.days.from_now)

      card.update!(status: :open)
      Crm::Memoria::FechamentoJob.perform_now(card.id)
      expect(fato.reload.expirado_em).to be_present
    end
  end
end
