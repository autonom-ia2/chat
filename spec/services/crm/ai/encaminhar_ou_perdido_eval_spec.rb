require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. A rodada para ao passar de TETO_USD, somado pelo evento de custo da IA do
# CRM (Crm::Ai::UsageRecorder::EVENT_NAME). Teto da Issue: US$ 3 somando todas as rodadas (#2396).
#
# #2396: a IA de etapa REAL (Crm::Ai::Evaluator, gatilho de mensagem, movimento automático ligado, com as flags do "não é
# negócio" e do "fechar o card") avalia cards de cinco tipos, cada um REPETICOES vezes, num card novo:
# - lixo: ninguém pede nada à empresa (fornecedor vendendo, engano de número, golpe, robô). Esperado: arquivado.
# - funil_estreito: a pessoa quer algo DA EMPRESA que não é o que este funil atende (conhecer a empresa, testar o
#   serviço, outro produto, contato de um evento). Esperado: o card fica aberto para uma pessoa encaminhar; nada de
#   arquivar nem de sugerir perdido.
# - desistiu e clicou_engano: o lead desistiu do pedido ou disse que chegou sem querer. Esperado: sugestão de perdido
#   (Crm::Ai::FecharCard), nunca arquivado como "não é negócio" (não distorce o relatório de anúncios).
# - negocio (controle): pedido normal. Esperado: aberto, sem arquivar nem sugerir perdido.
# Funis e conversas inventados, sem ramo fixo no prompt; nenhum prompt é gravado. Saída em EVAL_SAIDA (JSON).
module EncaminharOuPerdidoEval
  TETO_USD = 0.6

  ETAPAS = [
    ['Novo', 'Primeiro contato, ainda sem pedido claro.'],
    ['Em atendimento', 'O cliente disse o que quer e estamos entendendo o pedido.'],
    ['Proposta enviada', 'Já mandamos orçamento, proposta ou cotação.'],
    ['Ganho', 'O cliente fechou com a gente.'],
    ['Perdido', 'O cliente desistiu, recusou ou fechou com outro.']
  ].freeze

  ANUNCIO = 'Olá! Tenho interesse e queria mais informações, por favor.'.freeze

  # Mensagem: [quem, texto, horas atrás]. quem: :cliente ou :nos. quando_usar: o "quando usar" do funil (estreito).
  LIXO = [
    { nome: 'fornecedor_vende', funil: 'Venda de cursos de idiomas', mensagens: [
      [:cliente, 'Bom dia! Sou da Rota Digital, fazemos gestão de redes sociais para escolas. Posso mandar nossa proposta ' \
                 'de pacote mensal para vocês?', 20]
    ] },
    { nome: 'engano_de_numero', funil: 'Venda de móveis planejados', mensagens: [
      [:cliente, 'Mãe, chego às 7, deixa a janta no forno', 30],
      [:nos, 'Olá! Aqui é a loja de móveis. Acho que a mensagem veio para o número errado.', 29],
      [:cliente, 'Ih, foi engano, desculpa!', 29]
    ] },
    { nome: 'golpe_de_premio', funil: 'Venda de planos odontológicos', mensagens: [
      [:cliente, 'Parabéns! Você foi sorteado e ganhou R$ 3.000. Para resgatar, confirme seus dados em http://resgate.example', 15]
    ] },
    { nome: 'robo_com_robo', funil: 'Venda de seguros', mensagens: [
      [:nos, 'Olá! Sou a assistente virtual. Como posso ajudar?', 40],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Retornaremos em breve.', 40],
      [:nos, 'Olá! Sou a assistente virtual. Como posso ajudar?', 39],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Retornaremos em breve.', 39]
    ] },
    { nome: 'oferece_parceria', funil: 'Venda de pacotes de viagem', mensagens: [
      [:cliente, 'Oi! Tenho uma empresa de cobrança e quero oferecer nossos serviços para recuperar inadimplentes de vocês.', 26]
    ] }
  ].map { |caso| caso.merge(categoria: :lixo) }.freeze

  FUNIL_ESTREITO = [
    { nome: 'evento_conhecer_empresa', funil: 'Assinatura do plano anual',
      quando_usar: 'Clientes que querem assinar o plano anual do nosso sistema de agenda online.', mensagens: [
        [:cliente, 'Oi! Passei no estande de vocês na feira de ontem e peguei o cartão. Queria conhecer melhor a empresa ' \
                   'e entender o que vocês fazem.', 20]
      ] },
    { nome: 'quer_testar_servico', funil: 'Renovação de contrato',
      quando_usar: 'Clientes atuais renovando o contrato que já têm conosco.', mensagens: [
        [:cliente, 'Ainda não sou cliente. Dá para testar o serviço uns dias antes de contratar?', 10],
        [:nos, 'Olá! Este canal é para renovação de contrato.', 10],
        [:cliente, 'Entendi, mas eu queria experimentar. Com quem eu falo?', 9]
      ] },
    { nome: 'outro_produto_da_empresa', funil: 'Aluguel de brinquedos para festas',
      quando_usar: 'Pedidos de aluguel de brinquedos infláveis e camas elásticas.', mensagens: [
        [:cliente, 'Boa tarde! Vocês também fazem decoração de festa? Queria um orçamento de decoração para um aniversário.', 8]
      ] },
    { nome: 'visita_por_indicacao', funil: 'Matrícula em curso de inglês para adultos',
      quando_usar: 'Adultos que querem se matricular no curso de inglês.', mensagens: [
        [:cliente, 'Uma amiga me indicou vocês. Meu filho tem 9 anos, vocês têm alguma turma para criança? Posso ' \
                   'visitar a escola?', 12]
      ] },
    { nome: 'evento_demonstracao', funil: 'Suporte técnico',
      quando_usar: 'Clientes que já usam o sistema e precisam de ajuda com um problema.', kind: 'serve', mensagens: [
        [:cliente, 'Olá, conheci vocês na palestra do congresso. Não uso o sistema ainda, queria marcar uma demonstração ' \
                   'para a minha equipe.', 16]
      ] },
    { nome: 'empresa_quer_conhecer_solucoes', funil: 'Seguro de celular',
      quando_usar: 'Pessoas que querem contratar seguro para o próprio celular.', mensagens: [
        [:cliente, 'Bom dia, tenho uma empresa com 30 funcionários e queria conhecer as soluções que vocês têm para empresas.', 18]
      ] }
  ].map { |caso| caso.merge(categoria: :funil_estreito) }.freeze

  DESISTIU = [
    { nome: 'pensou_melhor', funil: 'Venda de móveis planejados', mensagens: [
      [:cliente, 'Quero orçamento de um guarda-roupa planejado', 50],
      [:nos, 'Claro! Segue o orçamento: R$ 6.800.', 48],
      [:cliente, 'Pensei melhor e não vou mais fazer o guarda-roupa. Obrigado mesmo assim.', 2]
    ] },
    { nome: 'sem_interesse_depois_do_anuncio', funil: 'Venda de planos de academia', mensagens: [
      [:cliente, ANUNCIO, 30],
      [:nos, 'Olá! Que bom! Qual plano te interessou, mensal ou anual?', 30],
      [:cliente, 'Na verdade desisti, não tenho mais interesse.', 6]
    ] },
    { nome: 'cancela_pedido_de_orcamento', funil: 'Venda de energia solar', mensagens: [
      [:cliente, 'Queria um orçamento de placas solares para minha casa', 70],
      [:nos, 'Perfeito! Qual o valor médio da sua conta de luz?', 69],
      [:cliente, 'Pode cancelar o pedido de orçamento, não quero mais.', 3]
    ] },
    { nome: 'resolveu_de_outro_jeito', funil: 'Venda de serviços de reforma', mensagens: [
      [:cliente, 'Preciso trocar o piso da sala, quanto fica?', 60],
      [:nos, 'Podemos agendar uma visita para medir. Qual o melhor dia?', 59],
      [:cliente, 'Não precisa mais, desisti da reforma.', 4]
    ] }
  ].map { |caso| caso.merge(categoria: :desistiu) }.freeze

  CLICOU_ENGANO = [
    { nome: 'cliquei_sem_querer', funil: 'Venda de planos de internet', mensagens: [
      [:cliente, ANUNCIO, 20],
      [:nos, 'Olá! Para qual endereço você quer a internet?', 20],
      [:cliente, 'Desculpa, cliquei no anúncio sem querer. Não tenho interesse.', 19]
    ] },
    { nome: 'apertou_o_botao_por_engano', funil: 'Venda de cursos online', mensagens: [
      [:cliente, ANUNCIO, 12],
      [:nos, 'Oi! Qual curso você quer conhecer?', 12],
      [:cliente, 'Foi engano, apertei o botão do anúncio sem querer.', 11]
    ] },
    { nome: 'nao_fiz_cadastro', funil: 'Venda de consórcio', mensagens: [
      [:nos, 'Olá, Carla! Recebemos seu cadastro no formulário do anúncio de consórcio. Posso te ajudar com a simulação?', 30],
      [:cliente, 'Acho que preenchi sem querer, não estou procurando consórcio não.', 28]
    ] },
    { nome: 'mandou_a_mensagem_do_anuncio_sem_querer', funil: 'Venda de imóveis', mensagens: [
      [:cliente, ANUNCIO, 25],
      [:nos, 'Olá! É para compra ou aluguel?', 25],
      [:cliente, 'Ops, mandei essa mensagem sem querer, não estou procurando imóvel.', 24]
    ] }
  ].map { |caso| caso.merge(categoria: :clicou_engano) }.freeze

  NEGOCIO = [
    { nome: 'pedido_vago', funil: 'Venda de tratamentos odontológicos', mensagens: [
      [:cliente, 'Quanto custa mais ou menos um clareamento?', 2]
    ] },
    { nome: 'oi_agora', funil: 'Venda de cursos de idiomas', mensagens: [[:cliente, 'oi', 0]] },
    { nome: 'pedido_claro', funil: 'Venda de seguros', mensagens: [
      [:cliente, 'Quero cotar o seguro do meu carro, um sedã 2021', 3],
      [:nos, 'Claro! Qual o CEP de pernoite?', 3],
      [:cliente, '01310-100', 2]
    ] },
    { nome: 'so_nos_prospeccao', funil: 'Venda de móveis planejados', mensagens: [
      [:nos, 'Olá, Paula! Vimos que você pediu informações sobre cozinha planejada no nosso site. Posso ajudar?', 60],
      [:nos, 'Paula, ainda tem interesse na cozinha? Temos condição especial este mês.', 30]
    ] },
    { nome: 'anuncio_sem_resposta', funil: 'Venda de imóveis', mensagens: [
      [:cliente, ANUNCIO, 30],
      [:nos, 'Olá! Claro. É para compra ou aluguel?', 30]
    ] },
    { nome: 'agora_nao_adiou', funil: 'Venda de energia solar', mensagens: [
      [:cliente, 'Quero orçamento de energia solar', 50],
      [:nos, 'Segue a proposta: R$ 18.000 instalado.', 48],
      [:cliente, 'Gostei, mas agora não dá. Me chama no ano que vem.', 3]
    ], esperado_fechar: true }
  ].map { |caso| caso.merge(categoria: :negocio) }.freeze

  CASOS = (LIXO + FUNIL_ESTREITO + DESISTIU + CLICOU_ENGANO + NEGOCIO).freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #2396: funil estreito encaminha, desistência vira sugestão de perdido' do
  let(:account) { create(:account, name: 'Conta Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Assistente') }
  let(:repeticoes) { ENV.fetch('EVAL_REPETICOES', '3').to_i }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    account.enable_features!(Crm::Ai::NaoENegocio::FLAG, Crm::Ai::FecharCard::FLAG)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
    allow_any_instance_of(Crm::Ai::ContextBuilder).to receive(:platform_bot_ids).and_return(Set[bot.id]) # rubocop:disable RSpec/AnyInstance
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-2396-encaminhar-ou-perdido.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > EncaminharOuPerdidoEval::TETO_USD

    resultado
  end

  def funil(caso)
    pipeline = account.crm_pipelines.create!(name: caso[:funil], created_by: admin, status: :active,
                                             when_to_use: caso[:quando_usar] || "Clientes de #{caso[:funil]}",
                                             metadata: { 'ai' => { 'auto_move_enabled' => true } })
    pipeline.update!(counts_as_sale: false) if caso[:kind] == 'serve'
    EncaminharOuPerdidoEval::ETAPAS.each_with_index do |(etapa, criterio), posicao|
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: etapa, position: posicao, metadata: { 'ai_criteria' => criterio },
                                          is_won_stage: etapa == 'Ganho', is_lost_stage: etapa == 'Perdido')
    end
    pipeline
  end

  def card(caso)
    pipeline = funil(caso)
    conversa, contato = conversa_com(caso[:mensagens])
    inicio = (caso[:mensagens].map { |mensagem| mensagem[2] }.max + 1).hours.ago
    account.crm_cards.create!(contact: contato, inbox: inbox, primary_conversation: conversa, created_at: inicio, pipeline: pipeline,
                              stage: pipeline.stages.order(:position).first, title: 'Contato Eval')
  end

  def conversa_com(mensagens)
    contato = create(:contact, account: account, name: 'Contato Eval')
    conversa = create(:conversation, account: account, inbox: inbox, contact: contato, status: :open)
    mensagens.each do |quem, texto, horas|
      cliente = quem == :cliente
      create(:message, account: account, inbox: inbox, conversation: conversa, message_type: cliente ? :incoming : :outgoing,
                       content: texto, sender: cliente ? contato : bot, created_at: horas.hours.ago)
    end
    [conversa, contato]
  end

  # O que o modelo devolveu nos dois campos de fim (nil quando não preencheu).
  def espiar_decisao!
    espiao = {}
    allow_any_instance_of(Crm::Ai::Evaluator).to receive(:aplicar).and_wrap_original do |original, classificacao, **opcoes| # rubocop:disable RSpec/AnyInstance
      espiao[:nao_e_negocio] = classificacao[:nao_e_negocio]
      espiao[:fechar_card] = classificacao[:fechar_card]
      original.call(classificacao, **opcoes)
    end
    espiao
  end

  def avaliar(caso, repeticao)
    alvo = card(caso)
    espiao = espiar_decisao!
    resultado = com_custo { Crm::Ai::Evaluator.new(card: alvo, trigger: 'message').perform }
    alvo.reload
    fechar = account.crm_ai_stage_suggestions.where(card: alvo, status: :pending).filter_map(&:fechar).first
    { nome: caso[:nome], categoria: caso[:categoria], repeticao: repeticao, status: resultado.status, erro: resultado.error,
      card_status: alvo.status, etapa: alvo.stage.name, sugestao_fechar: fechar, esperado_fechar: caso[:esperado_fechar],
      nao_e_negocio: espiao[:nao_e_negocio], fechar_card: espiao[:fechar_card] }.tap { |linha| saida[:casos] << linha }
  end

  def arquivado?(linha) = linha[:card_status] == 'archived'

  def perdido_sugerido?(linha) = linha[:sugestao_fechar].to_h['resultado'] == 'perdido'

  # Certo por categoria: lixo arquivado; desistência com sugestão de perdido e sem arquivar; o resto aberto, sem arquivar
  # nem sugerir perdido (o "agora não" do controle é o adiou: sugestão de perdido é o certo dele).
  def certo?(linha)
    case linha[:categoria]
    when :lixo then arquivado?(linha)
    when :desistiu, :clicou_engano then perdido_sugerido?(linha) && !arquivado?(linha)
    else !arquivado?(linha) && linha[:card_status] == 'open' && (linha[:esperado_fechar] ? perdido_sugerido?(linha) : !perdido_sugerido?(linha))
    end
  end

  def placar(linhas)
    linhas.group_by { |linha| linha[:categoria] }.transform_values { |grupo| placar_do_grupo(grupo) }
  end

  def placar_do_grupo(grupo)
    { total: grupo.size, certos: grupo.count { |linha| certo?(linha) }, arquivados: grupo.count { |linha| arquivado?(linha) },
      perdido_sugerido: grupo.count { |linha| perdido_sugerido?(linha) },
      os_dois_campos: grupo.count { |linha| linha[:nao_e_negocio].present? && linha[:fechar_card].present? } }
  end

  it 'lixo sai; funil estreito fica para encaminhar; desistência vira sugestão de perdido', :aggregate_failures do
    linhas = EncaminharOuPerdidoEval::CASOS.flat_map { |caso| (1..repeticoes).map { |repeticao| avaliar(caso, repeticao) } }
    saida[:placar] = placar(linhas)
    saida[:errados] = linhas.reject { |linha| certo?(linha) }.map { |linha| "#{linha[:nome]}:#{linha[:repeticao]}" }
    gravar_saida!

    expect(linhas.select { |linha| linha[:status] == :failed }).to be_empty
    expect(linhas.select { |linha| linha[:categoria] != :lixo && arquivado?(linha) }.pluck(:nome)).to be_empty
    expect(saida[:errados]).to be_empty
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
