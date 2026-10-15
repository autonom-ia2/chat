require 'rails_helper'

# #1433 — o leitor único de "esta caixa pode receber um agente da equipe agora?", usado pela tela dos Agentes, pelo
# CRM e pelo vincular! (com a caixa travada). Códigos fechados: :ok, :principal_parado, :robo_externo, :fase2_desligada.
RSpec.describe Autonomia::Agents::Areas do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def agente(nome, conta: account, **attrs)
    Autonomia::Agents::Agent.create!({ account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true }.merge(attrs))
  end

  def principal(caixa, **attrs)
    agent = agente('Porta', conta: caixa.account)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
    agent.update_columns(attrs) if attrs.any? # rubocop:disable Rails/SkipsModelValidations
    agent
  end

  def robo_externo(caixa)
    AgentBotInbox.create!(inbox: caixa, agent_bot: create(:agent_bot, account: caixa.account), account: caixa.account)
  end

  def codigo(caixa = inbox, **opcoes)
    described_class.caixa_aceita_area?(caixa, **opcoes)
  end

  before { Autonomia::Agents::Fase2.ligar!(account) }

  describe '.caixa_aceita_area?' do
    it ':ok para a caixa com principal atendendo' do
      principal(inbox)

      expect(codigo).to have_attributes(codigo: :ok, ok?: true)
    end

    it ':ok para a caixa só de pessoas (sem principal e sem robô)' do
      expect(codigo).to have_attributes(codigo: :ok, ok?: true)
    end

    # #1648 — espelho que sobrou de porta apagada não é robô de fora (AgentInbox.espelhos).
    it 'não chama de :robo_externo o espelho que sobrou de uma porta apagada' do
      principal(inbox)
      Autonomia::Agents::AgentInbox.kept.porta.find_by!(inbox: inbox).update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(AgentBotInbox.where(inbox_id: inbox.id).count).to eq(1)
      expect(codigo.codigo).to eq(:ok)

      robo_externo(inbox)
      expect(codigo.codigo).to eq(:robo_externo)
    end

    it ':principal_parado quando o principal não está atendendo' do
      principal(inbox, status: Autonomia::Agents::Agent.statuses[:paused], enabled: false)

      expect(codigo).to have_attributes(codigo: :principal_parado, ok?: false)
    end

    it ':robo_externo sem principal e com robô de fora' do
      robo_externo(inbox)

      expect(codigo).to have_attributes(codigo: :robo_externo, ok?: false)
    end

    it ':fase2_desligada quando a conta da caixa não tem a Fase 2, antes de olhar a caixa' do
      Autonomia::Agents::Fase2.desligar!(account)
      robo_externo(inbox)

      expect(codigo.codigo).to eq(:fase2_desligada)
      expect(codigo(conferir_fase2: false).codigo).to eq(:robo_externo)
    end

    it 'só devolve códigos da lista fechada' do
      expect(described_class::CODIGOS).to eq(%i[ok principal_parado robo_externo fase2_desligada])
    end

    it 'isola a conta: a Fase 2 e o principal são lidos da conta da caixa' do
      outra = create(:account)
      caixa_de_fora = create(:inbox, account: outra)
      principal(caixa_de_fora, status: Autonomia::Agents::Agent.statuses[:paused], enabled: false)

      expect(codigo(caixa_de_fora).codigo).to eq(:fase2_desligada)
      expect(codigo.codigo).to eq(:ok)

      Autonomia::Agents::Fase2.ligar!(outra)
      expect(codigo(caixa_de_fora).codigo).to eq(:principal_parado)
      expect(codigo.codigo).to eq(:ok)
    end

    it 'não trava a caixa (leitor puro)' do
      expect_any_instance_of(Inbox).not_to receive(:lock!) # rubocop:disable RSpec/AnyInstance
      expect_any_instance_of(Inbox).not_to receive(:with_lock) # rubocop:disable RSpec/AnyInstance

      codigo
    end
  end

  describe 'CaixaNaoAceitaArea' do
    it 'nasce de new(codigo), expõe #codigo e a mensagem vem do código' do
      erro = described_class::CaixaNaoAceitaArea.new(:principal_parado)

      expect(erro.codigo).to eq(:principal_parado)
      expect(erro.message).to include('principal_parado')
    end
  end

  describe '.vincular! usa o mesmo leitor' do
    it 'confere a caixa pelo caixa_aceita_area?, já travada, e levanta CaixaNaoAceitaArea com o mesmo código' do
      robo_externo(inbox)
      travada = false
      allow(inbox).to receive(:with_lock).and_wrap_original do |original, *args, &bloco|
        original.call(*args) do
          travada = true
          bloco.call
        end
      end
      allow(described_class).to receive(:caixa_aceita_area?).and_wrap_original do |original, *args, **kwargs|
        expect(travada).to be(true)
        original.call(*args, **kwargs)
      end

      expect { described_class.vincular!(agent: agente('Equipe'), inbox: inbox) }
        .to raise_error(described_class::CaixaNaoAceitaArea) { |erro| expect(erro.codigo).to eq(:robo_externo) }
      expect(described_class).to have_received(:caixa_aceita_area?).with(inbox, conferir_fase2: false)
    end

    it 'aceita quando o leitor diz :ok' do
      principal(inbox)

      expect(described_class.vincular!(agent: agente('Equipe'), inbox: inbox)).to have_attributes(papel: 'area')
    end
  end
end
