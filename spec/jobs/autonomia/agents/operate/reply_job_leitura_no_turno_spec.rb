require 'rails_helper'

# #3225 no ReplyJob: o turno que leu a mensagem nova do cliente no meio não fica superado por ela (`turno_superado?` com
# as lidas), o settle da mensagem lida não responde de novo (`respondida_junto`), o dono novo responde mesmo assim, e a
# fila espera o turno que pode ter lido até o teto do turno, não só os 150 s da fila. A IA é dublada (UmTurnoHelper),
# mas lê pelo leitor de verdade que o Responder deixa no contexto de entrega.
RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno do
  include_context 'with crm responsible agent'

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:leitura) { Autonomia::Agents::Operate::LeituraNoTurno }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    account.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
    contrato!
    ia_responde!
    clear_enqueued_jobs
    freeze_time
    limpar_a_fala!
  end

  after { limpar_a_fala! }

  def limpar_a_fala!
    Redis::Alfred.delete(fala.chave_ocupada(conversation.id))
    Redis::Alfred.delete(fala.chave_do_fim(conversation.id))
  end

  # A IA dublada que, no meio da resposta, roda `durante` e lê antes de enviar pelo leitor do turno (o da flag).
  def ia_le_no_meio!(texto: 'Resposta única.', &durante)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |delivery:, **|
      resposta = double('Answerer') # rubocop:disable RSpec/VerifiedDoubles
      allow(resposta).to receive(:answer) do
        durante&.call
        delivery.leitura&.antes_de_enviar('rascunho')
        Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: false, reason: nil }, used_knowledge: [],
                                            answered_from_knowledge: false)
      end
      resposta
    end
  end

  def marca!(mensagem)
    conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => mensagem.id } })
  end

  # A resposta de um turno que leu `lidas` no meio.
  def resposta_que_leu!(ancora, lidas, agente: agente_da_porta, robo: porta)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: robo,
                     content: 'Resposta que leu.',
                     content_attributes: { 'autonomia_agent_id' => agente.id, 'autonomia_reply_to_message_id' => ancora.id,
                                           leitura::CHAVE => lidas.map(&:id) })
  end

  describe '.turno_superado?' do
    let!(:primeira) { cliente_escreve('França, 15 a 20/01, 40 anos') }
    let!(:segunda) { cliente_escreve('Conhece lá?') }

    def superado?(lidas)
      described_class.turno_superado?(conversation.reload, primeira.id, agente_da_porta, lidas: lidas.map(&:id))
    end

    it 'a mais nova não foi lida: superado (o de sempre)' do
      marca!(segunda)
      expect(superado?([])).to be(true)
    end

    it 'a mais nova foi lida e não tem resposta própria: não superado' do
      marca!(segunda)
      expect(superado?([segunda])).to be(false)
    end

    it 'a mais nova foi lida, mas o turno dela já respondeu: superado' do
      marca!(segunda)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: porta,
                       content: 'Sim!', content_attributes: { 'autonomia_reply_to_message_id' => segunda.id })
      expect(superado?([segunda])).to be(true)
    end

    it 'chegou outra depois da lida: superado' do
      marca!(cliente_escreve('E esqui?'))
      expect(superado?([segunda])).to be(true)
    end

    it 'a chave foi desligada no meio do turno: superado (a mensagem nova responde)' do
      marca!(segunda)
      account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      expect(superado?([segunda])).to be(true)
    end
  end

  it 'o turno lê a mensagem nova no meio: uma resposta, com a lida gravada, e o settle dela não responde', :aggregate_failures do
    primeira = cliente_escreve('França, 15 a 20/01, 40 anos')
    segunda = nil
    ia_le_no_meio! { segunda ||= cliente_escreve('Conhece lá?').tap { |mensagem| gatilho(mensagem) } }
    gatilho(primeira)

    linhas = linhas_do_log { rodar_turno! }

    expect(respostas.sole.content_attributes).to include('autonomia_reply_to_message_id' => primeira.id,
                                                         leitura::CHAVE => [segunda.id])
    expect(Autonomia::Agents::Answerer).to have_received(:new).once
    expect(linhas.join).to include('mensagem_lida_no_turno', 'respondida_junto', "msg=#{segunda.id}", 'etapa=settle')
  end

  # #3225 (revisão): A leu B no meio e não postou (a IA falhou, ou calou). Nada gravou B como lida: o settle de B responde.
  describe 'A leu B e não postou' do
    let(:primeira) { cliente_escreve('França, 15 a 20/01, 40 anos') }

    def ia_le_b_e(desfecho)
      segunda = nil
      allow(Autonomia::Agents::Answerer).to receive(:new) do |delivery:, agent:, **|
        resposta = double('Answerer') # rubocop:disable RSpec/VerifiedDoubles
        allow(resposta).to receive(:answer) do
          next resposta_de(agent) if segunda # o turno de B: responde

          segunda = cliente_escreve('Conhece lá?').tap { |mensagem| gatilho(mensagem) }
          delivery.leitura.antes_de_enviar('rascunho')
          desfecho.call
        end
        resposta
      end
      gatilho(primeira)
      rodar_turno!
      segunda
    end

    def resposta_de(agent)
      Autonomia::Agents::AnswerResult.new(reply: "Resposta de #{agent.name}.", confidence: 0.9,
                                          handoff: { should: false, reason: nil }, used_knowledge: [], answered_from_knowledge: false)
    end

    it 'a IA de A falhou depois de ler B: o settle de B responde B', :aggregate_failures do
      segunda = ia_le_b_e(-> { raise StandardError, 'caiu' })

      expect(respostas.count).to eq(1)
      expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(segunda.id)
    end

    it 'A calou depois de ler B: o settle de B responde B', :aggregate_failures do
      segunda = ia_le_b_e(lambda {
        Autonomia::Agents::AnswerResult.new(reply: nil, confidence: 0.0, handoff: { should: false, reason: nil },
                                            used_knowledge: [], answered_from_knowledge: false)
      })

      expect(respostas.count).to eq(1)
      expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(segunda.id)
    end
  end

  describe 'o settle da mensagem que outro turno leu' do
    let!(:primeira) { cliente_escreve('França, 15 a 20/01, 40 anos') }
    let!(:segunda) { cliente_escreve('Conhece lá?') }

    it 'a resposta deste agente leu: não chama a IA nem posta, e registra' do
      resposta_que_leu!(primeira, [segunda])
      gatilho(segunda)

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas.count).to eq(1)
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(linhas.join).to include('respondida_junto', "msg=#{segunda.id}", 'etapa=settle')
    end

    it 'sem a flag: responde, como antes' do
      account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      resposta_que_leu!(primeira, [segunda])
      gatilho(segunda)

      rodar_turno!

      expect(respostas.count).to eq(2)
    end

    it 'o dono mudou depois da resposta que leu: o dono novo responde a mensagem', :aggregate_failures do
      resposta_que_leu!(primeira, [segunda])
      conversation.update!(ai_assignee: espelho_area)
      clear_enqueued_jobs
      gatilho(segunda)

      rodar_turno!

      expect(respostas.count).to eq(2)
      expect(respostas.order(:id).last).to have_attributes(sender_id: espelho_area.id)
      expect(respostas.order(:id).last.content_attributes['autonomia_reply_to_message_id']).to eq(segunda.id)
    end
  end

  describe 'a fila, com o turno que pode ter lido falando' do
    let!(:primeira) { cliente_escreve('França, 15 a 20/01, 40 anos') }
    let!(:segunda) { cliente_escreve('Conhece lá?') }

    before do
      fala.ocupar(conversation.id, primeira.id, agente_da_porta)
      gatilho(segunda)
    end

    it 'A demora mais que o prazo da fila: o settle de B segue esperando, sem responder', :aggregate_failures do
      travel 6.seconds + Autonomia::Agents::Operate::EsperaDaFala::TETO_DA_FILA + 1.second
      clear_enqueued_jobs
      settle(segunda)

      expect(respostas).to be_empty
      expect(Time.zone.at(settles_na_fila.sole[:at])).to be_within(0.5.seconds).of(2.seconds.from_now)
    end

    it 'com o prazo de quem lê ainda correndo: segue esperando' do
      travel Autonomia::Agents::Operate::LeituraNoTurno::PRAZO_DE_QUEM_LE
      clear_enqueued_jobs
      settle(segunda)

      expect(respostas).to be_empty
    end

    # O turno que falava morreu sem soltar a fala (OOM, deploy): a fila não espera o teto da Lia (horas).
    it 'passado o prazo de quem lê (bem antes do teto do turno), desiste e responde', :aggregate_failures do
      prazo = 6.seconds + Autonomia::Agents::Operate::EsperaDaFala::TETO_DA_FILA + Autonomia::Agents::Operate::LeituraNoTurno::PRAZO_DE_QUEM_LE
      expect(prazo).to be < Autonomia::Agents::Operate::TurnoEmCurso.teto_do_turno(agente_da_porta)
      travel prazo + 1.second
      settle(segunda)

      expect(respostas.count).to eq(1)
    end

    it 'sem a flag: o prazo de sempre (passados os 150 s, responde)' do
      account.disable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      travel 6.seconds + Autonomia::Agents::Operate::EsperaDaFala::TETO_DA_FILA + 1.second
      settle(segunda)

      expect(respostas.count).to eq(1)
    end
  end
end
