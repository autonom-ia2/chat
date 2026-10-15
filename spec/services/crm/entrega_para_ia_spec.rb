require 'rails_helper'

# #1593 — a regra da Atribuição levando a conversa a um agente de IA (Crm::Entrega + Crm::Entrega::ParaIa). O serviço
# dos Agentes é dublê por contrato (PassarParaIaHelper). Cada cenário diz que falha pega.
RSpec.describe Crm::Entrega do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Vendas') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:lia) { criar_agente_ia(account, 'Lia') }
  let!(:servico) { dublar_passar_para_ia(destinos: [lia]) }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    allow(Crm::Ai::Config).to receive(:areas_ligadas?).and_return(true)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
  end

  def conversa_do_robo
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
    conversation.update!(ai_assignee: bot, assignee: nil)
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Lead',
                              primary_conversation: conversation, inbox: inbox)
    conversation
  end

  def regra!(extra)
    vendas.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' }.merge(extra) })
  end

  def entrega(conversation, sugestao: nil)
    described_class.new(conversation: conversation, motivo: 'ia_crm', origem: 'message', pedido: { sugestao: sugestao }).call
  end

  describe '"A mesma pessoa" é um agente de IA' do
    before { regra!('pool_type' => 'ai_agent', 'pool_id' => lia.id) }

    # Pega: a regra apontando a Lia entregava a uma pessoa (a IA não era destino).
    it 'passa à Lia pelo serviço dos Agentes, com a origem e o motivo da Atribuição, e não atribui pessoa', :aggregate_failures do
      conversa = conversa_do_robo

      resultado = entrega(conversa)

      expect(resultado.status).to eq(:com_ia)
      expect(resultado.agente).to eq(lia)
      expect(servico).to have_received(:call).with(conversation: conversa, agent: lia, por: :crm, motivo: 'atribuicao',
                                                   origem: bot, transfer_id: nil)
      expect(conversa.reload.assignee_id).to be_nil
    end

    # Pega: agente parado (fora dos destinos) deixava a conversa sem ninguém. Agente parado = pessoa fora: equipe.
    it 'Lia parada (fora dos destinos): alguém da equipe recebe, sem chamar o serviço', :aggregate_failures do
      allow(servico).to receive(:destinos_possiveis).and_return([])
      conversa = conversa_do_robo

      resultado = entrega(conversa)

      expect(resultado.status).to eq(:entregue)
      expect(conversa.reload.assignee_id).to eq(ana.id)
      expect(servico).not_to have_received(:call)
    end

    # Pega: o agente parar entre a leitura e a passagem; a recusa não pode deixar a conversa parada.
    it 'o serviço recusa: entrega de novo, sem IA, para alguém da equipe', :aggregate_failures do
      responder_ia(servico, :nao_atende_cliente)
      conversa = conversa_do_robo

      resultado = entrega(conversa)

      expect(resultado.status).to eq(:entregue)
      expect(conversa.reload.assignee_id).to eq(ana.id)
    end

    # Pega: o laço. A Lia pede pessoa e a regra a manda de volta para ela mesma.
    it 'o alvo já é o dono (ja_e_o_dono): vai para alguém da equipe', :aggregate_failures do
      responder_ia(servico, :ja_e_o_dono)
      conversa = conversa_do_robo

      expect(entrega(conversa).status).to eq(:entregue)
      expect(conversa.reload.assignee_id).to eq(ana.id)
    end

    # Pega: uma pessoa assumiu entre a leitura e a passagem; a entrega não pode tirá-la nem dar a conversa a outra.
    it 'pessoa já no nome (pessoa_atribuida): fica com ela, sem cair para a equipe', :aggregate_failures do
      conversa = conversa_do_robo
      allow(servico).to receive(:call) do
        conversa.update_columns(assignee_id: admin.id) # rubocop:disable Rails/SkipsModelValidations
        resultado_da_ia(:pessoa_atribuida)
      end

      resultado = entrega(conversa)

      expect(resultado).to have_attributes(status: :nada, motivo: 'ja_tem_pessoa')
      expect(conversa.reload.assignee_id).to eq(admin.id)
    end

    # Pega: sem a Fase 2, a regra salva com agente não pode virar silêncio nem chamar os Agentes.
    it 'sem a Fase 2: alguém da equipe, sem chamar o serviço' do
      allow(Crm::Ai::Config).to receive(:areas_ligadas?).and_return(false)
      conversa = conversa_do_robo

      expect(entrega(conversa).status).to eq(:entregue)
      expect(servico).not_to have_received(:call)
    end

    # Pega: o robô passando (bot_handoff!) com a regra na Lia. A passagem ao agente sai depois da gravação, e não há o
    # aviso de "passou para pessoa".
    it 'na passagem do robô: grava como hoje e, depois do commit, passa à Lia, sem o aviso de passagem para pessoa', :aggregate_failures do
      conversa = conversa_do_robo
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      conversa.bot_handoff!

      esperado = { conversation: conversa, agent: lia, por: :crm, motivo: 'atribuicao', origem: bot }
      expect(servico).to have_received(:call).with(hash_including(esperado))
      expect(conversa.reload.assignee_id).to be_nil
      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
    end

    # Pega: o Responder e a saída da triagem chamam bot_handoff! dentro de uma trava; a passagem ao agente não pode sair
    # antes do commit dela (um rollback deixaria o agente com a conversa sem a passagem gravada).
    it 'dentro da transação de quem chama: passa à Lia só depois do commit', :aggregate_failures do
      conversa = conversa_do_robo
      chamadas = 0
      allow(servico).to receive(:call) do
        chamadas += 1
        resultado_da_ia(:passou)
      end
      chamadas_antes_do_commit = nil

      ActiveRecord::Base.transaction do
        conversa.bot_handoff!
        chamadas_antes_do_commit = chamadas
      end

      expect(chamadas_antes_do_commit).to eq(0)
      expect(chamadas).to eq(1)
    end

    it 'na passagem do robô com recusa: alguém da equipe recebe e o aviso de passagem sai', :aggregate_failures do
      responder_ia(servico, :sem_vinculo_na_caixa)
      conversa = conversa_do_robo
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      conversa.bot_handoff!

      expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_BOT_HANDOFF, anything, anything)
    end
  end

  describe 'pedido pelo nome (a IA do CRM decide; aqui é a lista que ela recebeu)' do
    let(:lia_pessoa) { create(:user, account: account, role: :agent, name: 'Lia') }

    # Pega: "quero falar com a Lia" com a Lia sendo agente de IA ia para uma pessoa.
    it 'com o rótulo do agente, vai para o agente' do
      regra!('mode' => 'direct')
      conversa = conversa_do_robo

      expect(entrega(conversa, sugestao: 'Lia (agente de IA)').status).to eq(:com_ia)
    end

    it 'com o nome de uma pessoa, segue para a pessoa' do
      regra!('mode' => 'direct')
      conversa = conversa_do_robo

      expect(entrega(conversa, sugestao: 'Ana Vendas').pessoa).to eq(ana)
    end

    # Pega: o rótulo do agente casar por pedaço com uma pessoa chamada "Lia" quando o agente não pôde receber.
    it 'agente pedido mas fora dos destinos: rodízio entre pessoas, sem casar o rótulo com a pessoa "Lia"' do
      create(:inbox_member, inbox: inbox, user: lia_pessoa)
      create(:conversation, account: account, inbox: inbox, assignee: lia_pessoa, status: :open)
      regra!('mode' => 'direct')
      conversa = conversa_do_robo
      allow(servico).to receive(:destinos_possiveis).and_return([])

      expect(entrega(conversa, sugestao: 'Lia (agente de IA)').pessoa).to eq(ana)
    end

    # Pega: a IA entrando no rodízio. Sem "pelo nome", o rótulo é ignorado.
    it 'rodízio ("Alguém da equipe") nunca escolhe o agente' do
      regra!('mode' => 'round_robin')
      conversa = conversa_do_robo

      expect(entrega(conversa, sugestao: 'Lia (agente de IA)').pessoa).to eq(ana)
      expect(servico).not_to have_received(:call)
    end
  end
end
