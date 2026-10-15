require 'rails_helper'

# #1593 / #1606: o serviço único de passagem para um agente de IA. Os leitores do Multifunnel (o registro das passagens)
# são dublados pelo adaptador; nada aqui chama rede nem IA real.
RSpec.describe Autonomia::Agents::PassarParaIa, :um_turno do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account, role: :agent) }
  let(:vinculo_area) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    allow(contrato).to receive(:registrar_passagem!)
    allow(contrato).to receive(:com_motivo_da_passagem).and_yield
    clear_enqueued_jobs
  end

  def passar(agente = area, por: :crm, **resto)
    described_class.call(conversation: conversation, agent: agente, por: por, motivo: 'pedido_pelo_nome', **resto)
  end

  def eventos_de_troca(&)
    eventos = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { eventos << payload },
                                            Crm::Ai::ResponsibleAgentSync::EVENTO_TROCA, &)
    eventos
  end

  def expect_recusa(resultado, codigo)
    expect(resultado).to have_attributes(ok?: false, trocou?: false, codigo: codigo)
    expect(conversation.reload.ai_assignee).to eq(porta)
  end

  describe 'passa' do
    it 'troca o ai_assignee pelo espelho do vínculo na caixa, registra a passagem e emite o evento com origem e transfer_id' do
      resultado = nil
      eventos = eventos_de_troca { resultado = passar(origem: porta, transfer_id: 'tr-1') }

      expect(resultado).to have_attributes(ok?: true, trocou?: true, codigo: :passou)
      expect(conversation.reload).to have_attributes(ai_assignee: espelho_area, status: 'open', assignee_id: nil)
      expect(contrato).to have_received(:registrar_passagem!).with(
        conversation: conversation, de: porta, para: area, pedida_por: nil, motivo: 'pedido_pelo_nome', transfer_id: 'tr-1',
        card: nil
      ).once
      expect(eventos.sole).to include(conversation: conversation, from_bot: porta, to_bot: espelho_area, agent: area,
                                      origem: porta, transfer_id: 'tr-1', por: :crm, motivo: 'pedido_pelo_nome')
    end

    it 'vinda de pessoa, solta a pessoa, e quem pediu é ela' do
      conversation.update!(assignee: pessoa)

      resultado = passar(por: :pessoa, origem: pessoa, pedida_por: pessoa)

      expect(resultado.codigo).to eq(:passou)
      expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: espelho_area)
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(de: pessoa, pedida_por: pessoa, para: area))
    end

    it 'quem pediu é quem clicou, não quem tinha a conversa' do
      supervisora = create(:user, account: account, role: :administrator)
      conversation.update!(assignee: pessoa)

      passar(por: :pessoa, origem: pessoa, pedida_por: supervisora)

      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(de: pessoa, pedida_por: supervisora))
    end

    it 'pedida pela IA: sem pedida_por, é a IA que tinha a conversa; com ele, o informado' do
      passar(por: :ia, origem: agente_da_porta)
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(pedida_por: agente_da_porta)).once

      passar(agente_da_porta, por: :ia, origem: area, pedida_por: area)
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(pedida_por: area)).once
    end

    it 'registra com o card do assunto em atendimento, no contexto e no registro' do
      card = create_card(pipeline: suporte)

      passar(origem: porta)

      expect(contrato).to have_received(:com_motivo_da_passagem).with('passar_para_ia', card: card)
      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(card: card))
    end

    it 'com o registro real do CRM (Crm::Passagens.registrar!): grava a passagem com card e quem pediu' do
      allow(contrato).to receive(:registrar_passagem!).and_call_original
      card = create_card(pipeline: suporte)
      conversation.update!(assignee: pessoa)

      passar(por: :pessoa, origem: pessoa, pedida_por: pessoa, transfer_id: 'tr-9')

      expect(Crm::Passagem.where(conversation_id: conversation.id).sole).to have_attributes(
        card_id: card.id, de_type: 'User', de_id: pessoa.id, para_type: 'Autonomia::Agents::Agent', para_id: area.id,
        pedida_por_type: 'User', pedida_por_id: pessoa.id, motivo: 'pedido_pelo_nome', transfer_id: 'tr-9'
      )
    end

    it 'card fechado não vai ao registro' do
      card = create_card(pipeline: suporte)
      card.update_columns(status: Crm::Card.statuses[:won]) # rubocop:disable Rails/SkipsModelValidations

      passar(origem: porta)

      expect(contrato).to have_received(:registrar_passagem!).with(hash_including(card: nil))
    end

    it 'encerra a espera de pessoa e a marca de entrega do CRM, na mesma gravação' do
      esperar_pessoa!
      Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'robo_pediu')
      conversation.save!
      expect(conversation.reload.bot_handoff_waiting?).to be(true)
      expect(conversation.crm_delivery_pending?).to be(true)

      passar

      expect(conversation.reload.bot_handoff_waiting?).to be(false)
      expect(conversation.crm_delivery_pending?).to be(false)
    end

    it 'o turno em andamento é refeito pelo dono novo, uma vez' do
      ia_responde!
      mensagem = cliente_escreve('quero falar com o suporte')
      gatilho(mensagem)

      passar(por: :ia, origem: agente_da_porta)
      rodar_turno!

      expect(respostas.sole.sender_id).to eq(espelho_area.id)
    end

    it 'sem trava de tempo: A→B→A logo em seguida passa as duas vezes' do
      expect(passar.codigo).to eq(:passou)
      expect(passar(agente_da_porta, origem: area).codigo).to eq(:passou)
      expect(passar(origem: agente_da_porta).codigo).to eq(:passou)
      expect(conversation.reload.ai_assignee).to eq(espelho_area)
    end

    it 'a troca e o registro rodam dentro do contexto do registro do CRM (com_motivo), e só eles' do
      dentro = false
      vistos = []
      allow(contrato).to receive(:com_motivo_da_passagem) do |motivo, &bloco|
        vistos << motivo
        dentro = true
        bloco.call.tap { dentro = false }
      end
      allow(contrato).to receive(:registrar_passagem!) do
        vistos << [:registro, dentro, Conversation.find(conversation.id).ai_assignee]
      end

      passar

      expect(vistos).to eq(['passar_para_ia', [:registro, true, espelho_area]])
      expect(dentro).to be(false)
    end

    it 'sem o contexto do registro (o adaptador só roda o bloco), passa igual' do
      allow(contrato).to receive(:com_motivo_da_passagem) { |_motivo, &bloco| bloco.call }

      expect(passar.codigo).to eq(:passou)
      expect(contrato).to have_received(:registrar_passagem!).once
    end

    it 'o registro da passagem falhando desfaz a troca e não emite evento' do
      allow(contrato).to receive(:registrar_passagem!).and_raise(ActiveRecord::RecordInvalid)

      eventos = eventos_de_troca { expect { passar }.to raise_error(ActiveRecord::RecordInvalid) }

      expect(conversation.reload.ai_assignee).to eq(porta)
      expect(eventos).to be_empty
    end
  end

  it 'desatribuir a pessoa (devolução do ponto 4) não registra passagem: o listener do CRM cobre esse caso' do
    conversation.update!(assignee: pessoa)

    Conversations::AssignmentService.new(conversation: conversation, assignee_id: nil).perform

    expect(contrato).not_to have_received(:registrar_passagem!)
    expect(contrato).not_to have_received(:com_motivo_da_passagem)
  end

  it 'o próprio dono atual: ok, sem troca, sem registro e sem evento' do
    resultado = nil
    eventos = eventos_de_troca { resultado = passar(agente_da_porta) }

    expect(resultado).to have_attributes(ok?: true, trocou?: false, codigo: :ja_e_o_dono)
    expect(contrato).not_to have_received(:registrar_passagem!)
    expect(eventos).to be_empty
  end

  describe 'recusas' do
    it 'Fase 2 desligada' do
      Autonomia::Agents::Fase2.desligar!(conversation.account)

      expect_recusa(passar, :fase2_desligada)
    end

    it 'agente que não atende cliente: parado, interno ou de sistema' do
      area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations
      expect_recusa(passar, :nao_atende_cliente)

      interno = criar_agente('Copiloto', actuation: :internal)
      expect_recusa(passar(interno), :nao_atende_cliente)
    end

    it 'agente sem vínculo ativo na caixa da conversa' do
      sem_vinculo = criar_agente('Sem caixa')
      expect_recusa(passar(sem_vinculo), :sem_vinculo_na_caixa)

      area_sumiu!
      expect_recusa(passar, :sem_vinculo_na_caixa)
    end

    it 'agente de outra conta' do
      outra = create(:account)
      alheio = Autonomia::Agents::Agent.create!(account: outra, name: 'Alheio', agent_type: 'custom', status: :active,
                                                enabled: true)

      expect_recusa(passar(alheio), :outra_conta)
    end

    it 'conversa resolvida' do
      conversation.update!(status: :resolved)

      resultado = passar
      expect(resultado).to have_attributes(ok?: false, codigo: :conversa_resolvida)
      expect(conversation.reload).to have_attributes(status: 'resolved')
    end

    it 'pessoa atribuída: o CRM e a IA não tiram a conversa dela' do
      conversation.update!(assignee: pessoa)

      %i[crm ia].each do |por|
        resultado = passar(por: por, origem: agente_da_porta)

        expect(resultado).to have_attributes(ok?: false, trocou?: false, codigo: :pessoa_atribuida)
        expect(conversation.reload).to have_attributes(assignee_id: pessoa.id, ai_assignee: nil)
      end
      expect(contrato).not_to have_received(:registrar_passagem!)
    end

    it 'por fora da lista' do
      expect { passar(por: :robo) }.to raise_error(ArgumentError)
    end

    it 'pessoa sem pedida_por: erro, e nada troca' do
      conversation.update!(assignee: pessoa)

      expect { passar(por: :pessoa, origem: pessoa) }.to raise_error(ArgumentError, /pedida_por/)
      expect(conversation.reload).to have_attributes(assignee_id: pessoa.id)
      expect(contrato).not_to have_received(:registrar_passagem!)
    end

    it 'pedido do CRM com pedida_por: erro (o pedido do CRM é do sistema)' do
      expect { passar(por: :crm, pedida_por: pessoa) }.to raise_error(ArgumentError, /pedida_por/)
      expect(conversation.reload.ai_assignee).to eq(porta)
    end

    it 'agente pausado entre a conferência e a trava: recusa sob a trava, sem troca nem registro' do
      allow(conversation).to receive(:with_lock).and_wrap_original do |original, *args, &bloco|
        area.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args, &bloco)
      end

      resultado = nil
      eventos = eventos_de_troca { resultado = passar }

      expect_recusa(resultado, :nao_atende_cliente)
      expect(contrato).not_to have_received(:registrar_passagem!)
      expect(eventos).to be_empty
    end

    it 'recusa não registra passagem nem emite evento' do
      Autonomia::Agents::Fase2.desligar!(conversation.account)

      eventos = eventos_de_troca { passar }

      expect(eventos).to be_empty
      expect(contrato).not_to have_received(:registrar_passagem!)
    end
  end

  describe '.destinos_na_caixa' do
    it 'os agentes com vínculo ativo na caixa (porta e área) que atendem cliente' do
      parado = criar_agente('Parado')
      Autonomia::Agents::Areas.vincular!(agent: parado, inbox: inbox)
      parado.update_columns(status: Autonomia::Agents::Agent.statuses[:paused]) # rubocop:disable Rails/SkipsModelValidations
      outra_caixa = create(:inbox, account: account)
      Autonomia::Agents::Operate::InboxConnector.new(agent: criar_agente('Outra porta'), inbox: outra_caixa).perform(connect: true)

      expect(described_class.destinos_na_caixa(inbox)).to contain_exactly(agente_da_porta, area)
    end

    it 'vazio sem a Fase 2 ou sem caixa' do
      Autonomia::Agents::Fase2.desligar!(conversation.account)

      expect(described_class.destinos_na_caixa(inbox)).to eq([])
      expect(described_class.destinos_na_caixa(nil)).to eq([])
    end

    it 'sem N+1: a mesma quantidade de consultas com mais agentes' do
      contar = lambda do
        consultas = 0
        contador = ->(*, payload) { consultas += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') do
          described_class.destinos_na_caixa(Inbox.find(inbox.id))
        end
        consultas
      end
      antes = contar.call
      2.times { |indice| Autonomia::Agents::Areas.vincular!(agent: criar_agente("Mais #{indice}"), inbox: inbox) }

      expect(contar.call).to eq(antes)
    end
  end

  describe '.destinos_possiveis' do
    it 'os da caixa da conversa' do
      expect(described_class.destinos_possiveis(conversation)).to contain_exactly(agente_da_porta, area)
    end

    it 'conversa resolvida: ninguém' do
      conversation.update!(status: :resolved)

      expect(described_class.destinos_possiveis(conversation)).to eq([])
    end
  end
end
