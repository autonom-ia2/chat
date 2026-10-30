require 'rails_helper'

# A visão "Equipe" de CRM › Números (#1992, F5 do #1871): os números da equipe nos funis que quem abre enxerga, o R$
# dos colegas, "Quem precisa de ajuda", a IA numa linha só e o custo da IA só para o administrador ou o Financeiro (financial_view).
RSpec.describe Crm::Numeros::Equipe do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Marcos', display_name: 'Marcos') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana', display_name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno', display_name: 'Bruno') }
  let(:carla) { create(:user, account: account, role: :agent, name: 'Carla', display_name: 'Carla') }
  let(:inbox) { create_crm_inbox(account: account, members: [ana, bruno, carla]) }
  let(:sale) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Suporte', created_by: admin, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end
  let(:sofia) { create(:agent_bot, account: account, name: 'Sofia') }

  around { |example| travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run } }

  before { allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: 5.0, fetched_at: nil) }

  # Só os funis listados, como o painel de quem tem acesso por funil.
  def acesso(pipelines = nil)
    return Crm::Access::VisiblePipelines.new(user: admin, account: account) if pipelines.nil?

    ids = pipelines.map { |pipeline, _stage| pipeline.id }
    Struct.new(:ids) { def apply_to_reports(scope) = scope.where(id: ids) }.new(ids)
  end

  # perfil: dono (true), leitura (false) e valor (true, #2075); o custo segue o dono.
  def equipe(user: admin, pipelines: nil, chave: nil, **perfil)
    perfil = { dono: true, leitura: false, valor: true }.merge(perfil)
    Current.account = account
    described_class.new(account: account, user: user, mes: Crm::Numeros::Mes.new(account: account, chave: chave),
                        acesso: acesso(pipelines), perfil: perfil.merge(custo: perfil[:dono])).perform
  end

  def card(pipeline_and_stage, owner:, conversation: nil, **attrs)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, primary_conversation: conversation,
                              title: "Card #{SecureRandom.hex(3)}", **attrs)
  end

  def close(card, result = 'won')
    Crm::Cards::Closer.new(card: card, actor: admin, result: result).perform
  end

  def conversation(assignee: nil)
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: assignee)
  end

  def resposta_do_robo(chat, robo = sofia, quando: 2.days.ago)
    create(:message, account: account, inbox: chat.inbox, conversation: chat, message_type: :outgoing, sender: robo,
                     created_at: quando)
  end

  def passagem(chat, para, robo: sofia)
    Crm::Passagem.create!(account: account, conversation: chat, de_type: 'AgentBot', de_id: robo.id, de_nome: robo.name,
                          para_type: 'User', para_id: para.id, para_nome: para.name, em: 2.days.ago)
  end

  it 'o dono vê a empresa: o R$ de cada um, os dois blocos e a IA numa linha própria, com o custo' do
    sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 2_000_000, 'currency' => 'BRL' } })
    close(card(sale, owner: ana, value_cents: 620_000))
    close(card(sale, owner: bruno, value_cents: 290_000))
    close(card(service, owner: carla), 'resolved')
    chat = conversation(assignee: ana)
    resposta_do_robo(chat)
    passagem(chat, ana)
    close(card(sale, owner: ana, conversation: chat, value_cents: 100_000))
    Crm::AiUsageEvent.create!(account: account, feature: 'agente_resposta', model: 'gpt-test', cost_estimate: 2.0)

    result = equipe

    expect(result).to include(papel: 'dono', moeda: 'BRL', leitura: false)
    expect(result[:topo]).to include(escopo: 'empresa', medida: 'valor', feito: 10_100.0, meta: 20_000.0, fechadas: 3)
    expect(result[:topo][:frase]).to include(tipo: 'empresa', resolvidos: 1)
    expect(result[:vendendo][:itens].first).to include(tipo: 'fechadas', n: 3, valor: 10_100.0)
    linhas = result[:quemCuidou][:linhas]
    expect(linhas.map { |linha| [linha[:nome], linha.key?(:venda) ? linha[:venda][:valor] : linha[:atende][:resolveu]] })
      .to eq([['Ana', 7200.0], ['Bruno', 2900.0], ['Carla', 1]])
    expect(result[:quemCuidou][:ia]).to include(nome: 'Sofia', atendeu: 1, passou: 1, venda: { participou: 1, valor: 1000.0 },
                                                custo: { valor: 10.0, porConversa: 10.0, moeda: 'BRL' })
    expect(result[:quemCuidou][:plataforma]).to eq(ia: 'Sofia', atendeu: 1, participou: 1, valor: 1000.0)
  end

  it 'o gestor de vendas vê só Vender, sem o custo da IA, e o topo é da equipe' do
    close(card(sale, owner: ana, value_cents: 100_000))
    close(card(service, owner: carla), 'resolved')
    resposta_do_robo(conversation.tap { |chat| card(sale, owner: ana, conversation: chat) })

    result = equipe(user: ana, dono: false, pipelines: [sale])

    expect(result).to include(papel: 'gestor_vendas', atendendo: nil)
    expect(result[:topo]).to include(escopo: 'equipe', frase: include(tipo: 'equipe_vendas'))
    expect(result[:quemCuidou][:linhas].pluck(:nome)).to eq(%w[Ana])
    expect(result[:quemCuidou][:ia][:custo]).to be_nil
    expect(result[:quemCuidou][:ia][:atende]).to be_nil
    expect(result[:quemCuidou][:plataforma]).to be_nil
  end

  it 'o gestor de atendimento vê só Atender: resolvidos, lembretes e parados, sem R$' do
    close(card(service, owner: carla), 'resolved')
    card(service, owner: carla, next_follow_up_at: 1.day.ago)

    result = equipe(user: carla, dono: false, pipelines: [service])

    expect(result).to include(papel: 'gestor_atendimento', vendendo: nil)
    expect(result[:topo]).to include(escopo: 'equipe', medida: 'resolvidos', feito: 1, botao: { tipo: 'lembretes_equipe', n: 1 })
    expect(result[:atendendo][:itens].map { |item| [item[:tipo], item[:n]] })
      .to eq([['resolvidos', 1], ['lembretes', 1], ['parados_atende', 0]])
    expect(result[:quemCuidou][:linhas]).to eq([{ id: carla.id, nome: 'Carla', voce: true,
                                                  atende: { resolveu: 1, noPrazo: nil, meta: nil, pct: nil } }])
  end

  it 'uma conta só para a IA: dois robôs na mesma conversa contam uma vez, e a tela diz "A IA"' do
    lia = create(:agent_bot, account: account, name: 'Lia')
    chat = conversation
    card(sale, owner: ana, conversation: chat)
    resposta_do_robo(chat, sofia)
    resposta_do_robo(chat, lia)
    outra = conversation
    card(sale, owner: ana, conversation: outra)
    resposta_do_robo(outra, lia)

    ia = equipe[:quemCuidou][:ia]

    expect(ia).to include(nome: nil, agenteId: nil, atendeu: 2)
  end

  it 'a IA conta só quem entrou num funil, e some quando não fez nada no mês' do
    resposta_do_robo(conversation)
    card(sale, owner: ana)

    expect(equipe[:quemCuidou][:ia]).to be_nil
  end

  it 'resolveu sozinha: só os casos de Atender sem pessoa no meio' do
    sozinha = conversation
    card(service, owner: carla, conversation: sozinha)
    resposta_do_robo(sozinha)
    com_pessoa = conversation
    card(service, owner: carla, conversation: com_pessoa)
    resposta_do_robo(com_pessoa)
    create(:message, account: account, inbox: inbox, conversation: com_pessoa, message_type: :outgoing, sender: carla)
    [sozinha, com_pessoa].each do |chat|
      create(:reporting_event, account: account, conversation_id: chat.id, name: 'conversation_resolved', event_end_time: 1.day.ago)
    end

    expect(equipe[:quemCuidou][:ia][:atende]).to eq(resolveuSozinha: 1)
  end

  # #1999: a frase do topo e a linha da IA leem o mesmo "atendeu" e o mesmo "passou", somando Vender e Atender.
  it 'a IA tem um número só de atendidas e de passadas, nos dois tipos de funil' do
    [sale, service].each do |funil|
      chat = conversation
      card(funil, owner: carla, conversation: chat)
      resposta_do_robo(chat)
      passagem(chat, carla)
    end

    result = equipe

    expect(result[:quemCuidou][:ia]).to include(atendeu: 2, passou: 2)
    expect(result[:quemCuidou][:ia][:venda]).not_to have_key(:passou)
    expect(result[:quemCuidou][:ia][:atende]).not_to have_key(:passou)
    expect(result[:quemCuidou][:plataforma]).to include(atendeu: 2)
  end

  # #1999: quem vende e atende tem uma linha só, com os dois números.
  it '"Quem cuidou" tem uma linha por pessoa, com venda e atendimento juntos' do
    close(card(sale, owner: bruno, value_cents: 10_000))
    close(card(service, owner: bruno), 'resolved')

    linhas = equipe[:quemCuidou][:linhas].select { |linha| linha[:nome] == 'Bruno' }

    expect(linhas.size).to eq(1)
    expect(linhas.first).to include(venda: include(fechou: 1), atende: include(resolveu: 1))
  end

  # Revisão do #1999, achado 1: o "a IA está esperando" conta só as conversas dos funis que quem abre vê no Números.
  it 'a IA esperando conta só as conversas de cliente num funil, como a caixa aberta pelo link' do
    [true, false].each do |no_funil|
      chat = conversation(assignee: ana)
      card(sale, owner: ana, conversation: chat) if no_funil
      passagem(chat, ana)
      chat.update!(waiting_since: 1.hour.ago)
    end

    expect(equipe[:proximo].find { |item| item[:tipo] == 'ia_esperando' }).to include(n: 1)
  end

  # Revisão 2 do #1999: a função sem a aba "Todas" (só Minhas e Não atribuídas) conta o que a caixa do link mostra:
  # a lista pede "todas" e o ConversationFinder corta pelas permissões de quem pede.
  it 'a IA esperando de quem só vê Minhas e Não atribuídas é o tamanho da lista que o link abre' do
    helena = create(:user, account: account, role: :agent, name: 'Helena', display_name: 'Helena')
    papel = create(:custom_role, account: account, permissions: %w[crm_view crm_view_reports conversation_unassigned_manage])
    helena.account_users.find_by(account: account).update!(custom_role: papel)
    create(:inbox_member, user: helena, inbox: inbox)
    [ana, nil, helena].each do |quem|
      chat = conversation(assignee: quem)
      card(sale, owner: ana, conversation: chat)
      passagem(chat, ana)
      chat.update!(waiting_since: 1.hour.ago)
    end

    numero = equipe(user: helena, dono: false)[:proximo].find { |item| item[:tipo] == 'ia_esperando' }[:n]
    lista = ConversationFinder.new(helena, ActionController::Parameters.new(
                                             Crm::Numeros::Equipe::LINK_IA_ESPERANDO.merge(assignee_type: 'all')
                                           )).perform[:conversations]

    expect(numero).to eq(2)
    expect(lista.size).to eq(numero)
  end

  # Achado 2: no teto do crédito a conta pode ter sido cortada; o número não abre a Lista, que mostraria outro conjunto.
  it 'fechadas abre a Lista quando ela bate, e não abre no teto do crédito' do
    2.times { close(card(sale, owner: ana, value_cents: 1000)) }

    expect(equipe[:vendendo][:itens].first).to include(tipo: 'fechadas', lista: true)
    stub_const('Crm::Numeros::Credito::MAX_CARDS', 2)
    expect(equipe[:vendendo][:itens].first).to include(tipo: 'fechadas', lista: false)
  end

  # Achado 3: a conversa ligada ao card pelo vínculo (crm_card_conversations) conta como a principal, uma vez só.
  it 'a IA conta a conversa vinculada ao card, e a ligada dos dois jeitos uma vez só' do
    vinculada = conversation
    ganho = card(sale, owner: ana, value_cents: 50_000)
    Crm::CardConversation.create!(account: account, card: ganho, conversation: vinculada)
    resposta_do_robo(vinculada)
    dupla = conversation
    outro = card(sale, owner: ana, conversation: dupla)
    Crm::CardConversation.create!(account: account, card: outro, conversation: dupla)
    resposta_do_robo(dupla)
    close(ganho)

    ia = equipe[:quemCuidou][:ia]

    expect(ia).to include(atendeu: 2, venda: { participou: 1, valor: 500.0 })
  end

  # Achado 4: a IA respondeu em setembro e a venda fechou em outubro: ela participou, então a linha dela aparece.
  it 'a IA aparece quando só participou de venda do mês, com a resposta de um mês antes' do
    chat = conversation
    resposta_do_robo(chat, quando: 40.days.ago)
    close(card(sale, owner: ana, conversation: chat, value_cents: 80_000))

    expect(equipe[:quemCuidou][:ia]).to include(atendeu: 0, venda: { participou: 1, valor: 800.0 })
  end

  # Achado 5: o topo soma tudo; a última linha (sem responsável ou fora da equipe) fecha a conta.
  it 'a soma das linhas de "Quem cuidou" bate com o topo, com quem saiu e sem responsável' do
    close(card(sale, owner: ana, value_cents: 100_000))
    close(card(sale, owner: bruno, value_cents: 50_000))
    close(card(sale, owner: nil, value_cents: 30_000))
    close(card(service, owner: carla), 'resolved')
    close(card(service, owner: bruno), 'resolved')
    account.account_users.find_by(user: bruno).destroy!

    result = equipe
    linhas = result[:quemCuidou][:linhas]
    fora = result[:quemCuidou][:foraDaEquipe]

    expect(linhas.sum { |linha| linha.dig(:venda, :fechou).to_i } + fora[:venda][:fechou]).to eq(result[:topo][:fechadas])
    expect(linhas.sum { |linha| linha.dig(:venda, :valor).to_f } + fora[:venda][:valor]).to eq(result[:topo][:feito])
    expect(linhas.sum { |linha| linha.dig(:atende, :resolveu).to_i } + fora[:atende][:resolveu])
      .to eq(result[:topo][:frase][:resolvidos])
    expect(fora).to eq(venda: { fechou: 2, valor: 800.0 }, atende: { resolveu: 1 })
  end

  it 'a linha de fora da equipe não diz "resolveu 0"' do
    close(card(sale, owner: nil, value_cents: 30_000))
    close(card(service, owner: carla), 'resolved')

    expect(equipe[:quemCuidou][:foraDaEquipe]).to eq(venda: { fechou: 1, valor: 300.0 })
  end

  it 'quem precisa de ajuda: a partir de 5 atrasos somados, com o motivo e sem posição' do
    5.times { card(sale, owner: bruno, next_follow_up_at: 1.day.ago) }
    4.times { card(sale, owner: ana, next_follow_up_at: 1.day.ago) }

    result = equipe

    expect(result[:ajuda]).to eq([{ pessoa: { id: bruno.id, nome: 'Bruno' }, retornos: 5, casosParados: 0, total: 5 }])
    expect(result[:topo][:frase]).to be_present
    expect(equipe(chave: '2026-09')[:ajuda]).to eq([])
  end

  it 'a lista de ajuda mostra até 3 pessoas, pela soma dos atrasos, e a frase conta todas' do
    { ana => 5, bruno => 7, carla => 7, admin => 8 }.each do |pessoa, n|
      n.times { card(sale, owner: pessoa, next_follow_up_at: 1.day.ago) }
    end

    result = equipe(pipelines: [sale])

    expect(result[:ajuda].map { |item| [item[:pessoa][:nome], item[:total]] }).to eq([['Marcos', 8], ['Bruno', 7], ['Carla', 7]])
    expect(result[:topo][:frase]).to include(tipo: 'equipe_vendas', ajuda: 4)
  end

  # #1999: a mesma pessoa não ocupa duas vagas; retornos e casos parados somam na mesma linha.
  it 'a ajuda tem uma linha por pessoa, com retornos e casos parados somados' do
    parado = { last_message_at: 10.days.ago, entered_stage_at: 10.days.ago }
    8.times { card(sale, owner: bruno, next_follow_up_at: 1.day.ago) }
    5.times { card(service, owner: bruno, **parado) }
    6.times { card(service, owner: carla, **parado) }
    5.times { card(sale, owner: ana, next_follow_up_at: 1.day.ago) }
    3.times { card(sale, owner: admin, next_follow_up_at: 1.day.ago) }
    2.times { card(service, owner: admin, **parado) }

    result = equipe

    expect(result[:ajuda].map { |item| [item[:pessoa][:nome], item[:retornos], item[:casosParados]] })
      .to eq([['Bruno', 8, 5], ['Carla', 0, 6], ['Ana', 5, 0]])
  end

  # A régua da linha (#1999): dono de card aberto ou movimento no mês. Guarda o encaixe com o Crm::Numeros::Papel (#1997),
  # que sem movimento daria "vende" a quem só enxerga o funil.
  it 'quem só enxerga o funil, sem card aberto nem movimento no mês, não tem linha' do
    inbox
    service
    close(card(sale, owner: ana, value_cents: 10_000))
    card(service, owner: bruno)

    expect(equipe[:quemCuidou][:linhas].map { |linha| [linha[:nome], linha.key?(:venda) ? :venda : :atende] })
      .to eq([['Ana', :venda], ['Bruno', :atende]])
  end

  it 'próximo passo: venda do mês sem responsável vira a faixa amarela; em modo leitura, nada de próximo nem botão' do
    won = card(sale, owner: nil, value_cents: 10_000)
    close(won)

    expect(equipe[:proximo]).to eq([{ tipo: 'sem_responsavel', n: 1, aviso: true }])
    leitura = equipe(dono: false, leitura: true)
    expect(leitura).to include(papel: 'leitura', proximo: [])
    expect(leitura[:topo][:botao]).to be_nil
  end

  it 'sem funil que a pessoa enxergue, a tela vazia' do
    sale

    expect(equipe(pipelines: [])).to include(vazio: true)
  end

  # #2075: sem `sales_value_view`, todo R$ some (vendido, meta, por pessoa, da IA) e as contagens ficam.
  it 'sem os valores de venda: contagens ficam, R$ e % da meta vêm vazios' do
    sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 2_000_000, 'currency' => 'BRL' } })
    close(card(sale, owner: ana, value_cents: 620_000))
    chat = conversation(assignee: ana)
    resposta_do_robo(chat)
    close(card(sale, owner: bruno, conversation: chat, value_cents: 100_000))
    card(sale, owner: ana, value_cents: 50_000, entered_stage_at: 30.days.ago)

    result = equipe(user: ana, dono: false, pipelines: [sale], valor: false)

    expect(result).to include(valorOculto: true)
    expect(result[:topo]).to include(feito: nil, meta: nil, fechadas: 2)
    expect(result[:topo][:frase]).to include(feito: nil, meta: nil)
    expect(result[:vendendo][:itens].first).to include(tipo: 'fechadas', n: 2, valor: nil)
    expect(result[:quemCuidou][:linhas].map { |linha| linha[:venda] }).to all(include(valor: nil, meta: nil, pct: nil))
    expect(result[:quemCuidou][:ia][:venda]).to eq(participou: 1, valor: nil)
    expect(result[:quemCuidou][:caminhoCerto]).to eq([])
  end
end
