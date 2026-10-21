require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 para a Issue #1920 somando todas as rodadas: a
# primeira gastou US$ 0,0186, então esta para ao passar de TETO_USD, somado pelo evento de custo da IA do CRM
# (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1920: quatro ramos inventados (três funis de venda e um de atendimento), cada um com frases fracas (fronteira mal
# definida). Em cada ramo:
# - casos em que a IA de etapa errou e uma pessoa corrigiu, em cards que ENSINAM: viram a evidência do "Melhorar com IA";
# - casos em que uma pessoa escolheu a etapa, em cards que PROVAM, com outras situações na mesma fronteira (não a mesma
#   frase com outras palavras): são a prova do raio-x. A separação é a do produto (Crm::Ai::EscolhaDePessoa).
# Três braços no mesmo raio-x: frases originais × melhoradas SEM evidência (só tipo, ramo e vizinhas) × melhoradas COM
# evidência, para saber quanto do ganho vem da evidência. EVAL_RODADAS rodadas (padrão 2).
# Saída (placar, frases, custo) em EVAL_SAIDA (JSON). Dados fictícios; nenhum prompt é gravado.
module FrasesComEvidenciaEval
  TETO_USD = 0.25
  RODADAS = (ENV['EVAL_RODADAS'].presence || 2).to_i
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
        { de: 2, certa: 1, falas: [[:cliente, 'Quanto custa a lente de contato dental?'],
                                   [:equipe, 'Depende da avaliação: posso te passar o valor depois que a doutora vir as fotos?']] },
        { de: 2, certa: 4, falas: [[:equipe, 'O tratamento de canal fica R$ 900.'],
                                   [:cliente, 'Obrigada, mas o convênio cobriu numa clínica perto de casa, não vou precisar.']] },
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
                                   [:equipe, 'Ainda estou esperando a seguradora liberar, amanhã cedo te passo.']] },
        { de: 2, certa: 4, falas: [[:equipe, 'Segue a cotação: R$ 1.800 à vista.'], [:cliente, 'Desisti, o financiamento já incluiu o seguro.']] },
        { de: 1, certa: 4, falas: [[:cliente, 'Não vou mais trocar de carro este ano, pode encerrar.']] },
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
        { de: 1, certa: 0, falas: [[:cliente, 'Vocês têm turma de francês para criança?'], [:equipe, 'Temos sim, a partir de 7 anos.']] },
        { de: 2, certa: 4, falas: [[:equipe, 'O pacote anual sai por R$ 320 mensais.'],
                                   [:cliente, 'Vou estudar pelo aplicativo mesmo, obrigada.']] },
        { de: 0, certa: 1, falas: [[:equipe, 'Agendei sua aula experimental para terça às 19h, ok?'],
                                   [:cliente, 'Ok, terça 19h confirmado.']] },
        { de: 2, certa: 3, falas: [[:cliente, 'Fiz o pagamento da matrícula agora.'], [:equipe, 'Recebido! Bem-vindo à escola.']] }
      ]
    },
    'assistencia_tecnica' => {
      industry: 'Assistência técnica de eletrodomésticos',
      atendimento: true,
      etapas: [
        ['Aberto', 'Cliente relatou um problema.'],
        ['Em diagnóstico', 'Técnico está vendo.'],
        ['Aguardando cliente', 'Esperando o cliente.'],
        ['Resolvido', 'Problema resolvido.'],
        ['Cancelado', 'Cliente cancelou.']
      ],
      evidencia: [
        { ia: 3, pessoa: 1, falas: [[:equipe, 'Vou testar a peça nova e te aviso.'], [:cliente, 'Ok, obrigado!']] },
        { ia: 2, pessoa: 1, falas: [[:cliente, 'A máquina continua fazendo barulho.'], [:equipe, 'Estamos analisando o motor.']] },
        { ia: 4, pessoa: 3, falas: [[:equipe, 'Trocamos a placa, está funcionando?'], [:cliente, 'Funcionou, já testei aqui, pode encerrar.']] }
      ],
      prova: [
        { de: 3, certa: 1, falas: [[:equipe, 'Vamos abrir o aparelho amanhã para verificar.'], [:cliente, 'Perfeito, valeu!']] },
        { de: 0, certa: 2, falas: [[:cliente, 'Minha geladeira parou de gelar.'],
                                   [:equipe, 'Preciso que você mande uma foto da etiqueta do aparelho.']] },
        { de: 4, certa: 3, falas: [[:equipe, 'Ajustamos a configuração remotamente.'], [:cliente, 'Agora deu certo, pode fechar o chamado.']] },
        { de: 1, certa: 4, falas: [[:cliente, 'Não quero mais o conserto, vou comprar outro aparelho.']] },
        { de: 2, certa: 1, falas: [[:cliente, 'Mandei a foto da etiqueta.'], [:equipe, 'Recebi, o técnico vai analisar.']] }
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
    @saida ||= { inicio: Time.current.iso8601, rodadas: [], custo_usd: 0.0 }
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
    pipeline = conta.account.crm_pipelines.create!(name: ramo[:atendimento] ? 'Atendimento' : 'Vendas', created_by: conta.admin,
                                                   status: :active, counts_as_sale: !ramo[:atendimento])
    etapas = ramo[:etapas].each_with_index.map do |(nome, frase), posicao|
      conta.account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: { 'ai_criteria' => frase })
    end
    [pipeline, etapas]
  end

  def card_com_conversa(conta, etapa, falas, quando, lado:)
    contact = create(:contact, account: conta.account)
    conversation = create_crm_conversation(account: conta.account, inbox: conta.inbox, contact: contact)
    falas.each_with_index do |(quem, texto), index|
      conversation.messages.create!(account_id: conta.account.id, inbox_id: conta.inbox.id, content: texto,
                                    created_at: quando + index.minutes,
                                    message_type: quem == :cliente ? :incoming : :outgoing, sender: quem == :cliente ? contact : conta.admin)
    end
    create_crm_card_do_lado(account: conta.account, lado: lado, pipeline: etapa.pipeline, stage: etapa, title: 'Pedido',
                            conversation_id: conversation.id)
  end

  def mover_pela_pessoa(conta, card, origem, destino, quando)
    Crm::Activity.create!(account: conta.account, card: card, actor_type: 'user', actor_id: conta.admin.id, event_type: 'move',
                          created_at: quando,
                          payload: { from_pipeline_id: origem.pipeline_id, to_pipeline_id: destino.pipeline_id,
                                     from_stage_id: origem.id, to_stage_id: destino.id })
  end

  # A IA errou: moveu sozinha (sugestão aplicada) e uma pessoa corrigiu uma hora depois, sem mensagem nova no meio.
  def plantar_evidencia(conta, etapas, caso)
    quando = 40.days.ago
    card = card_com_conversa(conta, etapas[caso[:pessoa]], caso[:falas], quando, lado: :ensina)
    conta.account.crm_ai_stage_suggestions.create!(card: card, from_stage: etapas[0], to_stage: etapas[caso[:ia]], confidence: 0.8,
                                                   model_used: 'gpt-6-luna', status: :auto_applied, reasoning: 'Decisão anterior da IA.',
                                                   created_at: quando + 10.minutes, updated_at: quando + 10.minutes)
    mover_pela_pessoa(conta, card, etapas[caso[:ia]], etapas[caso[:pessoa]], quando + 70.minutes)
  end

  # Uma pessoa escolheu a etapa há poucos dias: é a prova do raio-x.
  def plantar_prova(conta, etapas, caso, index)
    quando = (5.days + index.hours).ago
    card = card_com_conversa(conta, etapas[caso[:certa]], caso[:falas], quando, lado: :prova)
    mover_pela_pessoa(conta, card, etapas[caso[:de]], etapas[caso[:certa]], quando + 30.minutes)
  end

  # O "Melhorar com IA" em cada etapa que tem evidência, uma de cada vez, sempre com as frases da tela até ali. Sem
  # evidência: o mesmo pedido, nas mesmas etapas, com nenhum card visível (o improver só vê tipo, ramo e vizinhas).
  def melhorar(pipeline, etapas, telas, com_evidencia:)
    cards = com_evidencia ? nil : Crm::Card.none
    etapas.each_with_index do |etapa, index|
      next if Crm::Ai::EvidenciaDaEtapa.new(stage: etapa).casos.empty?

      resposta = com_custo do
        Crm::Ai::StageCriteriaImprover.new(pipeline: pipeline, stages: telas, stage_index: index, language: 'pt_BR', cards: cards).perform
      end
      telas = telas.each_with_index.map { |tela, posicao| posicao == index ? tela.merge('description' => resposta['description']) : tela }
    end
    telas
  end

  def raio_x(pipeline, telas)
    resultado = com_custo { Crm::Ai::RaioXDasFrases.new(pipeline: pipeline, stages: telas).perform }
    raise "raio-x sem resultado: #{resultado[:error]}" if resultado[:error]

    resultado
  end

  def montar_ramo(ramo)
    conta = nova_conta(ramo[:industry])
    pipeline, etapas = montar_funil(conta, ramo)
    ramo[:evidencia].each { |caso| plantar_evidencia(conta, etapas, caso) }
    ramo[:prova].each_with_index { |caso, index| plantar_prova(conta, etapas, caso, index) }
    [pipeline, etapas]
  end

  def medir_ramo(nome, ramo, rodada)
    pipeline, etapas = montar_ramo(ramo)
    originais = etapas.zip(ramo[:etapas]).map { |etapa, (nome_etapa, frase)| { 'id' => etapa.id, 'name' => nome_etapa, 'description' => frase } }
    sem = melhorar(pipeline, etapas, originais, com_evidencia: false)
    com = melhorar(pipeline, etapas, originais, com_evidencia: true)
    raio_sem = raio_x(pipeline, sem)
    raio_com = raio_x(pipeline, com)
    rodada[nome] = { total: raio_com[:total], originais: raio_com[:acertos_atual], sem_evidencia: raio_sem[:acertos_nova],
                     com_evidencia: raio_com[:acertos_nova], casos_com: raio_com[:casos], frases_sem: sem, frases_com: com }
    gravar_saida!
  end

  # "Quando usar" (#1920, item 4): funil de atendimento sem texto, com um cancelamento que uma pessoa trouxe da venda.
  def medir_quando_usar
    conta = nova_conta('Corretora de seguros')
    venda, etapas_venda = montar_funil(conta, FrasesComEvidenciaEval::RAMOS['corretora_de_seguros'])
    venda.update!(when_to_use: 'Quem quer contratar um seguro novo.')
    atendimento = conta.account.crm_pipelines.create!(name: 'Atendimento', created_by: conta.admin, status: :active, counts_as_sale: false)
    resolvendo = conta.account.crm_pipeline_stages.create!(pipeline: atendimento, name: 'Resolvendo', position: 0)
    card = card_com_conversa(conta, resolvendo, [[:cliente, 'Quero cancelar meu seguro residencial.']], 3.days.ago, lado: :ensina)
    mover_pela_pessoa(conta, card, etapas_venda[0], resolvendo, 2.days.ago)
    saida[:quando_usar] = com_custo { Crm::Ai::WhenToUseImprover.new(pipeline: atendimento, language: 'pt_BR').perform }
    gravar_saida!
  end

  def soma(braco) = saida[:rodadas].sum { |rodada| rodada.values.sum { |ramo| ramo[braco] } }

  it 'mede o acerto da IA de etapa com as frases originais, as melhoradas sem evidência e as melhoradas com evidência' do
    FrasesComEvidenciaEval::RODADAS.times do
      saida[:rodadas] << {}
      FrasesComEvidenciaEval::RAMOS.each { |nome, ramo| medir_ramo(nome, ramo, saida[:rodadas].last) }
    end
    medir_quando_usar
    saida[:placar] = { originais: soma(:originais), sem_evidencia: soma(:sem_evidencia), com_evidencia: soma(:com_evidencia),
                       total: soma(:total) }
    gravar_saida!

    # Todo caso de prova avaliado (nenhum raio-x parou no teto), e a evidência não piora o que as frases originais já acertavam.
    saida[:rodadas].each do |rodada|
      FrasesComEvidenciaEval::RAMOS.each { |nome, ramo| expect(rodada.fetch(nome)[:total]).to eq(ramo[:prova].size) }
    end
    expect(saida[:placar][:com_evidencia]).to be >= saida[:placar][:originais]
    expect(saida[:custo_usd]).to be <= FrasesComEvidenciaEval::TETO_USD
  end
end
# rubocop:enable RSpec/DescribeClass
