require 'rails_helper'

# #1630: uma pessoa passa a conversa para um agente de IA (PassarParaIa, `por: :pessoa`) e o agente que recebe lê tudo e
# decide se fala ou fica calado, num turno próprio, sem mensagem nova do cliente. Caminho real (passagem, evento, fila,
# Responder, entrega) e registro real das passagens; só a IA é dublada.
RSpec.describe Autonomia::Agents::Operate::AoReceberPassagem, :um_turno do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:pedidos) { [] }
  let(:resposta_da_ia) { 'Oi, Joana! Sou da Área Suporte e sigo daqui.' }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    ligar!
    clear_enqueued_jobs
  end

  def ligar!(valor: true)
    account.update!(internal_attributes: account.internal_attributes.to_h.merge(described_class::LIGADA_KEY => valor))
  end

  # A IA dublada guarda o que recebeu (para conferir o contexto e o histórico) e responde `resposta_da_ia`.
  def ia_grava!(texto = nil)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      pedidos << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: Autonomia::Agents::AnswerResult.new(
        reply: texto || resposta_da_ia, confidence: 0.9, handoff: { should: false, reason: nil }, used_knowledge: [],
        answered_from_knowledge: false
      ))
    end
  end

  def ana_escreve(texto, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: ana,
                     content: texto, **extras)
  end

  def ana_passa!(agente = area, por: :pessoa)
    conversation.update!(assignee: ana) if por == :pessoa && conversation.reload.assignee_id.nil?
    Autonomia::Agents::PassarParaIa.call(conversation: conversation.reload, agent: agente, por: por, motivo: 'tela',
                                         origem: ana, pedida_por: por == :pessoa ? ana : nil)
  end

  def turnos_da_passagem
    jobs_de(UmTurnoHelper::REPLY_JOB).select { |job| ActiveJob::Arguments.deserialize(job[:args])[2] == described_class::FASE }
  end

  def silencios(linhas, motivo)
    linhas.grep(/\[autonomia\]\[operate\] silencio .*motivo=#{motivo}\b/)
  end

  def contexto
    pedidos.last[:contexto_do_turno].to_s
  end

  describe 'o turno da passagem' do
    before { ia_grava! }

    it 'exemplo 1: o cliente pediu e a Ana passou sem escrever: o agente responde uma vez, ancorado na passagem' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      linhas = linhas_do_log { ana_passa! }

      expect(turnos_da_passagem.size).to eq(1)
      rodar_turno!

      passagem = Crm::Passagens.ultima_aberta(conversation)
      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id, content: resposta_da_ia)
      expect(respostas.sole.content_attributes['autonomia_passagem_id']).to eq(passagem.id)
      expect(linhas.grep(/turno_da_passagem conv=#{conversation.id} passagem=#{passagem.id}/).size).to eq(1)
      expect(contexto).to include('Ana Souza', 'passou esta conversa para você',
                                  'não assuma como suas as promessas', '`conversation_closed_for_now`')
    end

    it 'o evento repetido não abre outro turno (SET NX por passagem), e o mesmo job rodando de novo não posta de novo' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      job = turnos_da_passagem.sole
      described_class.abrir(conversation)
      expect(turnos_da_passagem.size).to eq(1)

      rodar_turno!
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))

      expect(respostas.count).to eq(1)
    end

    it 'exemplo 3: o modelo decide calar com o sinal: nada é postado e a telemetria registra' do
      ia_grava!('conversation_closed_for_now')
      cliente_escreve('Obrigado!')
      ana_passa!

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(silencios(linhas, 'sinal').size).to eq(1)
      expect(linhas.grep(/sinal_na_passagem conv=#{conversation.id}/).size).to eq(1)
    end

    it 'nota privada nunca vai ao modelo; o que a Ana escreveu em público vai, marcado como dela' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_escreve('Cliente pediu 10% de desconto, não oferecer', private: true)
      ana_escreve('Vou te passar para nossa especialista.')
      ana_passa!

      rodar_turno!

      enviado = pedidos.last.values_at(:query, :history, :contexto_do_turno).to_s
      expect(enviado).not_to include('10% de desconto')
      expect(enviado).to include('Vou te passar para nossa especialista.')
    end

    it 'o cliente escreve antes de o turno rodar: o turno da passagem desiste e o turno da mensagem responde, com o contexto' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      turno = turnos_da_passagem.sole
      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(turno)
      travel 1.second
      mensagem = cliente_escreve('Alguém aí?')
      gatilho(mensagem)

      linhas = linhas_do_log do
        turno[:job].perform_now(*ActiveJob::Arguments.deserialize(turno[:args]))
        rodar_turno!
      end

      expect(silencios(linhas, 'cliente_escreveu').size).to eq(1)
      expect(respostas.sole.content_attributes['autonomia_reply_to_message_id']).to eq(mensagem.id)
      expect(contexto).to include('Ana Souza', 'passou esta conversa para você')
      expect(contexto).not_to include('conversation_closed_for_now')
    end

    it 'a Ana escreve de novo depois da passagem: a IA fica calada (ela está atendendo) e o modelo nem é chamado' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      travel 1.second
      ana_escreve('Ah, só mais uma coisa: a vistoria é amanhã.')

      linhas = linhas_do_log { rodar_turno! }

      expect(respostas).to be_empty
      expect(pedidos).to be_empty
      expect(silencios(linhas, 'pessoa_respondeu').size).to eq(1)
    end

    it 'depois que o agente falou, o turno normal seguinte não recebe mais o contexto da passagem' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      rodar_turno!
      travel 1.second
      mensagem = cliente_escreve('Beleza, obrigado.')
      gatilho(mensagem)

      rodar_turno!

      expect(respostas.count).to eq(2)
      expect(contexto).not_to include('passou esta conversa para você')
    end
  end

  describe 'quando o turno da passagem não abre' do
    before { ia_grava! }

    it 'a Lia (insurance_quote) fica de fora: nada de turno da passagem nem de contexto' do
      lia = criar_agente('Lia', agent_type: 'insurance_quote')
      Autonomia::Agents::Areas.vincular!(agent: lia, inbox: inbox)
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')

      expect(ana_passa!(lia).codigo).to eq(:passou)

      expect(turnos_da_passagem).to be_empty
      expect(Redis::Alfred.exists?(described_class.chave(Crm::Passagens.ultima_aberta(conversation).id))).to be(false)
    end

    it 'com a chave da conta desligada, tudo como antes: nenhum turno, nenhuma leitura da passagem' do
      ligar!(valor: false)
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      allow(Crm::Passagens).to receive(:ultima_aberta).and_call_original

      ana_passa!
      rodar_turno!

      expect(turnos_da_passagem).to be_empty
      expect(respostas).to be_empty
      expect(Crm::Passagens).not_to have_received(:ultima_aberta)
    end

    it 'sem a Fase 2, a chave da conta sozinha não liga nada' do
      Autonomia::Agents::Fase2.desligar!(account)

      expect(described_class.ligada?(account.reload)).to be(false)
    end

    it 'passagem pelo CRM (por: :crm) não abre o turno da passagem nem lê o registro' do
      cliente_escreve('Quero falar com o suporte.')
      allow(Crm::Passagens).to receive(:ultima_aberta).and_call_original

      expect(ana_passa!(por: :crm).codigo).to eq(:passou)

      expect(turnos_da_passagem).to be_empty
      expect(Crm::Passagens).not_to have_received(:ultima_aberta)
    end

    it 'passagem que não foi pedida por pessoa não vira contexto do turno normal' do
      expect(ana_passa!(por: :crm).codigo).to eq(:passou)
      mensagem = cliente_escreve('Quero falar com o suporte.')
      gatilho(mensagem)

      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(contexto).not_to include('passou esta conversa para você')
    end

    it 'outra passagem antes de o turno rodar: o turno da passagem antiga não fala por ninguém' do
      cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      ana_passa!
      antigo = turnos_da_passagem.sole
      clear_enqueued_jobs
      conversation.update!(assignee: ana)
      ana_passa!(agente_da_porta)

      antigo[:job].perform_now(*ActiveJob::Arguments.deserialize(antigo[:args]))

      expect(respostas).to be_empty
    end

    it 'troca de dono sem `por` (Sync do CRM, robô do n8n) não abre o turno da passagem' do
      cliente_escreve('Quero falar com o suporte.')

      trocar_dono!(espelho_area)

      expect(turnos_da_passagem).to be_empty
    end

    it 'turno do cliente em andamento quando a Ana passa: refaz o turno da mensagem e não abre outro (uma resposta só)' do
      mensagem = cliente_escreve('Quero cotar o seguro do meu Onix 2022.')
      gatilho(mensagem) # a porta marcou o debounce
      conversation.update!(assignee: ana)
      ana_passa!

      expect(turnos_da_passagem).to be_empty
      rodar_turno!

      expect(respostas.sole).to have_attributes(sender_id: espelho_area.id)
      expect(contexto).to include('passou esta conversa para você')
    end
  end
end
