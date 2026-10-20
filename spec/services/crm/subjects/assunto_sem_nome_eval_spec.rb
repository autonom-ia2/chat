require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto do #1918 (US$ 2 para os dois PRs): esta rodada para ao passar
# de US$ 0,50, somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1918 PR2: o porteiro (IA de assunto) com a flag `crm_avaliar_toda_mensagem`. Mede, em três ramos de negócio
# inventados (seguro, laboratório, viagem), se a última mensagem do cliente vai para o lugar certo:
#   - cortesia ("obrigada", "👍"): nenhum assunto, nada muda nos cards;
#   - mudança de situação do pedido aberto (desistiu, pagou, mandou o documento, aceitou, renovou): o card aberto é o
#     assunto da mensagem (mesmo assunto ou volta a ele), e nenhum card nasce nem ganha nome;
#   - pedido novo de outro assunto: nasce o card no funil esperado;
#   - continuação do pedido de um card ainda sem nome: o card aberto é o assunto, e nenhum card nasce;
#   - o primeiro pedido num card sem nome: ele ganha o nome, como antes, e nenhum card nasce;
#   - o card da chegada intocado (C36): a cortesia não o toca, e o primeiro pedido o adota ou lhe dá nome.
# O modelo maior é REAL (Crm::Subjects::Reviewer). O Jev é simulado: com certeza zero ("não sei"), para que quem decide
# seja o modelo maior com as opções e as instruções de cada versão; e, nos casos de card sem nome, também CERTO de "o
# mesmo assunto" (0,95), para medir que o Jev sozinho não deixa o pedido sem nome.
# Linha de base: rode o mesmo arquivo com app/services/crm/subjects da versão anterior (o placar vem por ramo,
# categoria e Jev). Dados fictícios; nenhum prompt é gravado. A saída
# (resposta, ação, cards tocados, custo) vai para EVAL_SAIDA (JSON).
module AssuntoSemNomeEval
  TETO_USD = 0.50

  RAMOS = {
    seguro: {
      a: ['Vendas de seguro', 'Pessoa que quer cotar ou contratar um seguro novo.',
          ['Novo lead', 'Cotação enviada', 'Fechado', 'Perdido']],
      b: ['Pós-venda', 'Cliente que já tem seguro: sinistro, boleto, apólice, endosso ou renovação.',
          ['Triagem', 'Em andamento', 'Resolvido']]
    },
    laboratorio: {
      a: ['Agendamento de exames', 'Quem quer orçar ou marcar exame, coleta ou check-up, e o preparo do exame.',
          ['Novo pedido', 'Orçamento enviado', 'Agendado', 'Perdido']],
      b: ['Resultados e laudos', 'Quem já fez o exame e pergunta pelo resultado, laudo ou segunda via.',
          ['Triagem', 'Em análise', 'Entregue']]
    },
    viagem: {
      a: ['Pacotes de viagem', 'Quem quer cotar ou comprar pacote, passagem ou hotel.',
          ['Novo contato', 'Proposta enviada', 'Vendido', 'Perdido']],
      b: ['Atendimento ao viajante', 'Quem já comprou: remarcação, bagagem, voucher ou cancelamento.',
          ['Aberto', 'Em tratamento', 'Resolvido']]
    }
  }.freeze

  # [ramo, categoria, card aberto, mensagens (c: cliente, e: equipe), funil esperado para pedido novo]
  # card aberto: [funil, nome do card ou nil (sem nome: o nome do contato), etapa]
  CASOS = [
    [:seguro, :cortesia, [:a, nil, 'Cotação enviada'],
     [[:c, 'Quero cotar seguro para o meu Onix 2022'], [:e, 'Segue a cotação: R$ 2.480 por ano, franquia reduzida.'],
      [:c, 'Obrigada! Boa noite']]],
    [:seguro, :cortesia, [:b, 'Apólice do HB20', 'Em andamento'],
     [[:c, 'Preciso da cópia da apólice do HB20'], [:e, 'Te mando a apólice amanhã cedo por e-mail.'], [:c, 'ok, combinado 👍']]],
    [:seguro, :estado, [:a, nil, 'Cotação enviada'],
     [[:c, 'Quero cotar seguro para o meu Onix 2022'], [:e, 'Segue a cotação: R$ 2.480 por ano, franquia reduzida.'],
      [:c, 'Acabei fechando com outra corretora, saiu mais barato. Mas obrigado pela atenção']]],
    [:seguro, :estado, [:a, nil, 'Fechado'],
     [[:c, 'Pode emitir o seguro do Corolla'], [:e, 'Emitido! O boleto da primeira parcela está no seu e-mail.'],
      [:c, 'Paguei agora de manhã, segue o comprovante']]],
    [:seguro, :estado, [:b, 'Seguro do HB20', 'Em andamento'],
     [[:e, 'Olá! A vigência do seu seguro do HB20 termina dia 30. Quer que a gente prepare a renovação?'],
      [:c, 'Quero sim, pode renovar mantendo as mesmas coberturas']]],
    [:seguro, :novo, [:a, nil, 'Cotação enviada'],
     [[:c, 'Quero cotar seguro para o meu Onix 2022'], [:e, 'Segue a cotação: R$ 2.480 por ano, franquia reduzida.'],
      [:c, 'Outra coisa: bateram no meu outro carro, que já é segurado com vocês, como abro o sinistro?']], :b],
    [:seguro, :novo, [:a, 'Seguro do Onix', 'Cotação enviada'],
     [[:e, 'Conseguiu olhar a cotação do Onix?'], [:c, 'Ainda não. Mas queria também cotar um seguro de vida para mim']], :a],
    [:seguro, :continua, [:a, nil, 'Novo lead'],
     [[:c, 'Quero cotar seguro do meu Corolla 2020'], [:e, 'Claro! Qual o CEP onde o carro dorme?'],
      [:c, 'É 04567-000, e fica na garagem do prédio']]],
    [:seguro, :continua, [:b, nil, 'Triagem'],
     [[:c, 'Preciso da segunda via do boleto do seguro'], [:e, 'Claro, é para o titular do cadastro?'],
      [:c, 'Isso, o meu mesmo. Pode mandar por e-mail?']]],

    [:laboratorio, :cortesia, [:a, nil, 'Agendado'],
     [[:e, 'Seu horário ficou para quinta às 7h, jejum de 8 horas. Qualquer dúvida estamos à disposição.'],
      [:c, 'Valeu, tenha um ótimo dia!']]],
    [:laboratorio, :cortesia, [:a, 'Hemograma e glicemia', 'Orçamento enviado'],
     [[:e, 'Orçamento enviado no seu e-mail.'], [:c, '👍']]],
    [:laboratorio, :estado, [:a, nil, 'Orçamento enviado'],
     [[:c, 'Quanto fica hemograma, glicemia e colesterol?'], [:e, 'O orçamento ficou R$ 180. Quer agendar a coleta?'],
      [:c, 'Desisti, o plano vai cobrir num laboratório perto de casa']]],
    [:laboratorio, :estado, [:a, nil, 'Orçamento enviado'],
     [[:c, 'Quero agendar a ressonância do joelho'], [:e, 'Para confirmar o horário, o pagamento é antecipado por pix: R$ 650.'],
      [:c, 'Fiz o pix agora, segue o comprovante']]],
    [:laboratorio, :estado, [:a, 'Ultrassom abdominal', 'Novo pedido'],
     [[:e, 'Para liberar o agendamento precisamos da foto do pedido médico.'], [:c, 'Pronto, mandei a foto do pedido aí em cima']]],
    [:laboratorio, :novo, [:a, nil, 'Agendado'],
     [[:e, 'Seu horário ficou para quinta às 7h.'], [:c, 'Combinado. E o resultado do exame de sangue que fiz semana passada, já saiu?']], :b],
    [:laboratorio, :novo, [:a, 'Ultrassom abdominal', 'Orçamento enviado'],
     [[:e, 'O ultrassom fica R$ 220.'], [:c, 'Certo. Queria também orçar um check-up completo para o meu pai']], :a],
    [:laboratorio, :continua, [:a, nil, 'Novo pedido'],
     [[:c, 'Vocês fazem exame de tireoide?'], [:e, 'Fazemos sim, TSH e T4 livre. Tem pedido médico?'],
      [:c, 'Tenho sim. Precisa de jejum?']]],

    [:viagem, :cortesia, [:a, nil, 'Proposta enviada'],
     [[:c, 'Quero um pacote para Natal em março'], [:e, 'Proposta enviada no seu e-mail.'], [:c, 'Show, obrigada!']]],
    [:viagem, :cortesia, [:a, 'Pacote Gramado julho', 'Proposta enviada'],
     [[:e, 'Qualquer dúvida sobre a proposta de Gramado é só chamar.'], [:c, 'Boa tarde! Pode deixar']]],
    [:viagem, :estado, [:a, nil, 'Proposta enviada'],
     [[:c, 'Quanto fica passagem e hotel para Salvador em abril?'], [:e, 'Ficou R$ 3.200 para duas pessoas, 5 noites.'],
      [:c, 'Fechei direto com a companhia aérea, não vou precisar mais']]],
    [:viagem, :estado, [:a, nil, 'Proposta enviada'],
     [[:c, 'Gostei do pacote de Maceió'], [:e, 'Para garantir a tarifa, a entrada é de 30% e o resto em 10x no cartão.'],
      [:c, 'Paguei a entrada, o resto pode passar no cartão']]],
    [:viagem, :estado, [:a, 'Pacote Porto de Galinhas', 'Proposta enviada'],
     [[:e, 'Mandei duas opções de hotel: um na praia e um no centro.'], [:c, 'Vamos fechar com o da praia, podem reservar']]],
    [:viagem, :novo, [:a, nil, 'Proposta enviada'],
     [[:c, 'Quero um pacote para Natal em março'], [:e, 'Proposta enviada no seu e-mail.'],
      [:c, 'Vou olhar. Outra coisa: minha mala extraviou no voo de volta de Lisboa que comprei com vocês, o que eu faço?']], :b],
    [:viagem, :novo, [:a, 'Pacote Gramado julho', 'Proposta enviada'],
     [[:e, 'Conseguiu ver a proposta de Gramado?'], [:c, 'Vi sim. Queria também uma passagem para Recife em setembro, só ida']], :a],
    [:viagem, :continua, [:a, nil, 'Novo contato'],
     [[:c, 'Quanto fica um pacote para Porto Seguro em janeiro, 2 adultos?'], [:e, 'Quais datas vocês preferem?'],
      [:c, 'Do dia 10 ao 17, com café da manhã']]],

    # O primeiro pedido num card sem nome: ele ganha o nome (o que já acontecia) e nenhum card nasce.
    [:seguro, :primeiro, [:a, nil, 'Novo lead'], [[:c, 'Boa tarde, quero fazer seguro para a minha moto, uma CG 160 2023']]],
    [:laboratorio, :primeiro, [:a, nil, 'Novo pedido'], [[:c, 'Oi! Quanto custa o exame de vitamina D? Dá para fazer sábado?']]],
    [:viagem, :primeiro, [:a, nil, 'Novo contato'], [[:c, 'Olá, queria um orçamento de cruzeiro pela costa brasileira em fevereiro']]],

    # O card da chegada intocado (C36, card [funil, nil, etapa, :chegada]): a cortesia não o toca, e o primeiro pedido o
    # adota (outro funil) ou lhe dá nome (mesmo funil). Ele nunca é "o mesmo assunto".
    [:seguro, :chegada_cortesia, [:a, nil, 'Novo lead', :chegada], [[:c, 'Oi, boa tarde']]],
    [:seguro, :chegada_pedido, [:a, nil, 'Novo lead', :chegada], [[:c, 'Preciso da segunda via do boleto do meu seguro residencial']], :b],
    [:seguro, :chegada_pedido, [:a, nil, 'Novo lead', :chegada], [[:c, 'Quero cotar seguro para o meu Gol 2018']], :a],
    [:laboratorio, :chegada_cortesia, [:a, nil, 'Novo pedido', :chegada], [[:c, 'Bom dia!']]],
    [:laboratorio, :chegada_pedido, [:a, nil, 'Novo pedido', :chegada], [[:c, 'O laudo da minha mamografia já ficou pronto?']], :b],
    [:laboratorio, :chegada_pedido, [:a, nil, 'Novo pedido', :chegada], [[:c, 'Quanto custa o teste de gravidez de sangue?']], :a],
    [:viagem, :chegada_cortesia, [:a, nil, 'Novo contato', :chegada], [[:c, 'Olá 👋']]],
    [:viagem, :chegada_pedido, [:a, nil, 'Novo contato', :chegada], [[:c, 'Meu voo foi cancelado, preciso remarcar a passagem que comprei']], :b],
    [:viagem, :chegada_pedido, [:a, nil, 'Novo contato', :chegada], [[:c, 'Quero um pacote para Foz do Iguaçu no feriado']], :a]
  ].freeze

  # Os mesmos casos de card sem nome (fora a cortesia e o card da chegada) com o Jev CERTO de "o mesmo assunto" (certeza
  # 0,95). Na versão sem essa opção para o card sem nome, o Jev cai em "não sei" e o modelo maior decide, como acima.
  JEV_NO_MESMO = CASOS.select { |(_, categoria, card)| %i[estado continua primeiro].include?(categoria) && card[1].nil? }
                      .map { |(ramo, categoria, card, mensagens, esperado)| [ramo, categoria, card, mensagens, esperado, :mesmo] }

  TODOS = CASOS + JEV_NO_MESMO
