require 'rails_helper'

# AVALIAÇÃO PAGA DE "UM TURNO, UMA ORDEM" (#1606), DESLIGADA POR PADRÃO. Só faz sentido com as DUAS metades na main: a
# dos Agentes (este PR) e a do Multifunnel (a IA de assunto, o marco, a regra única do turno, o registro das passagens).
# Roda com `AUTONOMIA_EVAL_PAGO=1`, `UM_TURNO_EVAL=1` e `OPENAI_API_KEY`, com o modelo real do Answerer e da IA de
# assunto; o canal é o de teste (nada sai para cliente). Teto: o custo é somado pelo consumo gravado
# (Crm::AiUsageEvent, o mesmo do Crm::Ai::UsageRecorder) e a rodada para antes de passar de US$ 1,80.
# Opcional: `UM_TURNO_EVAL_SAIDA=<arquivo>` grava o relatório por conversa (quem respondeu, respostas por turno,
# latência, rótulos do turno) para a verificação final do Multifunnel.
#
# O que se confere é ESTRUTURA (quantas respostas, de qual agente, em quanto tempo), nunca o texto por lista de
# palavras. O pedido pelo nome é decidido pelo modelo; aqui só se mede quem acabou respondendo.
module AvaliacaoDoTurno
  TETO_USD = 1.8
  LATENCIA_MAXIMA = 45.seconds

  CLARA = 'Você é a Clara, da recepção da Vale. Cumprimente, entenda o assunto e responda curto. Não invente preços.'.freeze
  LIA = 'Você é a Lia, de seguros da Vale. Responda dúvidas de seguro auto, curto. Não invente preços.'.freeze
  ANA = 'Você é a Ana, do financeiro da Vale. Responda sobre boletos e pagamentos, curto. Não invente valores.'.freeze

  # Cada roteiro: as mensagens do cliente (uma por turno) e quem deve responder cada turno. `antes` prepara o turno
  # (ex.: uma pessoa assume e devolve). Nomes: :clara (porta), :lia (área de Seguros), :ana (área do Financeiro).
  ROTEIROS = [
    { nome: 'devolvido e já atendido', turnos: [['Oi, quero cotar um seguro para o meu carro', :lia],
                                                ['Na verdade já resolvi com vocês ontem, obrigado', :lia]] },
    { nome: 'volta à origem', turnos: [['Oi, bom dia', :clara], ['Quero cotar seguro auto', :lia],
                                       ['Era só isso, pode me passar de volta para a recepção?', :clara]] },
    { nome: 'volta pelo nome', turnos: [['Quero pagar um boleto atrasado', :ana], ['Quero falar com a Lia do seguro', :lia]] },
    { nome: 'modo convite', turnos: [['Preciso falar com uma pessoa do financeiro', :ana]], antes: :convite },
    { nome: 'sem regra do funil', turnos: [['Vocês vendem consórcio?', :clara]] },
    { nome: 'atribuição manual', turnos: [['Quero cotar seguro', :lia], ['E o boleto, quando vence?', :lia]],
      antes: :pessoa_devolve },
    { nome: 'Clara→Lia→Clara', turnos: [['Oi', :clara], ['Quero seguro para a moto', :lia], ['Qual o endereço da loja?', :clara]] },
    { nome: 'Ana→Lia→Ana', turnos: [['Meu boleto venceu', :ana], ['E aproveitando, quero cotar seguro', :lia],
                                    ['Voltando ao boleto: posso pagar amanhã?', :ana]] },
    { nome: 'cenário 1: rajada com o assunto mudando', turnos: [[['oi', 'tudo bem?', 'quero pagar o boleto'], :ana]] },
    { nome: 'cenário 5: troca no meio da resposta', turnos: [['Quero cotar seguro e pagar o boleto', :lia]] },
    { nome: 'cenário 11: desatribuir volta ao responsável do funil', turnos: [['Meu boleto venceu', :ana]],
      antes: :pessoa_devolve }
  ].freeze
end

