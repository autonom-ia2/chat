require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 para a Issue #1920: a rodada para ao passar de
# US$ 0,28, somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1920: três ramos inventados, cada um com um funil de venda de frases fracas (fronteira mal definida). Em cada ramo:
# - casos ANTIGOS (40 dias) em que a IA de etapa errou e uma pessoa corrigiu: viram a evidência do "Melhorar com IA";
# - casos RECENTES (5 dias), com outras palavras, em que uma pessoa escolheu a etapa: são a prova do raio-x.
# Os dois grupos não se cruzam (o raio-x olha 30 dias; a evidência só pega correção logo depois da IA), então o improver
# nunca lê a resposta da prova. O placar é o do raio-x: frases originais × frases melhoradas, nos mesmos casos.
# Saída (placar, frases, custo) em EVAL_SAIDA (JSON). Dados fictícios; nenhum prompt é gravado.
module FrasesComEvidenciaEval
  TETO_USD = 0.28
  Conta = Struct.new(:account, :admin, :inbox)

  RAMOS = {
    'clinica_odontologica' => {
      industry: 'Clínica odontológica',
      etapas: [
        ['Novo contato', 'Cliente entrou em contato pela primeira vez.'],
        ['Em atendimento', 'A equipe está conversando com o cliente.'],
        ['Orçamento enviado', 'Valor do tratamento foi falado.'],
        ['Consulta agendada', 'Cliente marcou consulta.'],
        ['Perdido', 'Cliente desistiu.']
      ],
      evidencia: [
        { ia: 1, pessoa: 0, falas: [[:cliente, 'Oi, vocês fazem clareamento?'], [:equipe, 'Bom dia! Tudo bem?']] },
        { ia: 2, pessoa: 1, falas: [[:cliente, 'Quanto fica um implante?'],
                                    [:equipe, 'Vou te ligar à tarde para explicar o orçamento direitinho.']] },
        { ia: 2, pessoa: 4, falas: [[:equipe, 'A limpeza sai por R$ 250.'], [:cliente, 'Obrigada, já fiz com outro dentista mês passado.']] }
      ],
      prova: [
        { de: 1, certa: 0, falas: [[:cliente, 'Vocês atendem aos sábados?'], [:equipe, 'Olá! Tudo bem com você?']] },
        { de: 2, certa: 1, falas: [[:cliente, 'Qual o valor da prótese?'],
                                   [:equipe, 'Amanhã eu te ligo para apresentar o orçamento com calma.']] },
        { de: 2, certa: 4, falas: [[:equipe, 'O tratamento de canal fica R$ 900.'],
                                   [:cliente, 'Já resolvi com outro profissional, obrigado.']] },
        { de: 1, certa: 2, falas: [[:cliente, 'Quanto é o aparelho?'],
                                   [:equipe, 'O aparelho fixo fica R$ 180 por mês, com manutenção inclusa.']] },
        { de: 2, certa: 3, falas: [[:equipe, 'Posso marcar para quinta às 14h?'], [:cliente, 'Pode sim, quinta às 14h está ótimo.']] }
      ]
    },
    'corretora_de_seguros' => {
      industry: 'Corretora de seguros',
      etapas: [
        ['Novo', 'Primeiro contato.'],
        ['Cotando', 'Estamos fazendo a cotação.'],
        ['Cotação apresentada', 'Cotação passada para o cliente.'],
        ['Fechado', 'Cliente fechou.'],
        ['Perdido', 'Cliente desistiu.']
      ],
      evidencia: [
        { ia: 2, pessoa: 1, falas: [[:cliente, 'Quero cotar o seguro do meu carro, é um hatch 2019.'],
                                    [:equipe, 'Vou te ligar para apresentar a cotação.']] },
        { ia: 2, pessoa: 4, falas: [[:equipe, 'A renovação ficou R$ 2.300.'], [:cliente, 'Não é mais necessário, vendi o carro.']] },
        { ia: 1, pessoa: 4, falas: [[:cliente, 'Bom dia, pode parar a cotação, já fiz com outra corretora.']] }
      ],
      prova: [
        { de: 2, certa: 1, falas: [[:cliente, 'Conseguiu ver o valor do seguro da moto?'],
                                   [:equipe, 'Consegui sim, te ligo daqui a pouco para apresentar a cotação.']] },
        { de: 2, certa: 4, falas: [[:equipe, 'Segue a cotação: R$ 1.800 à vista.'], [:cliente, 'Obrigado, mas já resolvi com o banco.']] },
        { de: 1, certa: 4, falas: [[:cliente, 'Pode cancelar a cotação, não é mais necessário.']] },
        { de: 1, certa: 2, falas: [[:equipe, 'Ficou R$ 2.100 em 10x sem juros, cobertura completa.'], [:cliente, 'Vou analisar.']] },
        { de: 2, certa: 3, falas: [[:cliente, 'Pode fechar, me manda o boleto.'], [:equipe, 'Fechado! Boleto enviado.']] }
      ]
    },
    'escola_de_idiomas' => {
      industry: 'Escola de idiomas',
      etapas: [
        ['Interessado', 'Pessoa pediu informações.'],
        ['Aula experimental agendada', 'Aluno quer fazer aula experimental.'],
        ['Negociando matrícula', 'Falando de preço e plano.'],
        ['Matriculado', 'Matrícula feita.'],
        ['Perdido', 'Desistiu.']
      ],
      evidencia: [
        { ia: 1, pessoa: 0, falas: [[:cliente, 'Queria fazer uma aula teste de inglês, como funciona?'],
                                    [:equipe, 'São 50 minutos com um professor.']] },
        { ia: 1, pessoa: 0, falas: [[:cliente, 'Posso passar aí amanhã pra conhecer?']] },
        { ia: 2, pessoa: 4, falas: [[:equipe, 'O plano semestral fica R$ 390 por mês.'], [:cliente, 'Ah, já fiz a matrícula em outra escola.']] }
      ],
      prova: [
        { de: 1, certa: 0, falas: [[:cliente, 'Tenho interesse numa aula experimental de espanhol.'],
                                   [:equipe, 'Que ótimo! Temos horários de manhã e à noite.']] },
        { de: 1, certa: 0, falas: [[:cliente, 'Será que dá pra eu ir aí sexta conhecer a escola?'], [:equipe, 'Oi! Seja bem-vindo.']] },
        { de: 2, certa: 4, falas: [[:equipe, 'O pacote anual sai por R$ 320 mensais.'],
                                   [:cliente, 'Obrigada, mas não é mais necessário, consegui bolsa em outro lugar.']] },
        { de: 0, certa: 1, falas: [[:equipe, 'Agendei sua aula experimental para terça às 19h, ok?'],
                                   [:cliente, 'Ok, terça 19h confirmado.']] },
        { de: 2, certa: 3, falas: [[:cliente, 'Fiz o pagamento da matrícula agora.'], [:equipe, 'Recebido! Bem-vindo à escola.']] }
      ]
    }
  }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1920: frases das etapas com evidência real e raio-x' do
  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, ramos: {}, custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1920-frases.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > FrasesComEvidenciaEval::TETO_USD

    resultado
  end

  # Uma conta por ramo, com a pessoa que move os cards e a caixa das conversas.
  def nova_conta(industry)
    account = create(:account, custom_attributes: { 'industry' => industry })
    FrasesComEvidenciaEval::Conta.new(account, create(:user, account: account, role: :administrator), create_crm_inbox(account: account))
  end

  def montar_funil(conta, ramo)
    pipeline = conta.account.crm_pipelines.create!(name: 'Vendas', created_by: conta.admin, status: :active)
    etapas = ramo[:etapas].each_with_index.map do |(nome, frase), posicao|
      conta.account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: { 'ai_criteria' => frase })
    end
    [pipeline, etapas]
  end

  def card_com_conversa(conta, etapa, falas, quando)
    contact = create(:contact, account: conta.account)
    conversation = create_crm_conversation(account: conta.account, inbox: conta.inbox, contact: contact)
    falas.each_with_index do |(quem, texto), index|
      conversation.messages.create!(account_id: conta.account.id, inbox_id: conta.inbox.id, content: texto,
                                    created_at: quando + index.minutes,
                                    message_type: quem == :cliente ? :incoming : :outgoing, sender: quem == :cliente ? contact : conta.admin)
    end
    conta.account.crm_cards.create!(pipeline: etapa.pipeline, stage: etapa, title: 'Pedido', conversation_id: conversation.id)
  end

  def mover_pela_pessoa(conta, card, origem, destino, quando)
    Crm::Activity.create!(account: conta.account, card: card, actor_type: 'user', actor_id: conta.admin.id, event_type: 'move',
                          created_at: quando,
                          payload: { from_pipeline_id: origem.pipeline_id, to_pipeline_id: destino.pipeline_id,
                                     from_stage_id: origem.id, to_stage_id: destino.id })
  end

  # A IA errou: moveu sozinha (sugestão aplicada) e uma pessoa corrigiu uma hora depois. 40 dias atrás: fora do raio-x.
  def plantar_evidencia(conta, etapas, caso)
    quando = 40.days.ago
    card = card_com_conversa(conta, etapas[caso[:pessoa]], caso[:falas], quando)
    conta.account.crm_ai_stage_suggestions.create!(card: card, from_stage: etapas[0], to_stage: etapas[caso[:ia]], confidence: 0.8,
                                                   model_used: 'gpt-6-luna', status: :auto_applied, reasoning: 'Decisão anterior da IA.',
                                                   created_at: quando + 10.minutes, updated_at: quando + 10.minutes)
    mover_pela_pessoa(conta, card, etapas[caso[:ia]], etapas[caso[:pessoa]], quando + 70.minutes)
  end

  # Uma pessoa escolheu a etapa há poucos dias: é a prova do raio-x.
  def plantar_prova(conta, etapas, caso, index)
    quando = (5.days + index.hours).ago
    card = card_com_conversa(conta, etapas[caso[:certa]], caso[:falas], quando)
    mover_pela_pessoa(conta, card, etapas[caso[:de]], etapas[caso[:certa]], quando + 30.minutes)
  end

  # O "Melhorar com IA" em cada etapa que tem evidência, uma de cada vez, sempre com as frases da tela até ali.
  def melhorar(pipeline, etapas, telas)
    etapas.each_with_index do |etapa, index|
      next if Crm::Ai::EvidenciaDaEtapa.new(stage: etapa).casos.empty?

      resposta = com_custo do
        Crm::Ai::StageCriteriaImprover.new(pipeline: pipeline, stages: telas, stage_index: index, language: 'pt_BR').perform
      end
      telas = telas.each_with_index.map { |tela, posicao| posicao == index ? tela.merge('description' => resposta['description']) : tela }
    end
    telas
  end

  def placar(raio_x)
    { antes: "#{raio_x[:acertos_atual]} de #{raio_x[:total]}", depois: "#{raio_x[:acertos_nova]} de #{raio_x[:total]}" }
  end

  def medir_ramo(nome, ramo)
    conta = nova_conta(ramo[:industry])
    pipeline, etapas = montar_funil(conta, ramo)
    ramo[:evidencia].each { |caso| plantar_evidencia(conta, etapas, caso) }
    ramo[:prova].each_with_index { |caso, index| plantar_prova(conta, etapas, caso, index) }

    originais = ramo[:etapas].map { |(nome_etapa, frase)| { 'name' => nome_etapa, 'description' => frase } }
    melhoradas = melhorar(pipeline, etapas, originais)
    raio_x = com_custo { Crm::Ai::RaioXDasFrases.new(pipeline: pipeline, stages: melhoradas).perform }
    saida[:ramos][nome] = placar(raio_x).merge(raio_x: raio_x, frases: melhoradas)
    gravar_saida!
  end

  # "Quando usar" (#1920, item 4): funil de atendimento sem texto, com um cancelamento que uma pessoa trouxe da venda.
  def medir_quando_usar
    conta = nova_conta('Corretora de seguros')
    venda, etapas_venda = montar_funil(conta, FrasesComEvidenciaEval::RAMOS['corretora_de_seguros'])
    venda.update!(when_to_use: 'Quem quer contratar um seguro novo.')
    atendimento = conta.account.crm_pipelines.create!(name: 'Atendimento', created_by: conta.admin, status: :active, counts_as_sale: false)
    resolvendo = conta.account.crm_pipeline_stages.create!(pipeline: atendimento, name: 'Resolvendo', position: 0)
    card = card_com_conversa(conta, resolvendo, [[:cliente, 'Quero cancelar meu seguro residencial.']], 3.days.ago)
    mover_pela_pessoa(conta, card, etapas_venda[0], resolvendo, 2.days.ago)
    saida[:quando_usar] = com_custo { Crm::Ai::WhenToUseImprover.new(pipeline: atendimento, language: 'pt_BR').perform }
    gravar_saida!
  end

  it 'mede o acerto da IA de etapa com as frases originais e com as melhoradas pela evidência' do
    FrasesComEvidenciaEval::RAMOS.each { |nome, ramo| medir_ramo(nome, ramo) }
    medir_quando_usar

    expect(saida[:ramos].keys).to eq(FrasesComEvidenciaEval::RAMOS.keys)
    expect(saida[:custo_usd]).to be <= FrasesComEvidenciaEval::TETO_USD
  end
end
# rubocop:enable RSpec/DescribeClass
