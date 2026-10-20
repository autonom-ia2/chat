require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1925): a rodada para ao passar de US$ 0,27, somado
# pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1925, card que renasce: o cliente volta depois de um card encerrado e um card novo nasce. Cada caso roda a IA de etapa
# real (Evaluator#stage_classifier, o mesmo caminho da avaliação) duas vezes: "antes" sem o pedido anterior (como a main)
# e "depois" com ele. Três ramos de negócio, conversas inventadas, quatro casos por ramo:
# - outra_conversa: a proposta foi enviada na conversa do card perdido; o cliente volta por outra conversa e cita o pedido;
# - outra_conversa_vaga: o mesmo, mas o cliente volta sem dizer qual era o pedido ("aquilo que você me mandou");
# - mesma_conversa: a proposta ficou fora da janela de mensagens recentes da mesma conversa (volta vaga);
# - outro_pedido (controle): o card anterior foi ganho e o cliente pede OUTRA coisa; o card novo não pode herdar etapa
#   nem valor do anterior.
# As decisões (etapa, valor, custo) vão para EVAL_SAIDA (JSON). Nenhum prompt é gravado.
module PedidoAnteriorEval
  TETO_USD = 0.27
  ETAPAS = [
    ['Novo', 'Primeiro contato: ainda não sabemos o que o cliente quer.'],
    ['Em atendimento', 'Entendemos o pedido e estamos levantando dados para montar a proposta.'],
    ['Proposta enviada', 'Já enviamos ao cliente uma proposta ou orçamento com preço.'],
    ['Negociação', 'O cliente está discutindo condições, prazo ou desconto de uma proposta já enviada.']
  ].freeze
  AVANCADAS = ['Proposta enviada', 'Negociação'].freeze
  INICIAIS = ['Novo', 'Em atendimento'].freeze
  MODOS = %i[antes depois].freeze
  # O que o cliente diz ao voltar, por caso. "vaga": só quem leu o pedido anterior sabe que há proposta.
  FALA_DA_VOLTA = { outra_conversa: :volta, outra_conversa_vaga: :vaga, mesma_conversa: :vaga, outro_pedido: :outro }.freeze

  RAMOS = {
    'seguro' => {
      pedido: 'Cotação do seguro do carro',
      inicio: ['Boa tarde, quero cotar o seguro do meu carro, um sedan 2021.', 'Claro! Me passa o CEP e se tem garagem?',
               'CEP 80010-000, tenho garagem sim.'],
      proposta: 'Pronto! O seguro completo ficou em R$ 2.380,00 à vista ou 10x de R$ 238,00.',
      fim: ['Vou pensar e te aviso.', 'Combinado, fico à disposição.'],
      volta: 'Oi, voltei. Aquela cotação do seguro do carro ainda está valendo? Queria fechar.',
      vaga: 'Oi, tudo bem? Pensei melhor e decidi: pode seguir com aquilo que você me mandou.',
      valor: 238_000,
      ganho: 'Fechado, pode emitir a apólice do carro.',
      outro: 'Oi! Agora quero cotar um seguro para o meu apartamento, é alugado.'
    },
    'escola de idiomas' => {
      pedido: 'Curso de inglês',
      inicio: ['Olá, vocês têm curso de inglês para adultos à noite?', 'Temos sim! Qual o seu nível hoje?',
               'Básico, parei faz anos.'],
      proposta: 'Para o básico noturno, a mensalidade fica em R$ 390,00, com material incluso, duração de 12 meses.',
      fim: ['Vou ver com meu chefe o horário e retorno.', 'Perfeito, aguardo!'],
      volta: 'Oi, consegui liberar a noite no trabalho. Aquela turma de inglês de R$ 390 ainda tem vaga? Quero fechar.',
      vaga: 'Oi! Consegui ajeitar o horário. Vamos seguir com aquilo que você me passou?',
      valor: 468_000,
      ganho: 'Fechado, pode fazer a matrícula no inglês.',
      outro: 'Oi! Minha filha de 9 anos quer aprender espanhol, vocês têm turma infantil?'
    },
    'reforma' => {
      pedido: 'Reforma do banheiro',
      inicio: ['Bom dia, preciso de orçamento para reformar o banheiro, uns 4 m².', 'Bom dia! Troca de piso e louças também?',
               'Sim, piso, revestimento e o vaso.'],
      proposta: 'Segue o orçamento: mão de obra e material ficam em R$ 8.900,00, prazo de 15 dias.',
      fim: ['Achei salgado, vou pesquisar.', 'Tudo bem, qualquer coisa estamos aqui.'],
      volta: 'Bom dia, pesquisei e o de vocês ainda é o melhor. O orçamento do banheiro ainda vale? Dá para começar mês que vem?',
      vaga: 'Bom dia, conversei aqui em casa e vamos fazer. Mantém aquilo que vocês me mandaram?',
      valor: 890_000,
      ganho: 'Fechado, podem começar o banheiro na segunda.',
      outro: 'Bom dia! Agora quero pintar a fachada da casa, vocês fazem pintura externa?'
    }
  }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1925: card que renasce no mesmo pedido' do
  let(:account) { create(:account, name: 'Conta Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
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
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1925-pedido-anterior.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > PedidoAnteriorEval::TETO_USD

    ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
  end

  def funil(ramo)
    pipeline = account.crm_pipelines.create!(name: "Comercial #{ramo}", created_by: admin, status: :active)
    PedidoAnteriorEval::ETAPAS.each_with_index do |(nome, criterio), posicao|
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: { 'ai_criteria' => criterio })
    end
    pipeline
  end

  def etapa(pipeline, nome) = pipeline.stages.find_by!(name: nome)

  def conversa(contato) = create(:conversation, account: account, inbox: inbox, contact: contato, status: :open).reload

  def fala(conversa, texto, cliente:, quando:)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: cliente ? :incoming : :outgoing,
                     content: texto, sender: cliente ? conversa.contact : admin, created_at: quando)
  end

  # O roteiro do pedido anterior: cliente e atendente alternando, a proposta no meio. `extras` empurra a proposta para fora
  # da janela de mensagens recentes (caso da mesma conversa).
  def historia(conversa, dados, inicio:, extras: 0)
    falas = dados[:inicio] + [dados[:proposta]] + Array.new(extras) { |i| i.even? ? 'Entendi.' : 'Mais alguma dúvida?' } + dados[:fim]
    falas.each_with_index { |texto, i| fala(conversa, texto, cliente: i.even?, quando: inicio + i.minutes) }
  end

  def card!(pipeline, contato, conversa, titulo, etapa_nome)
    account.crm_cards.create!(pipeline: pipeline, stage: etapa(pipeline, etapa_nome), contact: contato, title: titulo,
                              primary_conversation: conversa, inbox: inbox, currency: 'BRL')
  end

  # Monta o caso e devolve [card novo, pipeline]. O card anterior nasce e fecha dias antes do novo.
  def montar(ramo, tipo)
    dados = PedidoAnteriorEval::RAMOS.fetch(ramo)
    pipeline = funil(ramo)
    contato = create(:contact, account: account, name: "Cliente #{ramo}")
    antiga = conversa(contato)
    pedido_encerrado!(pipeline, antiga, dados, tipo)
    nova = tipo == :mesma_conversa ? antiga : conversa(contato)
    novo = card!(pipeline, contato, nova, 'Novo contato', 'Novo')
    fala(nova, 'Oi', cliente: true, quando: 1.minute.from_now)
    fala(nova, dados.fetch(PedidoAnteriorEval::FALA_DA_VOLTA.fetch(tipo)), cliente: true, quando: 2.minutes.from_now)
    [novo, pipeline]
  end

  def pedido_encerrado!(pipeline, antiga, dados, tipo)
    anterior = travel_to(5.days.ago) { card!(pipeline, antiga.contact, antiga, dados[:pedido], 'Proposta enviada') }
    historia(antiga, dados, inicio: 5.days.ago, extras: tipo == :mesma_conversa ? 14 : 0)
    travel_to(4.days.ago) do
      fala(antiga, dados[:ganho], cliente: true, quando: Time.current) if tipo == :outro_pedido
      anterior.update!(status: tipo == :outro_pedido ? :won : :lost)
    end
  end

  # "antes" = como a main, sem o pedido anterior; "depois" = com ele.
  def classificar(card, com_anterior:)
    if com_anterior
      allow(Crm::Ai::PedidoAnterior).to receive(:do_card).and_call_original
    else
      allow(Crm::Ai::PedidoAnterior).to receive(:do_card).and_return(nil)
    end
    avaliador = Crm::Ai::Evaluator.new(card: card.reload, trigger: 'manual')
    com_custo { avaliador.stage_classifier(client: avaliador.classify_client).perform }
  end

  def certo?(tipo, etapa_nome, valor)
    return PedidoAnteriorEval::INICIAIS.include?(etapa_nome) && valor.nil? if tipo == :outro_pedido

    PedidoAnteriorEval::AVANCADAS.include?(etapa_nome)
  end

  it 'antes x depois, 3 ramos x 4 casos' do # rubocop:disable RSpec/NoExpectationExample
    PedidoAnteriorEval::RAMOS.each_key do |ramo|
      PedidoAnteriorEval::FALA_DA_VOLTA.each_key do |tipo|
        card, pipeline = montar(ramo, tipo)
        travel_to(3.minutes.from_now) do
          PedidoAnteriorEval::MODOS.each do |modo|
            resultado = classificar(card, com_anterior: modo == :depois)
            nome = pipeline.stages.find_by(id: resultado[:suggested_stage_id])&.name
            valor = resultado.dig(:value, :amount_cents)
            saida[:casos] << { ramo: ramo, tipo: tipo, modo: modo, etapa: nome, confianca: resultado[:confidence],
                               valor_centavos: valor, certo: certo?(tipo, nome, valor),
                               valor_certo: valor == (tipo == :outro_pedido ? nil : PedidoAnteriorEval::RAMOS.dig(ramo, :valor)) }
          end
        end
      end
    end
    gravar_saida!
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
