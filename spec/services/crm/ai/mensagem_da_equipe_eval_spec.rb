require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1923): a rodada para ao passar de US$ 0,27, somado
# pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1923: a equipe manda os valores depois da última mensagem do cliente. Conversas INVENTADAS de três ramos (seguro,
# clínica, móveis planejados), pelo caminho de produção: a mensagem passa pelo CardSyncer, que agenda (ou não) a
# avaliação, e o job roda com o classificador real.
#   - antes: a avaliação que já existia, a da última mensagem do cliente ("ok, fico no aguardo"). Sem o #1923, o card
#     ficava onde ela o deixou até o cliente voltar;
#   - depois: a avaliação agendada pela mensagem da equipe.
# Casos por ramo: valores numa mensagem, valores numa rajada de duas (uma avaliação só) e o controle, em que a equipe
# ainda não mandou valor nenhum ("amanhã te mando"): o card tem de ficar.
# As saídas vão para EVAL_SAIDA (JSON). Nenhum prompt é gravado.
module MensagemDaEquipeEval
  TETO_USD = 0.27
  ATENDIMENTO = 'Em atendimento'.freeze
  TIPOS = %i[valores rajada controle].freeze
  RAMOS = {
    'seguro' => {
      funil: 'Comercial', enviada: 'Cotação enviada', fechado: 'Fechado',
      criterios: {
        'Em atendimento' => 'O cliente pediu uma cotação e a equipe está levantando as informações.',
        'Cotação enviada' => 'A equipe enviou ao cliente os valores da cotação (preço, parcelas ou comparativo).',
        'Fechado' => 'O cliente aceitou a proposta e confirmou o pagamento ou a emissão.'
      },
      pedido: 'Oi, queria uma cotação de seguro para o meu carro, um hatch 2021.',
      espera: 'Claro! Vou levantar com as seguradoras e já te retorno.',
      ok: 'Ok, fico no aguardo.',
      valores: ['Pronto! Na seguradora A ficou R$ 2.380 por ano, em até 10x sem juros. Na B, R$ 2.610 com carro reserva.'],
      rajada: ['Segue a cotação do seu seguro auto.', 'Opção 1: R$ 2.380/ano em 10x. Opção 2: R$ 2.610/ano com carro reserva.'],
      controle: 'Ainda estou aguardando o retorno de duas seguradoras, amanhã cedo te mando tudo.'
    },
    'clinica' => {
      funil: 'Pacientes', enviada: 'Orçamento enviado', fechado: 'Consulta agendada',
      criterios: {
        'Em atendimento' => 'O paciente pediu informação ou orçamento e a equipe está avaliando o caso.',
        'Orçamento enviado' => 'A equipe enviou ao paciente o valor do tratamento ou da consulta.',
        'Consulta agendada' => 'O paciente marcou dia e horário para a consulta ou o procedimento.'
      },
      pedido: 'Bom dia, quanto custa um clareamento dental? Tenho sensibilidade.',
      espera: 'Bom dia! Vou ver com a doutora qual técnica é melhor no seu caso e te passo.',
      ok: 'Tá bom, obrigada.',
      valores: ['A doutora indicou o clareamento de consultório, em 2 sessões: R$ 1.200 à vista ou 4x de R$ 320.'],
      rajada: ['Falei com a doutora sobre o seu caso.', 'O clareamento fica R$ 1.200 à vista ou 4x de R$ 320, em 2 sessões.'],
      controle: 'A doutora está em atendimento agora, assim que ela sair eu confirmo com ela e te falo.'
    },
    'moveis' => {
      funil: 'Vendas', enviada: 'Proposta enviada', fechado: 'Fechado',
      criterios: {
        'Em atendimento' => 'O cliente pediu um projeto ou orçamento e a equipe está medindo ou desenhando.',
        'Proposta enviada' => 'A equipe enviou ao cliente a proposta com o valor do projeto.',
        'Fechado' => 'O cliente aprovou a proposta e assinou ou pagou a entrada.'
      },
      pedido: 'Olá, quero orçamento de cozinha planejada, a parede tem 3,20 m.',
      espera: 'Olá! Vou pedir para o projetista montar o desenho e te mando a proposta.',
      ok: 'Combinado.',
      valores: ['Sua proposta ficou pronta: cozinha em MDF branco, 3,20 m, R$ 18.400 em até 12x, entrega em 35 dias.'],
      rajada: ['O projeto da sua cozinha ficou pronto!', 'Valor total R$ 18.400, em até 12x, com entrega em 35 dias.'],
      controle: 'O projetista ainda está ajustando o desenho, devo te mandar até sexta.'
    }
  }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1923: a mensagem da equipe com os valores move o card' do
  include ActiveJob::TestHelper

  let(:account) { create(:account, name: 'Conta Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :off)
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1923-mensagem-da-equipe.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > MensagemDaEquipeEval::TETO_USD
  end

  def funil(ramo)
    pipeline = account.crm_pipelines.create!(name: ramo[:funil], created_by: admin, status: :active,
                                             metadata: { 'ai' => { 'enabled' => true, 'auto_move_enabled' => true } })
    nomes = ['Novo contato', *ramo[:criterios].keys, 'Perdido']
    criterios = ramo[:criterios].merge('Perdido' => 'O cliente desistiu, fechou com outro ou disse que não quer mais.')
    stages = nomes.each_with_index.to_h do |nome, posicao|
      metadata = criterios[nome] ? { 'ai_criteria' => criterios[nome] } : {}
      [nome, account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: metadata)]
    end
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stages['Novo contato'],
                                         auto_create_card: false, created_by: admin)
    stages
  end

  def card_em_atendimento(stages, nome)
    contact = create(:contact, account: account, name: nome)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, assignee: ana)
    card = account.crm_cards.create!(pipeline: stages.values.first.pipeline, stage: stages[MensagemDaEquipeEval::ATENDIMENTO],
                                     contact: contact, primary_conversation: conversa, inbox: inbox, title: "Pedido de #{nome}")
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa)
                         .update!(is_primary: true, focused_at: Time.current)
    [conversa, card]
  end

  def fala(conversa, texto, quem)
    tipo = quem == :cliente ? :incoming : :outgoing
    message = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: tipo, content: texto,
                               sender: quem == :cliente ? conversa.contact : ana)
    Crm::Conversations::CardSyncer.new(conversation: conversa.reload, message: message).perform
  end

  # Roda as avaliações agendadas no `momento`, como a fila faria; devolve quantas chegaram ao modelo.
  def rodar_agendadas(momento)
    jobs = enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
    clear_enqueued_jobs
    chamadas = 0
    allow(Crm::Ai::StageClassifier).to receive(:new).and_wrap_original do |original, **args|
      chamadas += 1
      original.call(**args)
    end
    travel_to(momento)
    com_custo { jobs.each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) } }
    chamadas
  end

  def etapa(card) = card.reload.stage.name

  # A conversa até o "ok" do cliente e a avaliação dela: a etapa em que o card ficava antes do #1923.
  def ate_o_ok(ramo, conversa, card, inicio)
    fala(conversa, ramo[:pedido], :cliente)
    travel_to(inicio + 1.minute) { fala(conversa, ramo[:espera], :equipe) }
    travel_to(inicio + 2.minutes) { fala(conversa, ramo[:ok], :cliente) }
    rodar_agendadas(inicio + 3.minutes)
    etapa(card)
  end

  # A equipe escreve 10 min depois; a avaliação roda depois da espera da equipe.
  def equipe_escreve(textos, conversa, inicio)
    textos.each_with_index { |texto, indice| travel_to(inicio + 10.minutes + (indice * 20).seconds) { fala(conversa, texto, :equipe) } }
    agendou = enqueued_jobs.count { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
    { avaliacoes_agendadas: agendou,
      chamadas_ao_modelo: rodar_agendadas(inicio + 10.minutes + Crm::Conversations::CardEmFoco::ESPERA_DA_EQUIPE + 1.minute) }
  end

  def caso(nome_do_ramo, ramo, tipo)
    inicio = Time.current
    conversa, card = card_em_atendimento(funil(ramo), "Cliente #{nome_do_ramo} #{tipo}")
    antes = ate_o_ok(ramo, conversa, card, inicio)
    textos = { valores: ramo[:valores], rajada: ramo[:rajada], controle: [ramo[:controle]] }.fetch(tipo)
    contagem = equipe_escreve(textos, conversa, inicio)
    travel_back
    esperado = tipo == :controle ? MensagemDaEquipeEval::ATENDIMENTO : ramo[:enviada]
    registro = { ramo: nome_do_ramo, tipo: tipo, esperado: esperado, antes: antes, depois: etapa(card), **contagem,
                 ultima_sugestao: ultima_sugestao(card) }
    saida[:casos] << registro
    registro
  end

  def ultima_sugestao(card)
    sugestao = card.account.crm_ai_stage_suggestions.where(card: card).order(:id).last
    sugestao && { para: sugestao.to_stage&.name, confianca: sugestao.confidence.to_f, status: sugestao.status }
  end

  it 'três ramos: valores, rajada e controle' do
    registros = MensagemDaEquipeEval::RAMOS.flat_map do |nome, ramo|
      MensagemDaEquipeEval::TIPOS.map { |tipo| caso(nome, ramo, tipo) }
    end
    gravar_saida!

    expect(registros.map { |registro| registro[:chamadas_ao_modelo] }).to all(be <= 1)
    expect(registros.reject { |registro| registro[:depois] == registro[:esperado] }).to be_empty
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
