require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. O Jev é simulado com certeza zero ("não sei"): quem decide é sempre o
# modelo maior (Crm::Subjects::Reviewer), que é o real; o tamanho do que iria ao Jev é medido pelo corpo da chamada
# simulada. Teto do #1924: US$ 0,30 no total; esta rodada para ao passar de TETO_USD, somado pelo evento de custo da IA
# (Crm::Ai::UsageRecorder::EVENT_NAME). O caminho em que o Jev responde sozinho, seguro, NÃO é avaliado aqui (revisão).
#
# #1924: a IA de assunto separa venda de pós-venda. Cinco ramos de negócio inventados. Os textos de "quando usar" são
# curtos e genéricos, e a etapa depois da venda tem nome diferente em cada ramo. Além dos casos da Issue, há os da
# revisão: funil de atendimento marcado como venda (o interruptor nasce ligado), conta só com funis de venda, renovação
# que o "quando usar" manda para o funil de venda, desistir da cotação antes de comprar, card de chegada sem nome com
# outro assunto nomeado aberto, e pós-venda sem nenhum card aberto numa conta só com funis de venda (abre no funil mais
# próximo, como antes: a equipe não perde o pedido). Categorias (o que conta como certo):
#   - fica: o modelo maior respondeu o assunto atual e a decisão ficou "kept"; nenhum card nasce, nada muda de nome, o
#     foco segue nele;
#   - volta: o modelo maior respondeu o outro assunto aberto e a decisão foi aplicada; ele vira o foco, sem card novo;
#   - novo: UM card novo num dos funis aceitos, que vira o foco (ou o card atual sem nome ganha nome, se for desse funil);
#     nada mais é criado, e a decisão foi aplicada;
#   - nao_cria: sem funil que sirva (só há de venda) e com assunto aberto: o modelo maior respondeu o assunto atual,
#     "kept", nenhum card nasce e nada muda de nome.
# Falha, sem cota, sem conteúdo ou dúvida nunca contam como acerto.
# Dados fictícios; nenhum prompt é gravado. A saída (resposta do modelo maior, ação, decisão, custo) vai para
# EVAL_SAIDA (JSON).
module VendaPosVendaEval
  TETO_USD = 0.07

  # ramo => { letra => [nome, quando usar, etapas, conta como venda] }
  RAMOS = {
    seguro: {
      a: ['Seguros', 'Pessoas interessadas em contratar seguro.', ['Novo lead', 'Cotação enviada', 'Apólice emitida', 'Perdido'], true],
      b: ['Atendimento', 'Suporte aos clientes.', ['Triagem', 'Em andamento', 'Resolvido'], false]
    },
    software: {
      a: ['Comercial', 'Empresas interessadas no sistema de gestão.', ['Novo lead', 'Demonstração', 'Implantação', 'Perdido'], true],
      b: ['Sucesso do cliente', 'Suporte aos clientes.', ['Aberto', 'Em análise', 'Concluído'], false]
    },
    academia: {
      a: ['Matrículas', 'Quem quer conhecer os planos da academia.', ['Interessado', 'Aula experimental', 'Primeiras semanas', 'Perdido'], true],
      b: ['Relacionamento', 'Suporte aos alunos.', ['Novo', 'Em tratamento', 'Resolvido'], false]
    },
    # Funil de atendimento com o interruptor "conta como venda" ligado, como nasce todo funil.
    odonto: {
      a: ['Tratamentos', 'Pacientes interessados em fazer um tratamento.', %w[Contato Orçamento Fechado Perdido], true],
      b: ['Pós-tratamento', 'Pacientes que já fizeram tratamento: retorno, garantia, reclamação e cancelamento.', %w[Aberto Resolvido], true]
    },
    # Só funis de venda: um cancelamento não tem para onde ir.
    idiomas: {
      a: ['Cursos', 'Quem quer conhecer os cursos de idiomas.', %w[Novo Proposta Matriculado Perdido], true],
      b: ['Empresas', 'Turmas fechadas para empresas.', %w[Contato Proposta Fechado], true]
    },
    # Renovação comercial: o "quando usar" do funil de venda cobre a renovação.
    corretora: {
      a: ['Vendas e renovações', 'Contratação de seguro novo e renovação de apólice.', ['Novo lead', 'Cotação', 'Fechado', 'Perdido'], true],
      b: ['Sinistros', 'Clientes com apólice que tiveram sinistro.', ['Aviso', 'Em regulação', 'Encerrado'], false]
    },
    # Conta pequena com um funil só, de venda.
    petshop: {
      a: ['Banho e tosa', 'Clientes que querem agendar banho e tosa.', %w[Novo Agendado Atendido Perdido], true]
    },
    # Dois funis de venda, nenhum de atendimento.
    moveis: {
      a: ['Vendas', 'Quem quer comprar móveis planejados.', %w[Contato Projeto Fechado Perdido], true],
      b: ['Corporativo', 'Empresas que querem mobiliar escritórios.', %w[Contato Proposta Fechado], true]
    }
  }.freeze

  # [ramo, categoria, cards abertos (o 1º é o atual), mensagens (c: cliente, e: equipe), funis aceitos para o pedido novo]
  # card aberto: [funil, nome do card ou nil (sem nome: o nome do contato), etapa]
  CASOS = [
    [:seguro, :fica, [[:a, 'Seguro do Corolla', 'Apólice emitida']],
     [[:e, 'Apólice emitida! Bem-vindo. Nos próximos dias chega o kit com o cartão do seguro.'],
      [:c, 'Que bom! O cartão chega pelo correio ou por e-mail? E a vistoria do carro ainda precisa ser feita?']]],
    [:seguro, :novo, [[:a, 'Seguro do Onix', 'Apólice emitida']],
     [[:c, 'Quero cancelar o seguro do meu carro, vendi o Onix semana passada'], [:e, 'Entendi. Qual a data da venda?'],
      [:c, 'Dia 12'], [:e, 'O comprador já transferiu o documento?'], [:c, 'Sim, já está no nome dele'],
      [:e, 'Certo, vou verificar aqui'], [:c, 'Consegue resolver ainda hoje?']], [:b]],
    [:seguro, :novo, [[:a, nil, 'Novo lead']],
     [[:c, 'Oi, meu seguro residencial com vocês vence mês que vem. Quero renovar, como faço?']], %i[a b]],
    [:seguro, :novo, [[:b, 'Segunda via do boleto', 'Em andamento']],
     [[:e, 'Pronto, a segunda via do boleto foi para o seu e-mail.'],
      [:c, 'Obrigado! Aproveitando, queria fazer um seguro para a moto que acabei de comprar']], [:a]],
    [:seguro, :fica, [[:a, 'Seguro do HB20', 'Cotação enviada']],
     [[:e, 'Segue a cotação do seguro do HB20, válida por 7 dias.'],
      [:c, 'Achei caro. Pode cancelar essa cotação, não vou fazer o seguro agora']]],

    [:software, :fica, [[:a, 'Sistema para a loja', 'Implantação']],
     [[:e, 'Contrato assinado! Agora começa a implantação: a consultora vai configurar o sistema com vocês.'],
      [:c, 'Ótimo. Como importo a planilha de produtos que já temos? E quantos usuários posso cadastrar?']]],
    [:software, :novo, [[:a, 'Sistema para a loja', 'Implantação']],
     [[:c, 'Queremos cancelar a assinatura do sistema a partir do mês que vem'], [:e, 'Poxa, posso perguntar o motivo?'],
      [:c, 'Vamos fechar uma das lojas'], [:e, 'Entendo. Vocês usam quantas licenças hoje?'], [:c, 'Cinco'],
      [:e, 'Ok, vou ver as condições do contrato'], [:c, 'Tem multa por sair antes do fim do contrato?']], [:b]],
    [:software, :novo, [[:a, nil, 'Novo lead']],
     [[:c, 'Bom dia, somos clientes há um ano e o contrato vence agora. Queremos renovar por mais 12 meses.']], %i[a b]],
    [:software, :novo, [[:b, 'Erro na nota fiscal', 'Em análise']],
     [[:e, 'O erro da nota fiscal foi corrigido na versão de hoje.'],
      [:c, 'Show, funcionou. Outra coisa: queremos contratar o sistema também para a nossa nova filial em outra cidade']], [:a]],
    [:software, :volta, [[:a, nil, 'Novo lead'], [:b, 'Erro na nota fiscal', 'Em análise']],
     [[:c, 'Oi, e aquele erro na emissão da nota fiscal que eu reclamei ontem, já corrigiram?']]],

    [:academia, :fica, [[:a, 'Plano anual', 'Primeiras semanas']],
     [[:e, 'Matrícula feita! Na primeira semana você faz a avaliação física e monta o treino com o professor.'],
      [:c, 'Legal! Preciso levar alguma coisa na avaliação física? E qual horário tem professor livre?']]],
    [:academia, :novo, [[:a, 'Plano mensal', 'Primeiras semanas']],
     [[:c, 'Quero cancelar meu plano, vou me mudar de cidade'], [:e, 'Que pena! Quando é a mudança?'],
      [:c, 'Dia 30'], [:e, 'Você tem alguma pendência de pagamento?'], [:c, 'Não, está tudo pago'],
      [:e, 'Certo, vou consultar aqui'], [:c, 'Dá para encerrar ainda esta semana?']], [:b]],
    [:academia, :novo, [[:a, nil, 'Interessado']],
     [[:c, 'Oi! Meu plano semestral termina semana que vem e quero renovar por mais seis meses']], %i[a b]],
    [:academia, :novo, [[:b, 'Catraca não libera', 'Em tratamento']],
     [[:e, 'Liberamos sua digital na catraca, pode testar.'],
      [:c, 'Funcionou, valeu! E queria matricular a minha filha também, quais planos vocês têm para adolescente?']], [:a]],

    [:odonto, :novo, [[:a, 'Clareamento', 'Fechado']],
     [[:c, 'Fiz o clareamento mês passado e agora meus dentes estão muito sensíveis. Preciso de um retorno']], [:b]],
    [:odonto, :novo, [[:a, 'Aparelho ortodôntico', 'Fechado']],
     [[:c, 'Quero cancelar o plano de manutenção do aparelho, vou trocar de dentista']], [:b]],
    [:idiomas, :nao_cria, [[:a, 'Curso de inglês', 'Matriculado']],
     [[:e, 'Bem-vinda à turma de inglês! As aulas começam segunda.'],
      [:c, 'Preciso cancelar a minha matrícula, perdi o emprego e não vou conseguir pagar']]],
    [:corretora, :novo, [[:b, 'Sinistro do Gol', 'Em regulação']],
     [[:e, 'O perito vai à sua casa amanhã às 10h.'],
      [:c, 'Ok, obrigado. Aproveitando: a apólice do Gol vence mês que vem e quero renovar']], [:a]],

    # Revisão: sem card aberto e só funis de venda, o pós-venda abre no funil mais próximo em vez de sumir.
    [:idiomas, :novo, [],
     [[:c, 'Oi, sou aluna de vocês e preciso cancelar a minha matrícula no curso de espanhol, como faço?']], %i[a b]],
    [:petshop, :novo, [],
     [[:c, 'Levei meu cachorro no banho ontem e ele voltou com uma ferida na orelha. Quero uma explicação']], %i[a]],
    [:moveis, :novo, [],
     [[:c, 'Comprei o armário planejado com vocês mês passado e a porta já está empenada. Preciso de assistência']], %i[a b]]
  ].freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1924: a IA de assunto separa venda de pós-venda' do
  let(:account) { create(:account, name: 'Empresa Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  # A resposta do modelo maior e o tamanho do que iria ao Jev, do caso que está rodando.
  let(:registro) { {} }
  let(:ramos) { {} }

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

  # Um ramo, uma caixa, dois funis ligados a ela, cada um com o seu "conta como venda".
  def ramo(chave)
    ramos[chave] ||= begin
      inbox = create(:inbox, account: account, name: "Caixa #{chave}")
      account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :auto)
      funis = VendaPosVendaEval::RAMOS.fetch(chave).to_h do |letra, (nome, quando, etapas, venda)|
        [letra, funil(inbox, nome, quando, etapas, venda: venda)]
      end
      { inbox: inbox, funis: funis }
    end
  end

  def funil(inbox, nome, quando, etapas, venda:)
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: nome)
    pipeline.update!(when_to_use: quando, counts_as_sale: venda)
    primeira.update!(name: etapas.first)
    etapas.drop(1).each_with_index { |etapa, posicao| create_crm_stage(account: account, pipeline: pipeline, name: etapa, position: posicao + 1) }
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: primeira, auto_create_card: false, created_by: admin)
    pipeline
  end

  def guardar_resposta
    allow(Crm::Subjects::Reviewer).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap do |revisor|
        allow(revisor).to receive(:revisar).and_wrap_original do |revisar, *dados|
          revisar.call(*dados).tap { |veredito| registro[:resposta] = veredito.resposta }
        end
      end
    end
  end

  # O Jev "não sabe" (certeza zero): o modelo maior decide sempre. Guarda o tamanho do que iria ao Jev.
  def stub_jev
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
      registro[:jev_chars] = request.body.to_s.length
      { status: 200,
        body: { model: 'jev-1.13.0', usage: { input_tokens: 0, output_tokens: 0 },
                answers: { decisao: { type: 'choice', choice: Crm::Subjects::Question::SEM_ASSUNTO, confidence: 0.0 } } }.to_json }
    end
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0, tokens_in: 0, tokens_out: 0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1924-venda-pos-venda.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = lambda do |*, payload|
      saida[:custo_usd] += payload[:cost].to_f
      next unless payload[:feature] == Crm::Subjects::FEATURE_REVISAO

      saida[:tokens_in] += payload.dig(:tokens, :in).to_i
      saida[:tokens_out] += payload.dig(:tokens, :out).to_i
    end
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > VendaPosVendaEval::TETO_USD

    resultado
  end

  # Os cards abertos, o 1º em foco (o assunto atual) e os outros vinculados com foco mais antigo.
  def montar(indice, chave, cards, mensagens)
    dados = ramo(chave)
    contato = create(:contact, account: account, name: "Pessoa Teste #{indice}")
    conversa = create(:conversation, account: account, inbox: dados[:inbox], contact: contato)
    ultima = mensagens.map do |(quem, texto)|
      create(:message, account: account, inbox: dados[:inbox], conversation: conversa, content: texto,
                       message_type: quem == :c ? :incoming : :outgoing)
    end.last
    abertos = cards.each_with_index.map { |aberto, posicao| card_aberto(conversa, dados, aberto, posicao) }
    [conversa, ultima, abertos]
  end

  def card_aberto(conversa, dados, (funil, nome, etapa), posicao)
    pipeline = dados[:funis].fetch(funil)
    stage = pipeline.stages.find_by!(name: etapa)
    metadata = nome ? { 'subject' => { 'source' => 'ai' } } : {}
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversa.contact, primary_conversation: conversa,
                                     inbox: dados[:inbox], title: nome || conversa.contact.name, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa)
                         .update!(is_primary: posicao.zero?, focused_at: (posicao + 1).hours.ago)
    card
  end

  def rodar(indice, (chave, categoria, cards, mensagens, aceitos))
    conversa, mensagem, abertos = montar(indice, chave, cards, mensagens)
    titulos = abertos.to_h { |card| [card.id, card.title] }
    decisao, novos = decidir(conversa, mensagem)
    caso = { indice: indice, ramo: chave, categoria: categoria, card_sem_nome: cards.any? && cards.first[1].nil?,
             mensagens: mensagens.size, cards_novos: novos.size, **resultado(decisao) }
    cena = { conversa: conversa, abertos: abertos, novos: novos, mudou: renomeados(abertos, titulos), aceitos: funis_aceitos(chave, aceitos) }
    saida[:casos] << caso.merge(certo: certo?(caso, cena))
  end

  # A decisão e os cards que nasceram com ela.
  def decidir(conversa, mensagem)
    antes = account.crm_cards.pluck(:id)
    registro.clear
    decisao = com_custo { Crm::Subjects::Identifier.new(conversation: conversa, message: mensagem).perform }
    [decisao, account.crm_cards.where.not(id: antes).to_a]
  end

  def funis_aceitos(chave, aceitos)
    Array(aceitos).map { |letra| ramo(chave)[:funis].fetch(letra).id }
  end

  def resultado(decisao)
    { resposta: registro[:resposta], estado: decisao&.state, acao: decisao&.action, jev_chars: registro[:jev_chars],
      titulo: decisao&.title, motivo: decisao&.reason }
  end

  def em_foco(conversa)
    Crm::Cards::ConversationCardFinder.new(account: account).all(conversa).first
  end

  def renomeados(abertos, titulos)
    abertos.map(&:reload).reject { |card| card.title == titulos[card.id] }
  end

  # fica / nao_cria / volta: a resposta e o estado esperados, nada nasce nem muda de nome, e o foco é o esperado.
  # cena: conversa, abertos (o 1º é o atual), novos (cards que nasceram), mudou (abertos renomeados), aceitos (ids de funil).
  def certo?(caso, cena)
    return novo_certo?(caso, cena) if caso[:categoria] == :novo
    return false unless cena[:novos].empty? && cena[:mudou].empty? && resposta_esperada?(caso, cena[:abertos])

    foco = caso[:categoria] == :volta ? cena[:abertos].second : cena[:abertos].first
    em_foco(cena[:conversa])&.id == foco.id
  end

  # Falha, sem cota, sem conteúdo ou dúvida não contam: só a resposta certa, com a decisão concluída.
  def resposta_esperada?(caso, abertos)
    esperado = if caso[:categoria] == :volta
                 ['applied', "card_#{abertos.second.id}"]
               else
                 ['kept', Crm::Subjects::Question::MESMO_ASSUNTO]
               end
    esperado == [caso[:estado], caso[:resposta]]
  end

  # Um card novo num funil aceito, em foco; ou o card atual sem nome ganhou nome e está num funil aceito.
  def novo_certo?(caso, cena)
    return false unless caso[:estado] == 'applied'

    alvo = alvo_do_novo(cena[:abertos], cena[:novos], cena[:mudou], caso[:card_sem_nome])
    alvo.present? && cena[:aceitos].include?(alvo.reload.pipeline_id) && em_foco(cena[:conversa])&.id == alvo.id
  end

  def alvo_do_novo(abertos, novos, mudou, sem_nome)
    return novos.first if novos.one? && mudou.empty?

    abertos.first if novos.empty? && sem_nome && mudou == [abertos.first]
  end

  def placar(por)
    saida[:casos].group_by { |caso| caso[por] }.transform_values { |casos| "#{casos.count { |caso| caso[:certo] }}/#{casos.size}" }
  end

  it '21 conversas fictícias em 8 ramos: venda e pós-venda no funil certo' do
    VendaPosVendaEval::CASOS.each_with_index { |caso, indice| rodar(indice, caso) }
    saida[:placar] = placar(:ramo)
    saida[:placar_categoria] = placar(:categoria)
    gravar_saida!

    errados = saida[:casos].reject { |caso| caso[:certo] }
    expect(errados.select { |caso| caso[:categoria] == :fica }).to be_empty
    expect(errados.size).to be <= 1
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass
