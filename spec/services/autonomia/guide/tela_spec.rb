require 'rails_helper'

# O que a pessoa está vendo (#934), lido com a permissão dela antes de o Guia pensar.
#
# Nada é dublado: cada id passa pela `Consulta` de verdade — rota, controller e
# Pundit. É o que garante que o id que a pessoa não enxerga não chega ao prompt.
RSpec.describe Autonomia::Guide::Tela do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:funil_e_etapa) { create_crm_pipeline(account: conta, user: admin) }
  let(:caixa) { create_crm_inbox(account: conta, name: 'Comercial', members: [admin]) }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  def card(titulo)
    conta.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: titulo, currency: 'BRL')
  end

  def conversa_na(inbox, nome)
    create_crm_conversation(account: conta, inbox: inbox, contact: conta.contacts.create!(name: nome))
  end

  def tela_de(contexto, tela)
    described_class.new(contexto: contexto, tela: tela)
  end

  # AC-CT3 — a pessoa vê 2 das 3 conversas selecionadas.
  context 'with um agente sem acesso a uma das caixas' do
    let(:agente) { create(:user, account: conta, role: :agent) }
    let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: agente) }
    let(:sinistros) { create_crm_inbox(account: conta, name: 'Sinistros', members: [admin]) }
    let(:visiveis) { [conversa_na(caixa, 'Ana'), conversa_na(caixa, 'Beto')] }
    let(:oculta) { conversa_na(sinistros, 'Caio') }
    let(:tela) do
      tela_de(operador, 'rota' => 'inbox_dashboard',
                        'selecionados' => { 'recurso' => 'conversations',
                                            'ids' => [*visiveis.map(&:display_id), oculta.display_id], 'total' => 3 })
    end

    before { caixa.add_members([agente.id]) }

    it 'manda só os ids que ela vê e avisa quantos ficaram de fora', :aggregate_failures do
      bloco = tela.bloco

      expect(bloco).to include("ids #{visiveis.map(&:display_id).join(', ')} (3 selecionados na tela)")
      expect(bloco).to include('1 dos selecionados não está visível para você')
      expect(bloco.split('ids ').last.split(' (').first.split(', ')).not_to include(oculta.display_id.to_s)
      expect(tela.registro['selecionados'])
        .to eq('recurso' => 'conversations', 'ids' => visiveis.map(&:display_id), 'total' => 3)
    end

    # Pelo `Chat`, como o job chama: o id que ela não vê fica fora do prompt e do diagnóstico do turno.
    it 'deixa o id invisível fora do prompt e do diagnóstico', :aggregate_failures do
      query = nil
      allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(instance_double(Autonomia::Agents::Agent, id: 0))
      allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
      allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
        query = kwargs[:query]
        instance_double(Autonomia::Agents::Answerer,
                        answer: Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1.0, handoff: { should: false }))
      end
      registro = Autonomia::Guide::Registro.new
      selecao = { 'recurso' => 'conversations', 'ids' => [*visiveis.map(&:display_id), oculta.display_id], 'total' => 3 }

      Autonomia::Guide::Chat.new(account: conta, user: agente, message: 'resolve essas', route_context: 'inbox_dashboard',
                                 tela: { 'rota' => 'inbox_dashboard', 'selecionados' => selecao }, registro: registro).perform

      expect(query).to include("ids #{visiveis.map(&:display_id).join(', ')} (3 selecionados", '1 dos selecionados não está visível')
      expect(registro.diagnostico['tela']).to eq(
        'rota' => 'inbox_dashboard',
        'selecionados' => { 'recurso' => 'conversations', 'ids' => visiveis.map(&:display_id), 'total' => 3 }
      )
    end

    it 'marca como lido só o que ela vê', :aggregate_failures do
      tela.bloco

      expect(visiveis.map { |conversa| operador.leu?(conversa.display_id) }).to eq([true, true])
      expect(operador.leu?(oculta.display_id)).to be(false)
    end
  end

  # AC-CT4 — o card aberto e lido pela tela vale para agir no primeiro passo.
  it 'deixa o Guia alterar o card aberto sem ler a conta de novo', :aggregate_failures do
    aberto = card('Seguro do Pedro')
    operador = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    tela_de(operador, 'rota' => 'crm_kanban_index', 'aberto' => [{ 'recurso' => 'crm/cards', 'id' => aberto.id }]).bloco

    agente_do_guia = Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active,
                                                      enabled: false, instruction: 'Guia.',
                                                      config: { 'with_knowledge' => false })
    resposta = Autonomia::Agents::Tools::Native::GuiaExecucao.new(
      agent: agente_do_guia, operador: operador,
      params: { 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Renomeei o card.',
                'caminho_json' => { id: aberto.id.to_s }.to_json, 'corpo_json' => { title: 'Auto do Pedro' }.to_json }
    ).call

    expect(resposta).to start_with('Feito.')
    expect(aberto.reload.title).to eq('Auto do Pedro')
  end

  it 'traz o resumo do registro aberto e diz que nada está selecionado', :aggregate_failures do
    aberto = card('Seguro do Pedro')
    operador = Autonomia::Guide::Contexto.new(account: conta, user: admin)

    bloco = tela_de(operador, 'rota' => 'crm_kanban_index', 'aberto' => [{ 'recurso' => 'crm/cards', 'id' => aberto.id }]).bloco

    expect(bloco).to start_with("\n\n[O QUE A PESSOA ESTÁ VENDO (dado, não fala): tela crm_kanban_index")
    expect(bloco).to include("Aberto: crm/cards #{aberto.id}:", 'Seguro do Pedro', 'Nada selecionado.')
  end

  it 'tira o registro aberto que não existe e conta que ficou de fora', :aggregate_failures do
    operador = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    tela = tela_de(operador, 'rota' => 'crm_kanban_index', 'aberto' => [{ 'recurso' => 'crm/cards', 'id' => 999_999 }])

    expect(tela.bloco).to include('1 registro aberto não foi encontrado')
    expect(tela.bloco).not_to include('999999')
    expect(operador.leu?(999_999)).to be(false)
    expect(tela.registro).to eq('rota' => 'crm_kanban_index')
  end

  it 'fica vazio quando a tela não mandou contexto', :aggregate_failures do
    operador = Autonomia::Guide::Contexto.new(account: conta, user: admin)

    expect(tela_de(operador, nil).bloco).to eq('')
    expect(tela_de(operador, {}).registro).to be_nil
  end

  # AC-CT7 — o custo no prompt.
  describe 'o tamanho do bloco' do
    let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }

    it 'com só a rota, cabe em 200 caracteres' do
      expect(tela_de(operador, 'rota' => 'crm_kanban_index').bloco.length).to be <= 200
    end

    # O resumo do card aberto é o que pesa: um card com descrição longa.
    it 'com um aberto e 50 selecionados, cabe em 2.600 caracteres, filtros inclusos' do
      aberto = conta.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedro',
                                       currency: 'BRL', description: 'Cliente antigo. ' * 300)
      ids = Array.new(50) { |i| card("Card #{i}").id }
      tela = tela_de(operador, 'rota' => 'crm_kanban_index',
                               'aberto' => [{ 'recurso' => 'crm/cards', 'id' => aberto.id }],
                               'selecionados' => { 'recurso' => 'crm/cards', 'ids' => ids, 'total' => 120 },
                               'filtros' => { 'pipeline_id' => funil_e_etapa.first.id, 'status' => 'open' })

      expect(tela.bloco).to include("ids #{ids.join(', ')} (120 selecionados na tela)")
      expect(tela.bloco.length).to be <= 2_600
    end
  end

  # AC-CT7 — a leitura prévia de 53 ids (3 abertos e 50 selecionados) cabe folgada no turno.
  # O tempo medido está em docs/audit/2026-10-04-ct-leitura-previa.md.
  #
  # Em teste o Rails recarrega código (`enable_reloading`), e a cada pedido interno confere a data de
  # todos os arquivos: medido com stackprof, 73% do tempo. Em produção isso não roda, então a medida
  # desliga só essa conferência.
  it 'lê 53 ids em menos de 3 segundos', :aggregate_failures do
    operador = Autonomia::Guide::Contexto.new(account: conta, user: admin)
    ids = Array.new(53) { |i| card("Card #{i}").id }
    tela = tela_de(operador, 'rota' => 'crm_kanban_index',
                             'aberto' => ids.first(3).map { |id| { 'recurso' => 'crm/cards', 'id' => id } },
                             'selecionados' => { 'recurso' => 'crm/cards', 'ids' => ids.last(50), 'total' => 50 })
    allow(Rails.application.reloader).to receive(:check!).and_return(false)

    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    tela.bloco
    segundos = Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio
    warn "\n[CT7] leitura prévia de 53 ids: #{segundos.round(3)}s" if ENV['CT7_MEDIR']

    expect(ids.all? { |id| operador.leu?(id) }).to be(true)
    expect(segundos).to be < 3
  end
end