RSpec.describe 'Avaliação paga do turno (#1606)', :eval_pago do # rubocop:disable RSpec/DescribeClass
  let(:conta) { conta_da_fase2 }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:inbox) { create(:inbox, account: conta, enable_auto_assignment: false) }
  let(:relatorio) { [] }

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def custo_ate_agora
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def agente(nome, instrucao)
    Autonomia::Agents::Agent.create!(account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: instrucao)
  end

  # Recepção (porta) e duas áreas, cada uma responsável por um funil da caixa; o funil "Geral" fica sem responsável.
  def montar_caixa
    clara = agente('Clara', AvaliacaoDoTurno::CLARA)
    Autonomia::Agents::Operate::InboxConnector.new(agent: clara, inbox: inbox).perform(connect: true)
    conta.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true)
    { clara: clara, lia: area_com_funil('Lia', AvaliacaoDoTurno::LIA, 'Seguros'),
      ana: area_com_funil('Ana', AvaliacaoDoTurno::ANA, 'Financeiro') }.tap { funil('Geral') }
  end

  def funil(nome)
    pipeline = create_crm_pipeline(account: conta, user: admin, name: nome).first
    conta.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    pipeline
  end

  def area_com_funil(nome, instrucao, nome_do_funil)
    area = agente(nome, instrucao)
    Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox)
    Crm::InboxAiAgent.create!(account: conta, inbox: inbox, pipeline: funil(nome_do_funil), agent: area)
    area
  end

  # Roda todos os jobs na fila, cada um na hora marcada, como o Sidekiq faria; teto contra laço.
  def rodar_tudo!
    100.times do
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.min_by { |item| item[:at].to_f }
      break if job.nil?

      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      travel_to(Time.zone.at(job[:at])) if job[:at] && Time.zone.at(job[:at]) > Time.current
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def preparar(conversa, preparo)
    pessoa = create(:user, account: conta, role: :agent)
    case preparo
    when :pessoa_devolve
      conversa.update!(assignee: pessoa)
      Conversations::AssignmentService.new(conversation: conversa, assignee_id: nil).perform
    when :convite
      conversa.bot_handoff!(motivo: 'eval_convite')
    end
  end

  def rodar_turno(conversa, mensagens, esperado, agentes)
    ultima = conversa.messages.maximum(:id).to_i
    inicio = Time.current
    Array(mensagens).each do |texto|
      create(:message, account: conta, conversation: conversa, inbox: inbox, message_type: :incoming, content: texto)
    end
    rodar_tudo!
    novas = conversa.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', ultima).order(:id).to_a
    { esperado: esperado, respondeu: quem_respondeu(novas, agentes), respostas: novas.size,
      latencia_s: novas.first ? (novas.first.created_at - inicio).round(1) : nil }
  end

  # O nome (:clara, :lia, :ana) do agente dono de cada espelho que postou.
  def quem_respondeu(mensagens, agentes)
    mensagens.map { |mensagem| agentes.key(Autonomia::Agents::AgentInbox.find_by(agent_bot_id: mensagem.sender_id)&.agent) }.uniq
  end

  def rodar(roteiro, agentes)
    conversa = create(:conversation, account: conta, inbox: inbox, status: :open)
    preparar(conversa, roteiro[:antes])
    turnos = roteiro[:turnos].map { |mensagens, esperado| rodar_turno(conversa, mensagens, esperado, agentes) }
    { roteiro: roteiro[:nome], turnos: turnos, custo_acumulado_usd: custo_ate_agora.round(4),
      aprovado: turnos.all? { |turno| turno_certo?(turno) } }
  end

  # Uma resposta (a entrega em pedaços posta até 5 mensagens), de um agente só, o esperado, dentro da latência.
  def turno_certo?(turno)
    turno[:respostas].between?(1, 5) && turno[:respondeu] == [turno[:esperado]] &&
      turno[:latencia_s].to_f <= AvaliacaoDoTurno::LATENCIA_MAXIMA.to_f
  end

  it 'cada turno tem uma resposta só, do dono certo, dentro do teto de espera' do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['UM_TURNO_EVAL'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1, UM_TURNO_EVAL=1 e OPENAI_API_KEY, com as duas metades' unless ligada

    expect(Crm::Subjects).to respond_to(:ordem_do_turno?), 'a metade do Multifunnel ainda não está aqui'
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    agentes = montar_caixa

    AvaliacaoDoTurno::ROTEIROS.each do |roteiro|
      break if custo_ate_agora >= AvaliacaoDoTurno::TETO_USD

      relatorio << rodar(roteiro, agentes)
    end

    destino = ENV.fetch('UM_TURNO_EVAL_SAIDA', nil)
    File.write(destino, JSON.pretty_generate(relatorio)) if destino.present?
    expect(relatorio.size).to eq(AvaliacaoDoTurno::ROTEIROS.size), "teto de custo atingido: #{relatorio.size} roteiros"
    expect(relatorio.reject { |linha| linha[:aprovado] }.pluck(:roteiro)).to be_empty
  end
end
