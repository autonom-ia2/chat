require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1922, somando todas as rodadas da Issue): a rodada
# para ao passar de TETO_USD, somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1922: a IA de etapa REAL (Crm::Ai::Evaluator, gatilho de mensagem, movimento automático ligado) avalia cards de lixo
# e cards de negócio de vários ramos fictícios. Cada caso roda REPETICOES vezes (variância do modelo), num card novo.
# Dois conjuntos: "ajuste" (os casos usados para escrever a regra) e "validacao" (casos difíceis escritos depois, nunca
# usados para ajustar o prompt). Critérios (hard):
# - nenhuma avaliação falha;
# - nenhum card de negócio ou de perda é arquivado (falso positivo zero, nos dois conjuntos);
# - nenhum card de negócio vai para a etapa de perda, e a perda declarada vai para ela;
# - todo card repetido sai, apontando o card que fica;
# - pelo menos MINIMO_LIXO dos cards de lixo saem.
# As saídas vão para EVAL_SAIDA (JSON). Conversas inventadas; nenhum prompt é gravado.
module NaoENegocioEval
  TETO_USD = 0.12
  MINIMO_LIXO = 0.8

  ETAPAS = [
    ['Novo', 'Primeiro contato, ainda sem pedido claro.'],
    ['Em atendimento', 'O cliente disse o que quer e estamos entendendo o pedido.'],
    ['Proposta enviada', 'Já mandamos orçamento, proposta ou cotação.'],
    ['Ganho', 'O cliente fechou com a gente.'],
    ['Perdido', 'O cliente desistiu, recusou ou fechou com outro.']
  ].freeze

  # Mensagem: [quem, texto, horas atrás] ou [quem, texto, horas atrás, mídia]. quem: :cliente ou :nos.
  # Caso: { nome:, ramo:, esperado: (:lixo, :negocio ou :perda), conjunto: (:ajuste ou :validacao), mensagens:,
  #         irmao: { titulo:, outro_funil:, status: } (card mais antigo na mesma conversa), titulo: }
  AJUSTE = [
    { nome: 'fornecedor_oferece_leads', ramo: 'Corretora de seguros', esperado: :lixo, mensagens: [
      [:cliente, 'Bom dia! Sou da LeadMax, geramos leads qualificados de seguro auto para corretoras. ' \
                 'Posso apresentar nosso pacote com 200 leads por mês?', 30],
      [:nos, 'Olá! Como posso ajudar?', 30]
    ] },
    { nome: 'engano_pessoa_errada', ramo: 'Clínica odontológica', esperado: :lixo, mensagens: [
      [:cliente, 'Amor, passa no mercado e compra pão e leite', 50],
      [:nos, 'Olá! Aqui é a clínica. Acho que a mensagem veio para o número errado.', 49],
      [:cliente, 'Nossa, desculpa, foi engano!', 49]
    ] },
    { nome: 'robo_com_robo', ramo: 'Corretora de seguros', esperado: :lixo, mensagens: [
      [:nos, 'Olá! Sou a assistente virtual da corretora. Como posso ajudar?', 40],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Nosso horário de atendimento é de segunda a sexta, ' \
                 'das 8h às 18h. Retornaremos em breve.', 40],
      [:nos, 'Olá! Sou a assistente virtual da corretora. Como posso ajudar?', 39],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Nosso horário de atendimento é de segunda a sexta, ' \
                 'das 8h às 18h. Retornaremos em breve.', 39]
    ] },
    { nome: 'parceiro_divulgacao', ramo: 'Escola de idiomas', esperado: :lixo, mensagens: [
      [:cliente, 'Oi! Tenho um perfil de viagens com 80 mil seguidores e quero propor uma parceria: divulgo a escola ' \
                 'em troca de um curso. Vocês topam?', 26]
    ] },
    { nome: 'card_repetido', ramo: 'Loja de móveis planejados', esperado: :lixo, titulo: 'Cozinha planejada',
      irmao: { titulo: 'Orçamento de cozinha planejada' }, mensagens: [
        [:cliente, 'Quero um orçamento de cozinha planejada para um apartamento de 9 m²', 3],
        [:nos, 'Claro! Vou separar as opções.', 3],
        [:cliente, 'Ok, aguardo o orçamento da cozinha', 2]
      ] },
    { nome: 'fechou_com_outra', ramo: 'Corretora de seguros', esperado: :perda, mensagens: [
      [:cliente, 'Quero cotar o seguro do meu carro, um Onix 2022', 30],
      [:nos, 'Perfeito, já mando a cotação.', 29],
      [:nos, 'Segue a cotação: R$ 2.400 por ano.', 28],
      [:cliente, 'Obrigado, mas já fechei com outra corretora.', 1]
    ] },
    { nome: 'pedido_vago', ramo: 'Clínica odontológica', esperado: :negocio, mensagens: [
      [:cliente, 'Quanto custa mais ou menos um clareamento?', 2]
    ] },
    { nome: 'so_nos_prospeccao', ramo: 'Loja de móveis planejados', esperado: :negocio, mensagens: [
      [:nos, 'Olá, Paula! Vimos que você pediu informações sobre guarda-roupa planejado no nosso site. Posso ajudar?', 60],
      [:nos, 'Paula, ainda tem interesse no guarda-roupa? Temos condição especial este mês.', 30]
    ] },
    { nome: 'oi_agora', ramo: 'Escola de idiomas', esperado: :negocio, mensagens: [[:cliente, 'oi', 0]] },
    { nome: 'dois_pedidos_diferentes', ramo: 'Corretora de seguros', esperado: :negocio, titulo: 'Seguro residencial',
      irmao: { titulo: 'Seguro do HB20' }, mensagens: [
        [:cliente, 'Quero cotar o seguro do carro', 5],
        [:nos, 'Claro! Qual o modelo?', 5],
        [:cliente, 'É um HB20 2021. E também quero cotar o seguro da minha casa, é outro pedido', 4]
      ] },
    { nome: 'fora_do_perfil', ramo: 'Clínica odontológica', esperado: :negocio, mensagens: [
      [:cliente, 'Vocês fazem harmonização facial? Queria saber o preço', 6]
    ] },
    { nome: 'link_com_pedido', ramo: 'Loja de móveis planejados', esperado: :negocio, mensagens: [
      [:cliente, 'https://pin.it/abc123', 20],
      [:cliente, 'Quero um painel de TV igual a esse, vocês fazem?', 20]
    ] },
    { nome: 'so_um_link_parado', ramo: 'Loja de móveis planejados', esperado: :negocio, mensagens: [
      [:cliente, 'https://bit.ly/3xYz9Qa', 72],
      [:nos, 'Olá! Recebemos seu link, em que podemos ajudar?', 71]
    ] },
    { nome: 'caractere_solto_parado', ramo: 'Clínica odontológica', esperado: :negocio, mensagens: [
      [:cliente, '.', 80],
      [:nos, 'Olá! Tudo bem? Como podemos ajudar?', 79]
    ] }
  ].map { |caso| caso.merge(conjunto: :ajuste) }.freeze

  VALIDACAO = [
    { nome: 'link_de_anuncio_sem_resposta', ramo: 'Imobiliária', esperado: :negocio, mensagens: [
      [:cliente, 'https://fb.me/2kX9aQ', 40],
      [:nos, 'Olá! Vimos que você chegou pelo nosso anúncio. Qual imóvel te interessou?', 40]
    ] },
    { nome: 'texto_de_anuncio_sem_resposta', ramo: 'Imobiliária', esperado: :negocio, mensagens: [
      [:cliente, 'Olá! Tenho interesse e queria mais informações, por favor.', 30],
      [:nos, 'Olá! Claro. É para compra ou aluguel?', 30]
    ] },
    { nome: 'foto_sozinha', ramo: 'Oficina mecânica', esperado: :negocio, mensagens: [
      [:cliente, nil, 26, :image],
      [:nos, 'Olá! Recebemos a foto. Como podemos ajudar?', 26]
    ] },
    { nome: 'audio_sozinho', ramo: 'Pet shop', esperado: :negocio, mensagens: [
      [:cliente, nil, 28, :audio],
      [:nos, 'Olá! Não conseguimos ouvir o áudio, pode escrever o que precisa?', 27]
    ] },
    { nome: 'pos_venda_suporte', ramo: 'Suporte de provedor de internet', esperado: :negocio, mensagens: [
      [:cliente, 'Minha internet está caindo toda noite desde ontem, o que eu faço?', 3]
    ] },
    { nome: 'cliente_com_card_ganho', ramo: 'Loja de móveis planejados', esperado: :negocio,
      irmao: { titulo: 'Sofá retrátil', status: :won }, mensagens: [
        [:cliente, 'Oi, comprei o sofá com vocês mês passado e queria saber o prazo da garantia', 4]
      ] },
    { nome: 'parecidos_em_funis_diferentes', ramo: 'Corretora de seguros', esperado: :negocio, titulo: 'Seguro auto',
      irmao: { titulo: 'Seguro auto', outro_funil: 'Renovações' }, mensagens: [
        [:cliente, 'Quero renovar o seguro do meu carro, que vence mês que vem', 6],
        [:nos, 'Claro, já vejo a renovação.', 6],
        [:cliente, 'E também quero cotar um seguro novo para o carro da minha filha, um Kwid 2023', 5]
      ] },
    { nome: 'newsletter_de_marketing', ramo: 'Escola de idiomas', esperado: :lixo, mensagens: [
      [:cliente, 'Newsletter EdTech Hoje, edição de outubro: 5 tendências de ensino híbrido para escolas. ' \
                 'Leia em https://edtechhoje.example/out. Para não receber mais, responda SAIR.', 20]
    ] },
    { nome: 'golpe_de_premio', ramo: 'Clínica odontológica', esperado: :lixo, mensagens: [
      [:cliente, 'Parabéns! Seu número foi sorteado e você ganhou um prêmio de R$ 5.000. Para resgatar, ' \
                 'confirme seus dados em http://premio-agora.example', 15]
    ] },
    { nome: 'repetido_pet_shop', ramo: 'Pet shop', esperado: :lixo, titulo: 'Banho e tosa',
      irmao: { titulo: 'Banho e tosa do Thor' }, mensagens: [
        [:cliente, 'Quero agendar banho e tosa para o Thor no sábado', 4],
        [:nos, 'Claro! Temos horário às 10h.', 4],
        [:cliente, 'Pode ser às 10h para o banho e tosa do Thor', 3]
      ] }
  ].map { |caso| caso.merge(conjunto: :validacao) }.freeze

  CASOS = (AJUSTE + VALIDACAO).freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1922: o card que não é negócio sai do funil sem contar como perda' do
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
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
    # O nosso robô aparece como agente da plataforma (platform_agent), como um agente da Autonom.ia ligado à caixa.
    allow_any_instance_of(Crm::Ai::ContextBuilder).to receive(:platform_bot_ids).and_return(Set[bot.id]) # rubocop:disable RSpec/AnyInstance
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1922-nao-e-negocio.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > NaoENegocioEval::TETO_USD

    resultado
  end

  def funil(nome)
    pipeline = account.crm_pipelines.create!(name: nome, created_by: admin, status: :active, when_to_use: "Clientes de #{nome}",
                                             metadata: { 'ai' => { 'auto_move_enabled' => true } })
    NaoENegocioEval::ETAPAS.each_with_index do |(etapa, criterio), posicao|
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: etapa, position: posicao, metadata: { 'ai_criteria' => criterio })
    end
    pipeline
  end

  def conversa_com(mensagens)
    contato = create(:contact, account: account, name: 'Contato Eval')
    conversa = create(:conversation, account: account, inbox: inbox, contact: contato, status: :open)
    mensagens.each do |quem, texto, horas, midia|
      cliente = quem == :cliente
      mensagem = build(:message, account: account, inbox: inbox, conversation: conversa, message_type: cliente ? :incoming : :outgoing,
                                 content: texto, sender: cliente ? contato : bot, created_at: horas.hours.ago)
      anexar(mensagem, midia) if midia
      mensagem.save!
    end
    [conversa, contato]
  end

  def anexar(mensagem, tipo)
    arquivo = tipo == :image ? 'avatar.png' : 'sample.mp3'
    mensagem.attachments.new(account_id: account.id, file_type: tipo,
                             file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', arquivo)))
  end

  # O card avaliado e, quando o caso pede, o card irmão (mais antigo) na mesma conversa.
  def card(caso)
    pipeline = funil(caso[:ramo])
    conversa, contato = conversa_com(caso[:mensagens])
    inicio = (caso[:mensagens].map { |mensagem| mensagem[2] }.max + 1).hours.ago
    atributos = { contact: contato, inbox: inbox, primary_conversation: conversa, created_at: inicio }
    irmao = criar_irmao(caso[:irmao], pipeline, atributos) if caso[:irmao]
    alvo = account.crm_cards.create!(atributos.merge(pipeline: pipeline, stage: pipeline.stages.order(:position).first,
                                                     title: caso[:titulo] || 'Contato Eval'))
    [alvo, irmao]
  end

  def criar_irmao(irmao, pipeline, atributos)
    pipeline = funil(irmao[:outro_funil]) if irmao[:outro_funil]
    card = account.crm_cards.create!(atributos.merge(pipeline: pipeline, stage: pipeline.stages.order(:position).first, title: irmao[:titulo]))
    card.update!(status: irmao[:status], closed_at: 10.days.ago) if irmao[:status]
    card
  end

  # A decisão "não é negócio" que o modelo devolveu (nil quando ele não preencheu).
  def espiar_decisao!
    espiao = {}
    allow(Crm::Ai::NaoENegocio).to receive(:new).and_wrap_original do |original, **args|
      espiao[:decisao] = args[:decisao]
      original.call(**args)
    end
    espiao
  end

  def avaliar(caso, repeticao)
    alvo, irmao = card(caso)
    espiao = espiar_decisao!
    resultado = com_custo { Crm::Ai::Evaluator.new(card: alvo, trigger: 'message').perform }
    alvo.reload
    { nome: caso[:nome], ramo: caso[:ramo], conjunto: caso[:conjunto], esperado: caso[:esperado], repeticao: repeticao,
      status: resultado.status, erro: resultado.error, card_status: alvo.status, etapa: alvo.stage.name,
      irmao_id: irmao&.id, nao_e_negocio: espiao[:decisao] }.tap { |linha| saida[:casos] << linha }
  end

  def rodar
    NaoENegocioEval::CASOS.flat_map { |caso| (1..repeticoes).map { |repeticao| avaliar(caso, repeticao) } }
  end

  def arquivado?(linha) = linha[:card_status] == 'archived'

  def duplicado_de(linha) = linha[:nao_e_negocio].to_h.with_indifferent_access[:duplicado_de]

  def placar(linhas)
    linhas.group_by { |linha| [linha[:conjunto], linha[:esperado]] }.to_h do |(conjunto, esperado), grupo|
      ["#{conjunto}/#{esperado}", { total: grupo.size, arquivados: grupo.count { |linha| arquivado?(linha) },
                                    no_perdido: grupo.count { |linha| linha[:etapa] == 'Perdido' },
                                    modelo_disse_nao_e_negocio: grupo.count { |linha| linha[:nao_e_negocio].present? } }]
    end
  end

  it 'lixo sai do funil, negócio fica intacto, perda vai para a etapa de perda, repetido aponta o que fica', :aggregate_failures do
    linhas = rodar
    saida[:placar] = placar(linhas)
    gravar_saida!

    lixo = linhas.select { |linha| linha[:esperado] == :lixo }
    repetidos = lixo.select { |linha| linha[:irmao_id] }
    expect(linhas.select { |linha| linha[:status] == :failed }).to be_empty
    expect(linhas.select { |linha| linha[:esperado] != :lixo && arquivado?(linha) }).to be_empty
    expect(linhas.select { |linha| linha[:esperado] == :negocio && linha[:etapa] == 'Perdido' }).to be_empty
    expect(linhas.select { |linha| linha[:esperado] == :perda }.pluck(:etapa).uniq).to eq(['Perdido'])
    expect(repetidos.reject { |linha| arquivado?(linha) && duplicado_de(linha) == linha[:irmao_id] }).to be_empty
    expect(lixo.count { |linha| arquivado?(linha) }).to be >= (lixo.size * NaoENegocioEval::MINIMO_LIXO).ceil
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
