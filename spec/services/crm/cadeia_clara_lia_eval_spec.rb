require 'rails_helper'

# EVAL PAGO, DESLIGADO POR PADRÃO (#1606, worktree descartável teste/1606-cadeia = main + PR-B dos Agentes + C + D).
# Clara (porta) → Lia (área de Seguros) → Clara, com a IA de assunto REAL (Jev, chave em TYPESAFE_API_KEY, entra por
# stub de TypesafeAi::Config.api_key) e o resto real (revisor do assunto, Responder/Answerer, IA do CRM) pela chave
# OPENAI_API_KEY. Mede, por repetição:
#   a) o assunto é decidido (SubjectDecision fora de pending) antes da primeira resposta do turno;
#   b) no turno 2 quem responde é a Lia, com o funil atual = Seguros;
#   c) no turno 3 quem responde é a Clara e o registro tem a volta Lia → Clara, com a ida para a Lia devolvida;
#   d) nenhum turno com resposta de dois agentes ou mais de uma geração postada, e nenhuma troca de dono repetida.
# Teto: para quando o custo gravado (Crm::AiUsageEvent) passa de CADEIA_TETO_USD. Nada de prompt ou chave na saída.
module CadeiaEval
  REPETICOES = ENV.fetch('CADEIA_REPETICOES', '5').to_i
  TETO_USD = ENV.fetch('CADEIA_TETO_USD', '1.70').to_f
  CLARA = 'Você é a Clara, da recepção da Vale. Cumprimente, entenda o assunto e responda curto. Não invente preços.'.freeze
  LIA = 'Você é a Lia, de seguros da Vale. Responda dúvidas de seguro de carro e de moto, curto. Não invente preços.'.freeze
  ANA = 'Você é a Ana, do financeiro da Vale. Responda sobre boletos e pagamentos, curto. Não invente valores.'.freeze
  TURNOS = [['Oi', :clara], ['Quero seguro para a moto', :lia], ['Qual o endereço da loja?', :clara]].freeze
end

RSpec.describe 'Eval pago #1606: Clara → Lia → Clara com a IA de assunto real' do # rubocop:disable RSpec/DescribeClass
  let(:saida) { { repeticoes: [], custo_usd: 0.0 } }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    ligado = ENV['CADEIA_EVAL_PAGO'] == '1' && ENV['TYPESAFE_API_KEY'].present? && ENV['OPENAI_API_KEY'].present?
    skip 'eval pago: CADEIA_EVAL_PAGO=1, TYPESAFE_API_KEY e OPENAI_API_KEY' unless ligado

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(TypesafeAi::Config).to receive(:api_key).and_return(ENV.fetch('TYPESAFE_API_KEY'))
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: ENV.fetch('OPENAI_API_KEY'))
    contar_geracoes!
  end

  after { Current.reset }

  def geracoes
    @geracoes ||= []
  end

  # Cada chamada real ao Answerer (o que o modelo gerou), com o agente; o que foi postado se conta pelas mensagens.
  def contar_geracoes!
    allow(Autonomia::Agents::Answerer).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      instancia = original.call(*args, **kwargs)
      allow(instancia).to receive(:answer).and_wrap_original do |metodo, *a, **k|
        geracoes << kwargs[:agent]&.name
        metodo.call(*a, **k)
      end
      instancia
    end
  end

  def agente(conta, nome, instrucao)
    Autonomia::Agents::Agent.create!(account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: instrucao)
  end

  def funil(conta, admin, inbox, nome)
    pipeline = create_crm_pipeline(account: conta, user: admin, name: nome).first
    conta.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    pipeline
  end

  def area_com_funil(ctx, nome, instrucao, nome_do_funil)
    area = agente(ctx[:conta], nome, instrucao)
    Autonomia::Agents::Areas.vincular!(agent: area, inbox: ctx[:inbox])
    Crm::InboxAiAgent.create!(account: ctx[:conta], inbox: ctx[:inbox], pipeline: funil(ctx[:conta], ctx[:admin], ctx[:inbox], nome_do_funil),
                              agent: area)
    area
  end

  # O mesmo desenho do um_turno_eval_spec do PR-B: porta Clara, Lia em Seguros, Ana no Financeiro, Geral sem responsável.
  def montar
    conta = conta_da_fase2
    ctx = { conta: conta, admin: create(:user, account: conta, role: :administrator),
            inbox: create(:inbox, account: conta, enable_auto_assignment: false) }
    clara = agente(conta, 'Clara', CadeiaEval::CLARA)
    Autonomia::Agents::Operate::InboxConnector.new(agent: clara, inbox: ctx[:inbox]).perform(connect: true)
    conta.crm_inbox_settings.create!(inbox: ctx[:inbox], crm_enabled: true, subject_ai_mode: :auto)
    ctx[:agentes] = { clara: clara, lia: area_com_funil(ctx, 'Lia', CadeiaEval::LIA, 'Seguros'),
                      ana: area_com_funil(ctx, 'Ana', CadeiaEval::ANA, 'Financeiro') }
    funil(conta, ctx[:admin], ctx[:inbox], 'Geral')
    ctx
  end

  def custo(conta)
    Crm::AiUsageEvent.where(account_id: conta.id).sum(:cost_estimate).to_f
  end

  def jobs_rodados
    @jobs_rodados ||= []
  end

  def rodar_tudo!
    150.times do
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.min_by { |item| item[:at].to_f }
      break if job.nil?

      ActiveJob::Base.queue_adapter.enqueued_jobs.delete(job)
      jobs_rodados << job[:job].to_s
      travel_to(Time.zone.at(job[:at])) if job[:at] && Time.zone.at(job[:at]) > Time.current
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def nome_do_dono(ctx, conversa)
    bot_id = conversa.reload.assignee_agent_bot_id
    ctx[:agentes].key(Autonomia::Agents::AgentInbox.find_by(agent_bot_id: bot_id)&.agent)
  end

  def rodar_turno(ctx, conversa, texto, esperado)
    ultima = conversa.messages.maximum(:id).to_i
    trocas_antes = Crm::Activity.where(conversation_id: conversa.id, event_type: Crm::Ai::ResponsibleAgentSync::EVENTO).count
    geracoes.clear
    jobs_rodados.clear
    mensagem = create(:message, account: ctx[:conta], conversation: conversa, inbox: ctx[:inbox], message_type: :incoming,
                                content: texto)
    inicio = Time.current
    rodar_tudo!
    novas = conversa.messages.outgoing.where(sender_type: 'AgentBot', private: false).where('id > ?', ultima).order(:id).to_a
    decisao = Crm::SubjectDecision.find_by(conversation_id: conversa.id, message_id: mensagem.id)
    funil = Crm::Assunto.funil_atual(conversa.reload)&.pipeline&.name
    responderam = novas.map { |m| ctx[:agentes].key(Autonomia::Agents::AgentInbox.find_by(agent_bot_id: m.sender_id)&.agent) }.uniq
    {
      esperado: esperado, responderam: responderam, mensagens_postadas: novas.size, geracoes: geracoes.dup,
      dono_no_fim: nome_do_dono(ctx, conversa), funil_atual: funil, jobs: jobs_rodados.tally,
      decisao: decisao && { estado: decisao.state, acao: decisao.action, por: decisao.decided_by, certeza: decisao.confidence&.round(3),
                            motivo_curto: decisao.reason.to_s.first(60).presence,
                            pipeline: decisao.pipeline_id && Crm::Pipeline.find_by(id: decisao.pipeline_id)&.name },
      decidido_antes_da_resposta: decidido_antes?(decisao, novas.first),
      segundos_ate_decidir: decisao && (decisao.updated_at - inicio).round(1),
      segundos_ate_responder: novas.first && (novas.first.created_at - inicio).round(1),
      trocas_de_dono: Crm::Activity.where(conversation_id: conversa.id, event_type: Crm::Ai::ResponsibleAgentSync::EVENTO).count - trocas_antes
    }
  end

  def decidido_antes?(decisao, primeira)
    return false if decisao.nil? || decisao.state == 'pending' || primeira.nil?

    decisao.updated_at <= primeira.created_at
  end

  def passagens(conversa)
    Crm::Passagem.where(conversation_id: conversa.id).order(:id).map do |p|
      { de: p.de_nome, para: p.para_nome, motivo: p.motivo, devolvida: p.devolvida_em.present?, devolvida_por: p.devolvida_por_nome }
    end
  end

  # Critério d (#1606): uma mensagem do cliente = UMA resposta, mesmo com a troca de dono pelo assunto no meio do turno:
  # um agente só, uma geração do Answerer, uma mensagem pública e no máximo uma troca de dono.
  def resposta_unica?(turno)
    turno[:responderam].size == 1 && turno[:geracoes].size == 1 && turno[:mensagens_postadas] == 1 && turno[:trocas_de_dono] <= 1
  end

  def medir(turnos, registro)
    t1, t2, t3 = turnos
    volta = registro.any? { |p| p[:de] == 'Lia' && p[:para] == 'Clara' }
    ida_devolvida = registro.any? { |p| p[:para] == 'Lia' && p[:devolvida] }
    pares = registro.map { |p| [p[:de], p[:para]] }
    {
      a: turnos.all? { |t| t[:decidido_antes_da_resposta] },
      b: t2[:responderam] == [:lia] && t2[:funil_atual] == 'Seguros',
      c: t3[:responderam] == [:clara] && volta && ida_devolvida,
      d: turnos.all? { |t| resposta_unica?(t) } && pares.uniq.size == pares.size
    }.tap { |m| m[:t1_ok] = t1[:responderam] == [:clara] }
  end

  it 'cinco repetições, cada uma em conta nova' do
    CadeiaEval::REPETICOES.times do |i|
      ctx = montar
      conversa = create(:conversation, account: ctx[:conta], inbox: ctx[:inbox], status: :open)
      turnos = CadeiaEval::TURNOS.map { |texto, esperado| rodar_turno(ctx, conversa, texto, esperado) }
      falha_jev = turnos.filter_map { |t| t.dig(:decisao, :motivo_curto) }.find { |m| m.start_with?('typesafe_invalid_key') }
      raise 'Jev recusou a chave (401): parei' if falha_jev

      registro = passagens(conversa)
      gasto = custo(ctx[:conta])
      saida[:custo_usd] += gasto
      saida[:repeticoes] << { n: i + 1, turnos: turnos, passagens: registro, medidas: medir(turnos, registro), custo_usd: gasto.round(4) }
      break if saida[:custo_usd] >= CadeiaEval::TETO_USD
    ensure
      travel_back
    end
  ensure
    destino = ENV['CADEIA_SAIDA'].presence
    File.write(destino, JSON.pretty_generate(saida.merge(custo_usd: saida[:custo_usd].round(4)))) if destino
  end
end
