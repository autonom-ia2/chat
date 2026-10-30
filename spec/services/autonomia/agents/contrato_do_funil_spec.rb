require 'rails_helper'

# O adaptador dos leitores do Multifunnel (#1606). Os alvos são substituídos por stub_const nos dois sentidos — leitor
# presente e leitor sem o método —, para o spec não depender de a constante do CRM existir ou não na main.
RSpec.describe Autonomia::Agents::ContratoDoFunil do
  let(:conversation) { build_stubbed(:conversation) }

  def leitor(metodo, &)
    Module.new { define_singleton_method(metodo, &) }
  end

  describe '.ordem_do_turno?' do
    it 'delega ao leitor do CRM e devolve booleano estrito' do
      stub_const('Crm::Subjects', leitor(:ordem_do_turno?) { |_conversa| true })
      expect(described_class.ordem_do_turno?(conversation)).to be(true)

      stub_const('Crm::Subjects', leitor(:ordem_do_turno?) { |_conversa| 'sim' })
      expect(described_class.ordem_do_turno?(conversation)).to be(false)
    end

    it 'sem o leitor, o padrão seguro: não espera' do
      stub_const('Crm::Subjects', Module.new)

      expect(described_class.ordem_do_turno?(conversation)).to be(false)
    end
  end

  describe '.decidido_ate' do
    it 'delega ao marco do CRM' do
      stub_const('Crm::Subjects::Marco', leitor(:decidido_ate) { |id| id == 7 ? 42 : nil })

      expect(described_class.decidido_ate(7)).to eq(42)
      expect(described_class.decidido_ate(8)).to be_nil
    end

    it 'sem o leitor, nenhum marco' do
      stub_const('Crm::Subjects::Marco', Module.new)

      expect(described_class.decidido_ate(7)).to be_nil
    end
  end

  describe '.registrar_passagem!' do
    let(:pedido) do
      { conversation: conversation, de: nil, para: build_stubbed(:agent_bot), pedida_por: nil, motivo: 'm', transfer_id: 't' }
    end

    it 'delega ao registro do CRM com a mesma assinatura, card nil quando não vem' do
      recebidos = []
      stub_const('Crm::Passagens', leitor(:registrar!) { |**kwargs| recebidos << kwargs })

      described_class.registrar_passagem!(**pedido)

      expect(recebidos).to eq([pedido.merge(card: nil)])
    end

    it 'leva o card ao registro do CRM' do
      card = instance_double(Crm::Card)
      recebidos = []
      stub_const('Crm::Passagens', leitor(:registrar!) { |**kwargs| recebidos << kwargs })

      described_class.registrar_passagem!(**pedido, card: card)

      expect(recebidos.sole).to include(card: card)
    end

    it 'sem o registro, não faz nada' do
      stub_const('Crm::Passagens', Module.new)

      expect(described_class.registrar_passagem!(**pedido)).to be_nil
    end
  end

  describe '.com_motivo_da_passagem' do
    let(:card) { instance_double(Crm::Card) }

    it 'com o com_motivo do CRM: chamado com o motivo e o card, devolve o valor do bloco' do
      vistos = []
      stub_const('Crm::Passagens', leitor(:com_motivo) do |motivo, card: nil, &bloco|
        vistos << [motivo, card, :antes]
        bloco.call.tap { vistos << :depois }
      end)

      expect(described_class.com_motivo_da_passagem('passar_para_ia', card: card) { :feito }).to eq(:feito)
      expect(vistos).to eq([['passar_para_ia', card, :antes], :depois])
    end

    it 'sem card, o CRM recebe card nil' do
      vistos = []
      stub_const('Crm::Passagens', leitor(:com_motivo) { |motivo, card: :ausente, &bloco| (vistos << [motivo, card]) && bloco.call })

      described_class.com_motivo_da_passagem('passar_para_ia') { :feito }

      expect(vistos).to eq([['passar_para_ia', nil]])
    end

    it 'sem o com_motivo do CRM: só roda o bloco e devolve o valor dele' do
      stub_const('Crm::Passagens', leitor(:registrar!) { |**| nil })

      expect(described_class.com_motivo_da_passagem('passar_para_ia', card: card) { :feito }).to eq(:feito)
    end

    it 'decide na hora da chamada, não no carregamento' do
      stub_const('Crm::Passagens', Module.new)
      expect(described_class.com_motivo_da_passagem('m') { :sem }).to eq(:sem)

      stub_const('Crm::Passagens', leitor(:com_motivo) { |_motivo, card: nil, &bloco| [:com, bloco.call] }) # rubocop:disable Lint/UnusedBlockArgument
      expect(described_class.com_motivo_da_passagem('m') { :bloco }).to eq(%i[com bloco])
    end
  end

  describe '.robo_do_funil' do
    let(:robo) { build_stubbed(:agent_bot) }

    it 'delega ao leitor do CRM e só aceita um AgentBot' do
      robo_esperado = robo
      stub_const('Crm::Ai::Config', leitor(:robo_do_funil) { |_conversa| robo_esperado })
      expect(described_class.robo_do_funil(conversation)).to eq(robo)

      stub_const('Crm::Ai::Config', leitor(:robo_do_funil) { |_conversa| 'robô' })
      expect(described_class.robo_do_funil(conversation)).to be_nil
    end

    it 'sem o leitor, nil: a devolução vai para a porta' do
      stub_const('Crm::Ai::Config', Module.new)

      expect(described_class.robo_do_funil(conversation)).to be_nil
    end
  end

  # #2154: o agente avisou que vai chamar alguém e a fala saiu; quem decide passar é a IA de Atribuição.
  describe '.avaliar_depois_da_fala' do
    it 'delega ao CRM' do
      recebidas = []
      stub_const('Crm::Ai::AvaliacaoDepoisDaFala', leitor(:agendar) { |conversa| recebidas << conversa })

      described_class.avaliar_depois_da_fala(conversation)

      expect(recebidas).to eq([conversation])
    end

    it 'sem o leitor, nada' do
      stub_const('Crm::Ai::AvaliacaoDepoisDaFala', Module.new)

      expect(described_class.avaliar_depois_da_fala(conversation)).to be_nil
    end
  end
end
