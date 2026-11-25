require 'rails_helper'

# #3211: quanto esperar pela fala anterior (P1) e quando entrar na fila atrás do turno em curso (P2). As duas opções nascem
# ligadas (menos na Lia); o exemplo que prova a opção desligada grava `false` no agente.
RSpec.describe Autonomia::Agents::Operate::EsperaDaFala do
  subject(:espera) { described_class }

  let(:fala) { Autonomia::Agents::Operate::FalaEmCurso }
  let(:conta) { conta_da_fase2(ligada: false) }
  let(:agent) { criar_principal(conta) }
  let(:marca) { { 'pending_message_id' => 9, 'at' => Time.current.to_f, 'espera_ms' => 1000 } }
  let(:conversation) { create(:conversation, account: conta, additional_attributes: { 'autonomia_debounce' => marca }) }

  def liga!(*chaves)
    agent.update!(config: agent.config.merge(chaves.index_with { true }))
  end

  before { freeze_time }

  after do
    fala.soltar(conversation.id, 8)
    Redis::Alfred.delete(fala.chave_do_fim(1))
  end

  describe '.da_rajada' do
    it 'opção desligada: o debounce de sempre' do
      desligar_paridade!(agent, 'conversa_espera_a_fala')
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(6.seconds)
    end

    it 'sem a chave (padrão ligado): espera a fala anterior acabar' do
      allow(fala).to receive(:fim_previsto).with(1).and_return(25.seconds.from_now)
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(25.seconds)
    end

    it 'a Lia sem a chave: o debounce de sempre, como antes' do
      lia = Autonomia::Agents::Agent.new(account: conta, agent_type: 'insurance_quote', config: {})
      allow(fala).to receive(:fim_previsto).and_return(25.seconds.from_now)
      expect(espera.da_rajada(agent: lia, conversation_id: 1, inbox: nil)).to eq(6.seconds)
    end

    it 'ligada e sem fala anterior: 1 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(nil)
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(1.second)
    end

    it 'ligada: espera a fala anterior acabar' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(25.seconds.from_now)
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(25.seconds)
    end

    it 'ligada: fim já passado vira o mínimo de 1 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(10.seconds.ago)
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(1.second)
    end

    it 'ligada: teto de 180 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).and_return(500.seconds.from_now)
      expect(espera.da_rajada(agent: agent, conversation_id: 1, inbox: nil)).to eq(180.seconds)
    end
  end

  # #3218: e-mail fica fora da paridade. Pega: a conversa de e-mail esperar até 180 s pelo "fim da fala" ou entrar na fila.
  describe 'caixa de e-mail' do
    let(:caixa_de_email) { create(:channel_email, account: conta).inbox }
    let(:conversa_de_email) do
      create(:conversation, account: conta, inbox: caixa_de_email, additional_attributes: { 'autonomia_debounce' => marca })
    end

    after { fala.soltar(conversa_de_email.id, 8) }

    it 'a espera é o debounce de sempre, mesmo com fim previsto gravado', :aggregate_failures do
      fala.prever_fim!(conversa_de_email.id, 8, 'x' * 100)

      espera_do_email = espera.da_rajada(agent: agent, conversation_id: conversa_de_email.id, inbox: caixa_de_email)

      expect(espera_do_email).to eq(Autonomia::Agents::Config.debounce_seconds_for(agent))
    end

    it 'outro turno falando não põe o turno na fila' do
      fala.ocupar(conversa_de_email.id, 8)

      expect(espera.na_fila?(agent: agent, conversation: conversa_de_email, message_id: 9)).to be(false)
    end

    it 'a janela do settle com a fila é a de sempre, sem o teto da fila' do
      janela = espera.janela_do_settle(agent: agent, marca: marca, inbox: caixa_de_email, com_a_fila: true)

      expect(janela).to eq(1.second)
    end
  end

  describe '.janela_do_settle' do
    it 'a espera gravada na marca' do
      expect(espera.janela_do_settle(agent: agent, marca: marca.merge('espera_ms' => 25_000), inbox: nil)).to eq(25.seconds)
    end

    it 'marca sem espera_ms, ou sem marca: o debounce do agente', :aggregate_failures do
      expect(espera.janela_do_settle(agent: agent, marca: marca.except('espera_ms'), inbox: nil)).to eq(6.seconds)
      expect(espera.janela_do_settle(agent: agent, marca: nil, inbox: nil)).to eq(6.seconds)
    end

    it 'com_a_fila soma o teto da fila só quando o agente tem a fila ligada', :aggregate_failures do
      desligar_paridade!(agent, 'conversa_em_fila')
      expect(espera.janela_do_settle(agent: agent, marca: marca, com_a_fila: true, inbox: nil)).to eq(1.second)

      liga!('conversa_em_fila')
      expect(espera.janela_do_settle(agent: agent, marca: marca, com_a_fila: true, inbox: nil)).to eq(151.seconds)
      expect(espera.janela_do_settle(agent: agent, marca: marca, inbox: nil)).to eq(1.second)
    end
  end

  describe '.janela_maxima' do
    let(:debounce) { Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS }

    it 'sem agente ou com as opções desligadas: a maior janela de debounce de sempre', :aggregate_failures do
      expect(espera.janela_maxima(nil)).to eq(debounce)
      desligar_paridade!(agent)
      expect(espera.janela_maxima(agent)).to eq(debounce)
    end

    it 'sem as chaves (padrão ligado): cobre a espera máxima e soma o teto da fila' do
      expect(espera.janela_maxima(agent)).to eq(described_class::ESPERA_MAXIMA + described_class::TETO_DA_FILA)
    end

    it 'com a espera pela fala, cobre a espera máxima; com a fila, soma o teto da fila', :aggregate_failures do
      desligar_paridade!(agent, 'conversa_espera_a_fala')
      liga!('conversa_em_fila')
      expect(espera.janela_maxima(agent)).to eq(debounce + described_class::TETO_DA_FILA)

      liga!('conversa_espera_a_fala')
      expect(espera.janela_maxima(agent)).to eq(described_class::ESPERA_MAXIMA + described_class::TETO_DA_FILA)
    end
  end

  describe '.na_fila?' do
    it 'outro turno falando: fila' do
      liga!('conversa_em_fila')
      fala.ocupar(conversation.id, 8)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(true)
    end

    it 'a marca é do próprio turno: sem fila' do
      liga!('conversa_em_fila')
      fala.ocupar(conversation.id, 9)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
    end

    it 'ninguém falando: sem fila' do
      liga!('conversa_em_fila')
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
    end

    it 'sem a chave (padrão ligado): outro turno falando, fila' do
      fala.ocupar(conversation.id, 8)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(true)
    end

    it 'opção desligada: nunca fila' do
      desligar_paridade!(agent, 'conversa_em_fila')
      fala.ocupar(conversation.id, 8)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
    end

    it 'passado espera + 150 s, segue mesmo ocupada', :aggregate_failures do
      liga!('conversa_em_fila')
      fala.ocupar(conversation.id, 8)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9, agora: 152.seconds.from_now)).to be(false)
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9, agora: 150.seconds.from_now)).to be(true)
    end

    it 'sem marca do debounce: não fila' do
      liga!('conversa_em_fila')
      fala.ocupar(conversation.id, 8)
      conversation.update!(additional_attributes: {})
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
    end

    it 'marca do debounce sem `at`: não fila' do
      liga!('conversa_em_fila')
      fala.ocupar(conversation.id, 8)
      conversation.update!(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => 9 } })
      expect(espera.na_fila?(agent: agent, conversation: conversation, message_id: 9)).to be(false)
    end
  end
end
