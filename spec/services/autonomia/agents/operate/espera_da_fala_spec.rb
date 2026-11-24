require 'rails_helper'

# #3211: quanto esperar pela fala anterior (P1) e quando entrar na fila atrás do turno em curso (P2).
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
      expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(6.seconds)
    end

    it 'ligada e sem fala anterior: 1 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(nil)
      expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(1.second)
    end

    it 'ligada: espera a fala anterior acabar' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(25.seconds.from_now)
      expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(25.seconds)
    end

    it 'ligada: fim já passado vira o mínimo de 1 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).with(1).and_return(10.seconds.ago)
      expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(1.second)
    end

    it 'ligada: teto de 180 s' do
      liga!('conversa_espera_a_fala')
      allow(fala).to receive(:fim_previsto).and_return(500.seconds.from_now)
      expect(espera.da_rajada(agent: agent, conversation_id: 1)).to eq(180.seconds)
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

    it 'opção desligada: nunca fila' do
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