end

# rubocop:disable RSpec/DescribeClass, RSpec/InstanceVariable, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
RSpec.describe 'Eval pago #1918 PR2: o porteiro separa cortesia, mudança de situação, pedido novo e card sem nome' do
  let(:account) { create(:account, name: 'Empresa Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:media_enabled?).and_return(false)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_eval_not_real', model: 'jev-1.13.0')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
    stub_jev
    guardar_resposta
  end

  # Um ramo, uma caixa, dois funis ligados a ela.
  def ramo(chave)
    @ramos ||= {}
    @ramos[chave] ||= begin
      inbox = create(:inbox, account: account, name: "Caixa #{chave}")
      account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :auto)
      funis = AssuntoSemNomeEval::RAMOS.fetch(chave).transform_values { |(nome, quando, etapas)| funil(inbox, nome, quando, etapas) }
      { inbox: inbox, funis: funis }
    end
  end

  def funil(inbox, nome, quando, etapas)
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: nome)
    pipeline.update!(when_to_use: quando)
    primeira.update!(name: etapas.first)
    etapas.drop(1).each_with_index { |etapa, posicao| create_crm_stage(account: account, pipeline: pipeline, name: etapa, position: posicao + 1) }
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: primeira, auto_create_card: false, created_by: admin)
    pipeline
  end

  # A chave que o modelo maior escolheu para o principal (a decisão gravada não diferencia "nenhum" de "o mesmo").
  def guardar_resposta
    allow(Crm::Subjects::Reviewer).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap do |revisor|
        allow(revisor).to receive(:revisar).and_wrap_original do |revisar, *dados|
          revisar.call(*dados).tap { |veredito| @resposta = veredito.resposta }
        end
      end
    end
  end

  # O Jev "não sabe" (certeza zero) e o modelo maior decide; no caso com `jev: :mesmo`, o Jev escolhe "o mesmo assunto"
  # com certeza 0,95 quando a pergunta oferece a opção.
  def stub_jev
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
      criterios = JSON.parse(request.body).dig('questions', 'decisao', 'criteria').to_h
      escolha = @jev == :mesmo && criterios.key?(Crm::Subjects::Question::MESMO_ASSUNTO)
      resposta = escolha ? [Crm::Subjects::Question::MESMO_ASSUNTO, 0.95] : [Crm::Subjects::Question::SEM_ASSUNTO, 0.0]
      @resposta_do_jev = resposta[0]
      { status: 200, body: { model: 'jev-1.13.0', usage: { input_tokens: 300, output_tokens: 5 },
                             answers: { decisao: { type: 'choice', choice: resposta[0], confidence: resposta[1] } } }.to_json }
    end
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1918-assunto-sem-nome.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > AssuntoSemNomeEval::TETO_USD

    resultado
  end

  # A conversa com as mensagens do caso e o card aberto em foco. Sem nome: o título é o nome do contato, como o card que
  # a caixa cria sozinha.
  def montar(indice, chave, (funil, nome, etapa, chegada), mensagens)
    dados = ramo(chave)
    contato = create(:contact, account: account, name: "Pessoa Teste #{indice}")
    conversa = create(:conversation, account: account, inbox: dados[:inbox], contact: contato)
    ultima = mensagens.map do |(quem, texto)|
      create(:message, account: account, inbox: dados[:inbox], conversation: conversa, content: texto,
                       message_type: quem == :c ? :incoming : :outgoing)
    end.last
    [conversa, ultima, card_aberto(conversa, dados, [funil, nome, etapa, chegada])]
  end

  def card_aberto(conversa, dados, (funil, nome, etapa, chegada))
    pipeline = dados[:funis].fetch(funil)
    stage = pipeline.stages.find_by!(name: etapa)
    metadata = metadata_do_card(nome, chegada)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversa.contact, primary_conversation: conversa,
                                     inbox: dados[:inbox], title: nome || conversa.contact.name, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa)
                         .update!(is_primary: true, focused_at: 1.hour.ago)
    card
  end

  # Com nome: nomeado pela IA. Card da chegada: criado pelo sistema quando a conversa chegou (C36).
  def metadata_do_card(nome, chegada)
    return { 'subject' => { 'source' => 'ai' } } if nome
    return {} unless chegada

    { Crm::Conversations::CardSyncer::AUTO_SYNC_METADATA => { 'source' => Crm::Conversations::CardSyncer::OBSERVER_SOURCE } }
  end

  def rodar(indice, (chave, categoria, card, mensagens, esperado, jev))
    @jev = jev
    conversa, mensagem, aberto = montar(indice, chave, card, mensagens)
    titulo = aberto.title
    antes = account.crm_cards.pluck(:id)
    @resposta = nil
    @resposta_do_jev = nil
    decisao = com_custo { Crm::Subjects::Identifier.new(conversation: conversa, message: mensagem).perform }
    modelo_maior = !@resposta.nil?
    @resposta ||= @resposta_do_jev
    novos = account.crm_cards.where.not(id: antes)
    funil_esperado = esperado && ramo(chave)[:funis].fetch(esperado)
    saida[:casos] << { indice: indice, ramo: chave, categoria: categoria, jev: jev || :nao_sabe, card_sem_nome: card[1].nil?,
                       chegada: card[3] == :chegada, modelo_maior: modelo_maior,
                       resposta: @resposta, sobre_o_card: [Crm::Subjects::Question::MESMO_ASSUNTO, "card_#{aberto.id}"].include?(@resposta),
                       estado: decisao&.state, acao: decisao&.action, principal_e_o_card: decisao&.card_id == aberto.id,
                       card_tocado: Array(decisao&.touched_card_ids).include?(aberto.id), renomeado: aberto.reload.title != titulo,
                       funil_do_card: aberto.pipeline_id == funil_esperado&.id,
                       cards_novos: novos.count, novo_no_funil_esperado: funil_esperado ? novos.exists?(pipeline_id: funil_esperado.id) : nil,
                       titulo: decisao&.title, motivo: decisao&.reason }
  end

  # O critério de cada categoria.
  def certo?(caso)
    case caso[:categoria]
    when :cortesia then caso[:resposta] == Crm::Subjects::Question::SEM_ASSUNTO && caso[:cards_novos].zero? && !caso[:renomeado]
    when :estado then caso[:sobre_o_card] && caso[:principal_e_o_card] && caso[:cards_novos].zero? && !caso[:renomeado]
    when :novo then caso[:novo_no_funil_esperado]
    when :primeiro then caso[:principal_e_o_card] && caso[:renomeado] && caso[:cards_novos].zero?
    when :continua then caso[:principal_e_o_card] && caso[:card_tocado] && caso[:cards_novos].zero?
    when :chegada_cortesia then caso[:resposta] == Crm::Subjects::Question::SEM_ASSUNTO && !caso[:card_tocado] && !caso[:renomeado]
    when :chegada_pedido then caso[:renomeado] && caso[:funil_do_card] && caso[:cards_novos].zero?
    end
  end

  it 'conversas fictícias em 3 ramos: cada mensagem vai para o assunto certo' do
    AssuntoSemNomeEval::TODOS.each_with_index { |caso, indice| rodar(indice, caso) }
    saida[:casos].each { |caso| caso[:certo] = certo?(caso) }
    saida[:placar] = saida[:casos].group_by { |caso| [caso[:ramo], caso[:categoria], caso[:jev]] }
                                  .transform_keys { |chave| chave.join('/') }
                                  .transform_values { |casos| "#{casos.count { |caso| caso[:certo] }}/#{casos.size}" }
    gravar_saida!

    errados = saida[:casos].reject { |caso| caso[:certo] }
    cortesias = %i[cortesia chegada_cortesia]
    expect(errados.select { |caso| cortesias.include?(caso[:categoria]) }).to be_empty
    expect(errados.size).to be <= 3
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/InstanceVariable, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
