require 'rails_helper'

# IA entende a conversa F1: os fatos de ordem, hora e promessa (o texto é sempre do modelo).
RSpec.describe Crm::Ai::FatosDaConversa do
  describe '.com_ordem' do
    it 'cada mensagem do cliente leva o papel de quem falou antes; as outras ficam iguais' do
      mensagens = [{ role: 'customer', content: 'a' }, { role: 'customer', content: 'b' },
                   { role: 'platform_agent', content: 'c' }, { role: 'customer', content: 'd' }]

      expect(described_class.com_ordem(mensagens).map { |m| m[:after] }).to eq([nil, 'customer', nil, 'platform_agent'])
      expect(described_class.com_ordem(mensagens)[2]).not_to have_key(:after)
      expect(mensagens.first).not_to have_key(:after)
    end

    it 'com várias conversas no card, "after" é o de quem falou antes na MESMA conversa' do
      mensagens = [{ role: 'human_agent', conversation_id: 1 }, { role: 'customer', conversation_id: 2 },
                   { role: 'customer', conversation_id: 1 }]

      expect(described_class.com_ordem(mensagens).map { |m| m[:after] }).to eq([nil, nil, 'human_agent'])
    end
  end

  describe '.cliente_espera_desde' do
    let(:t0) { Time.zone.parse('2026-10-14 10:00') }

    it 'a hora da 1ª mensagem do cliente depois da última fala do atendimento' do
      trios = [[1, 'customer', t0], [1, 'human_agent', t0 + 1.minute], [1, 'customer', t0 + 2.minutes], [1, 'customer', t0 + 3.minutes]]

      expect(described_class.cliente_espera_desde(trios)).to eq((t0 + 2.minutes).iso8601)
    end

    it 'com várias conversas, a resposta numa não encerra a espera da outra; vale a espera mais antiga' do
      trios = [[2, 'customer', t0], [1, 'customer', t0 + 1.minute], [1, 'human_agent', t0 + 2.minutes], [2, 'customer', t0 + 3.minutes]]

      expect(described_class.cliente_espera_desde(trios)).to eq(t0.iso8601)
    end

    it 'nil quando a última fala é do atendimento ou não há mensagem', :aggregate_failures do
      expect(described_class.cliente_espera_desde([[1, 'customer', t0], [1, 'platform_agent', t0 + 1.minute]])).to be_nil
      expect(described_class.cliente_espera_desde([])).to be_nil
    end
  end

  describe '.com_promessa' do
    it 'o handoff ganha o campo obrigatório e o resto do schema não muda' do
      base = Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA
      novo = described_class.com_promessa(base)
      handoff = novo[:schema][:properties][:handoff]

      expect(handoff[:properties]).to have_key(:promised_by_our_assistant)
      expect(handoff[:required]).to include('promised_by_our_assistant')
      expect(novo[:schema][:properties].except(:handoff)).to eq(base[:schema][:properties].except(:handoff))
      expect(base[:schema][:properties][:handoff][:properties]).not_to have_key(:promised_by_our_assistant)
    end
  end

  describe '.promessa?' do
    it 'lê a saída do modelo', :aggregate_failures do
      expect(described_class.promessa?({ 'promised_by_our_assistant' => true })).to be(true)
      expect(described_class.promessa?({ promised_by_our_assistant: false })).to be(false)
      expect(described_class.promessa?(nil)).to be(false)
    end
  end

  describe 'cota da fala do robô' do
    it 'conta por dia e esgota no teto', :aggregate_failures do
      estado = {}
      described_class::MAX_AVALIACOES_DO_ROBO_POR_DIA.times do
        expect(described_class.cota_do_robo_esgotada?(estado)).to be(false)
        estado = estado.merge(described_class.contar_avaliacao_do_robo(estado))
      end

      expect(described_class.cota_do_robo_esgotada?(estado)).to be(true)
      travel(1.day) { expect(described_class.cota_do_robo_esgotada?(estado)).to be(false) }
      travel(1.day) { expect(described_class.contar_avaliacao_do_robo(estado)[described_class::CONTADOR]['total']).to eq(1) }
    end
  end

  describe '.fala_do_nosso_robo?' do
    include_context 'with crm responsible agent'

    def saida(sender:, **atributos)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Uma pessoa vai te atender',
                       sender: sender, **atributos)
    end

    it 'aceita a fala pública do nosso agente', :aggregate_failures do
      expect(described_class.fala_do_nosso_robo?(saida(sender: porta))).to be(true)
      expect(described_class.fala_do_nosso_robo?(saida(sender: espelho_area))).to be(true)
    end

    it 'recusa robô de fora, pessoa, nota privada e envio que falhou', :aggregate_failures do
      de_fora = AgentBot.create!(account: account, name: 'Integração', outgoing_url: 'https://integracao.invalid/webhook')

      expect(described_class.fala_do_nosso_robo?(saida(sender: de_fora))).to be(false)
      expect(described_class.fala_do_nosso_robo?(saida(sender: admin))).to be(false)
      expect(described_class.fala_do_nosso_robo?(saida(sender: porta, private: true))).to be(false)
      expect(described_class.fala_do_nosso_robo?(saida(sender: porta, status: :failed))).to be(false)
    end

    it 'recusa o agente protegido (instrução mantida pela Autonom.ia)' do
      allow_any_instance_of(Autonomia::Agents::Agent).to receive(:instrucao_mantida?).and_return(true) # rubocop:disable RSpec/AnyInstance

      expect(described_class.fala_do_nosso_robo?(saida(sender: porta))).to be(false)
    end
  end
end
