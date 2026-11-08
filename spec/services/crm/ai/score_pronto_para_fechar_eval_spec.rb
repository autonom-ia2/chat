require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1962): a rodada para ao passar de US$ 0,27,
# somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1962, item 3: "pronto para fechar, falta só um dado" é decisão do modelo, com saída "não se aplica". Três ramos
# (seguro viagem, clínica odontológica, software B2B), cada um com os três desfechos: falta dado NOSSO, falta dado
# DO CLIENTE e não se aplica (ainda escolhendo). Mais um caso por ramo com pergunta do cliente sem resposta, para a
# leitura de "pede resposta nossa" (awaiting_our_reply): o banco diz quem falou por último; se a fala pede resposta,
# é o modelo. Dois controles do item 4 (número errado e newsletter) conferem a saída negativo_explicito do blocker.
# Além da leitura, confere a nota final: a faixa certa é o que importa para quem atende. Avaliação real do card
# (Evaluator → StageClassifier → ScoreApplier); o que o modelo leu sai dos sinais gravados. Dados fictícios; nenhum
# prompt é gravado.
module ProntoParaFecharEval
  TETO_USD = 0.27

  RAMOS = {
    'seguro_viagem' => {
      'falta_dado_nosso' => [
        [:cliente, 'Oi! Quero o seguro viagem para Portugal, de 12/11 a 26/11, para duas pessoas.'],
        [:equipe, 'Para duas pessoas, o plano Europa 60 mil euros fica R$ 412 no total. Posso seguir com a emissão?'],
        [:cliente, 'Pode sim, fechado! Me manda o link de pagamento que eu pago agora.'],
        [:equipe, 'Perfeito! Vou gerar o link aqui e já te envio.']
      ],
      'falta_dado_do_cliente' => [
        [:cliente, 'Oi! Quero o seguro viagem para Portugal, de 12/11 a 26/11, para duas pessoas.'],
        [:equipe, 'Para duas pessoas, o plano Europa 60 mil euros fica R$ 412 no total. Posso seguir com a emissão?'],
        [:cliente, 'Fechado, quero esse plano.'],
        [:equipe, 'Ótimo! Para emitir, preciso do CPF e da data de nascimento dos dois viajantes.']
      ],
      'nao_se_aplica' => [
        [:cliente, 'Oi, quanto custa um seguro viagem para a Europa em novembro?'],
        [:equipe, 'Temos três opções: Básico R$ 290, Europa 60 mil R$ 412 e Premium R$ 590, para duas pessoas.'],
        [:cliente, 'Obrigado. Vou comparar com outra corretora e depois te falo.']
      ],
      'pergunta_pendente' => [
        [:cliente, 'Oi, quanto custa um seguro viagem para a Europa em novembro, para duas pessoas?'],
        [:equipe, 'Temos três opções: Básico R$ 290, Europa 60 mil R$ 412 e Premium R$ 590, para duas pessoas.'],
        [:cliente, 'Qual a diferença de cobertura médica entre o Básico e o Europa 60 mil?']
      ]
    },
    'clinica_odontologica' => {
      'falta_dado_nosso' => [
        [:cliente, 'Bom dia, recebi o orçamento do clareamento. R$ 900 em 3x está ótimo, quero fazer.'],
        [:equipe, 'Que bom! Qual o melhor período para você?'],
        [:cliente, 'Quinta de manhã. Pode marcar.'],
        [:equipe, 'Combinado! Vou confirmar o horário com a doutora e te retorno.']
      ],
      'falta_dado_do_cliente' => [
        [:cliente, 'Bom dia, recebi o orçamento do clareamento. R$ 900 em 3x está ótimo, quero fazer.'],
        [:equipe, 'Que bom! Tenho quinta às 9h com a doutora. Para reservar, preciso do seu nome completo e CPF.']
      ],
      'nao_se_aplica' => [
        [:cliente, 'Vocês atendem pelo convênio OdontoMais?'],
        [:equipe, 'No momento não atendemos esse convênio, só particular. A avaliação inicial é R$ 120.'],
        [:cliente, 'Ah, entendi. Vou ver o que faço.']
      ],
      'pergunta_pendente' => [
        [:cliente, 'Boa tarde! Vocês fazem clareamento a laser? Quanto custa e em quantas sessões?']
      ]
    },
    'software_b2b' => {
      'falta_dado_nosso' => [
        [:cliente, 'Olá, conversei com os sócios e aprovamos o plano Pro anual do sistema para as nossas 3 academias.'],
        [:cliente, 'Pode mandar o contrato para assinatura.'],
        [:equipe, 'Excelente notícia! Vou preparar o contrato e envio ainda hoje.']
      ],
      'falta_dado_do_cliente' => [
        [:cliente, 'Olá, conversei com os sócios e vamos de plano Pro anual para as nossas 3 academias.'],
        [:equipe, 'Excelente! Para emitir o contrato, me envia o CNPJ e o e-mail do responsável financeiro.']
      ],
      'nao_se_aplica' => [
        [:cliente, 'Oi, vi a demonstração do sistema de gestão. Gostei.'],
        [:equipe, 'Que bom! Ficou alguma dúvida sobre os planos?'],
        [:cliente, 'Estamos avaliando três ferramentas e vamos decidir só no mês que vem.']
      ],
      'pergunta_pendente' => [
        [:cliente, 'Oi, vi a demonstração do sistema de gestão. Gostei.'],
        [:equipe, 'Que bom! Ficou alguma dúvida sobre os planos?'],
        [:cliente, 'Sim: o plano Pro integra com o nosso ERP? E qual o prazo de implantação para 3 unidades?']
      ]
    }
  }.freeze

  # O que cada desfecho deve produzir: a leitura de pronto para fechar, se a última fala do cliente pede resposta
  # nossa e as faixas aceitas para a nota final. Onde nós falamos por último a leitura de awaiting_our_reply não muda
  # a nota (o banco já diz que ninguém espera) e não é conferida (nil).
  ESPERADO = {
    'falta_dado_nosso' => { ready_to_close: 'falta_dado_nosso', awaiting: nil, faixas: %w[urgente] },
    'falta_dado_do_cliente' => { ready_to_close: 'falta_dado_do_cliente', awaiting: nil, faixas: %w[quente urgente] },
    # Sem dívida nossa não há piso: nunca urgente. Entre frio e quente decidem os sinais-base (intenção, sinal de
    # compra), que este eval não calibra — "vou comparar" com preço na mesa já saiu 38 e 58 em rodadas diferentes.
    'nao_se_aplica' => { ready_to_close: 'nao_se_aplica', awaiting: false, faixas: %w[frio morno quente] },
    'pergunta_pendente' => { ready_to_close: 'nao_se_aplica', awaiting: true, faixas: %w[quente urgente] }
  }.freeze

  CONTROLES = {
    'numero_errado' => [
      [:equipe, 'Oi Carlos, tudo bem? Conseguiu ver a proposta do seguro que te enviei?'],
      [:cliente, 'Número errado. Não sou o Carlos e não conheço essa empresa.']
    ],
    'newsletter' => [
      [:cliente, 'Newsletter de outubro: confira as novidades do nosso blog e as promoções da semana. ' \
                 'Para deixar de receber estes e-mails, clique em descadastrar.']
    ]
  }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1962: pronto para fechar e sinal negativo explícito' do
  let(:account) { create(:account, name: 'Conta Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:funil) do
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: 'Vendas')
    create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta enviada', position: 1)
    create_crm_stage(account: account, pipeline: pipeline, name: 'Fechamento', position: 2)
    pipeline.update!(metadata: pipeline.metadata.to_h.deep_merge('ai' => { 'score_enabled' => true }))
    [pipeline, primeira]
  end

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
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1962-pronto-para-fechar.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > ProntoParaFecharEval::TETO_USD
  end

  # Uma conversa nova por caso, com as falas em ordem e um minuto entre elas.
  def conversa_com(contact, falas)
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
    falas.each_with_index do |(quem, texto), i|
      cliente = quem == :cliente
      create(:message, account: account, inbox: inbox, conversation: conversa, content: texto,
                       message_type: cliente ? :incoming : :outgoing, sender: cliente ? contact : admin,
                       created_at: (falas.size - i).minutes.ago)
    end
    conversa
  end

  # Avaliação real do card; devolve a nota com os sinais que o modelo gravou.
  def avaliar(nome, falas)
    pipeline, stage = funil
    contact = create(:contact, account: account, name: "Cliente #{nome}")
    conversa = conversa_com(contact, falas)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: nome,
                                     primary_conversation: conversa, inbox: inbox)
    com_custo { Crm::Ai::Evaluator.new(card: card, trigger: 'manual').perform }
    card.reload.metadata.to_h.dig('ai', 'score').to_h
  end

  # Confere leitura e nota final de um caso de cliente de verdade; devolve os erros.
  def conferir_caso(caso, desfecho, score)
    esperado = ProntoParaFecharEval::ESPERADO.fetch(desfecho)
    sinais = score['signals'].to_h
    saida[:casos] << { caso: caso, ready_to_close: sinais['ready_to_close'], awaiting_our_reply: sinais['awaiting_our_reply'],
                       blocker: sinais['blocker'], nota: score['value'], faixa: score['tier'] }
    erros = erros_de_leitura(caso, esperado, sinais)
    return erros if esperado[:faixas].include?(score['tier'])

    erros << "#{caso}: nota #{score['value']} (#{score['tier']}), esperado #{esperado[:faixas].join('/')}"
  end

  def erros_de_leitura(caso, esperado, sinais)
    [
      ("#{caso}: leu ready_to_close #{sinais['ready_to_close'].inspect}" unless sinais['ready_to_close'] == esperado[:ready_to_close]),
      (unless [nil, sinais['awaiting_our_reply']].include?(esperado[:awaiting])
         "#{caso}: leu awaiting_our_reply #{sinais['awaiting_our_reply'].inspect}"
       end),
      # O modo de falha caro do item 4: zerar na hora um cliente de verdade.
      ("#{caso}: negativo explícito num cliente de verdade" if sinais['blocker'] == 'negativo_explicito'),
      ("#{caso}: conversa legível lida como ilegível" if sinais['unreadable'] == true)
    ].compact
  end

  it 'lê pronto para fechar e pede resposta nos três ramos, e o negativo explícito nos controles' do
    erros = []
    ProntoParaFecharEval::RAMOS.each do |ramo, casos|
      casos.each { |desfecho, falas| erros.concat(conferir_caso("#{ramo}/#{desfecho}", desfecho, avaliar("#{ramo}/#{desfecho}", falas))) }
    end
    ProntoParaFecharEval::CONTROLES.each do |nome, falas|
      score = avaliar("controle/#{nome}", falas)
      lido = score.dig('signals', 'blocker')
      saida[:casos] << { caso: "controle/#{nome}", esperado: 'negativo_explicito', lido: lido, nota: score['value'] }
      erros << "controle/#{nome}: leu blocker #{lido.inspect}" unless lido == 'negativo_explicito'
      erros << "controle/#{nome}: nota #{score['value']}, esperado 0" unless score['value'].to_i.zero?
    end
    gravar_saida!

    expect(erros).to be_empty, erros.join("\n")
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
