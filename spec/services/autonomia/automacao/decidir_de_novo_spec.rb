require 'rails_helper'

# G31 do fechamento do #2414 (exemplo 2, passo 6: "a cada resposta da Ana, a IA decide"). O "decidir" com `de_novo`:
# quando a IA escolhe "ainda conversando", a execução espera a próxima resposta do cliente e decide de novo. A prova
# ponta a ponta, montada pela API da tela, fica em spec/fechamento/automacao/g31_decidir_a_cada_resposta_spec.rb; aqui
# ficam as bordas: a rajada durante a ida à IA, o prazo vencido, a caixa que quem ligou não vê, a nova tentativa e o
# salvar.
RSpec.describe Autonomia::Automacao::DecidirDeNovo, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Márcio') }
  let(:ana) { create(:contact, account: account, name: 'Ana') }
  let(:conversa) { create(:conversation, account: account, contact: ana, status: :open) }
  let(:corpos) { [] }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Qual o valor do condomínio?')
  end

  after { Current.reset }

  # A OpenAI devolve, em ordem, o caminho de cada item (o último se repete); um número é o status do erro. Um Proc roda
  # antes de responder (a mensagem que chega enquanto a IA pensa) e devolve o caminho.
  def ia_escolhe(*escolhas)
    fila = escolhas.dup
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      atual = fila.size > 1 ? fila.shift : fila.first
      atual = atual.call if atual.is_a?(Proc)
      erro = { status: atual, body: { error: { message: 'falhou' } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      next erro if atual.is_a?(Integer)

      payload = { id: "resp_#{corpos.size}", output_text: { 'caminho' => atual, 'motivo' => 'Pela conversa.' }.to_json,
                  usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def caminho(nome, chave, passos = [])
    { 'nome' => nome, 'chave' => chave, 'descricao' => "quando é #{nome}", 'passos' => passos }
  end

  # O passo 6 do exemplo 2, com um marcador no lugar do link da agenda (G12) e as 24 horas decididas pelo Rodrigo (09/11).
  def decide(prazo = { 'valor' => 24, 'unidade' => 'horas' })
    { 'id' => 'decide', 'tipo' => 'decidir', 'le' => %w[mensagens_recentes], 'pergunta' => 'O que a Ana quer?',
      'caminhos' => [caminho('Quer visitar', 'quer_visitar', [prioridade_passo('visita')]), caminho('Só curiosidade', 'so_curiosidade'),
                     caminho('Ainda conversando', 'ainda_conversando')],
      'de_novo' => { 'caminhos' => ['ainda_conversando'], 'prazo' => prazo } }
  end

  def comecar_e_rodar(definicao = automacao_ligada(account, admin, [decide]))
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def escreve(alvo = conversa, **atributos)
    mensagem = create(:message, account: account, conversation: alvo, inbox: alvo.inbox, **atributos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
    mensagem
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  # Os caminhos que a IA escolheu, em ordem (a tentativa que falhou não tem caminho).
  def ramos(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'decide').order(:id).filter_map { |item| item.dados['ramo'] }

  it '"ainda conversando" espera a próxima resposta a partir da leitura, sem nota, sem seguir pelo caminho', :aggregate_failures do
    ia_escolhe('ainda_conversando')

    antes = Time.current
    execucao = comecar_e_rodar

    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando decide])
    expect(execucao.due_at).to be_between(24.hours.since(antes), 24.hours.from_now)
    expect(registros(execucao)).to eq([['decide', 'ok', nil]])
    expect(ramos(execucao)).to eq(['ainda_conversando'])
    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao).dados.keys).not_to include('nota_id', 'nota_faltou')
    expect(conversa.messages.where(private: true)).to be_empty
  end

  it 'a resposta de quem atende (a agente de IA) acorda, mas volta a esperar com o mesmo prazo, sem chamar a IA', :aggregate_failures do
    ia_escolhe('ainda_conversando')
    execucao = comecar_e_rodar
    prazo = execucao.due_at

    travel(5.minutes) { escreve(message_type: :outgoing, sender: create(:agent_bot, account: account), content: 'R$ 600,00.') }

    expect([execucao.reload.estado, execucao.cursor, execucao.due_at]).to eq(['esperando', 'decide', prazo])
    expect(corpos.size).to eq(1)
  end

  it 'a resposta do cliente decide de novo, e o caminho escolhido segue com a nota só nesta volta', :aggregate_failures do
    ia_escolhe('ainda_conversando', 'quer_visitar')
    execucao = comecar_e_rodar

    travel(10.minutes) { escreve(message_type: :incoming, sender: ana, content: 'Quero visitar sábado') }

    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao)).to eq([['decide', 'ok', nil], ['decide', 'ok', nil], ['visita', 'ok', nil]])
    expect(ramos(execucao)).to eq(%w[ainda_conversando quer_visitar])
    expect(conversa.reload.priority).to eq('urgent')
    expect(conversa.messages.where(private: true).count).to eq(1)
    expect(corpos.size).to eq(2)
  end

  it 'a rajada que chega enquanto a IA pensa decide de novo na mesma rodada, sem ficar presa esperando', :aggregate_failures do
    rajada = lambda do
      2.times { |i| create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: "e #{i}") }
      'ainda_conversando'
    end
    ia_escolhe(rajada, 'ainda_conversando')

    execucao = comecar_e_rodar

    expect(corpos.size).to eq(2)
    expect(ramos(execucao)).to eq(%w[ainda_conversando ainda_conversando])
    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando decide])
  end

  # A janela é pelo id da mensagem, não pela hora (revisão do #2800): a gravada depois da leitura, com `created_at` de
  # antes do marco, não some.
  it 'a mensagem gravada durante a ida à IA, com a hora de antes da leitura, decide de novo', :aggregate_failures do
    atrasada = lambda do
      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'E o IPTU?',
                       created_at: 5.minutes.ago)
      'ainda_conversando'
    end
    ia_escolhe(atrasada, 'ainda_conversando')

    execucao = comecar_e_rodar

    expect(corpos.size).to eq(2)
    expect(ramos(execucao)).to eq(%w[ainda_conversando ainda_conversando])
    expect(Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'decide').order(:id).map { |item| item.dados['lido_ate'] })
      .to eq(conversa.messages.incoming.reorder(:id).pluck(:id).first(2))
  end

  # Revisão do #2800: o id reservado antes da leitura e visível só depois (commit atrasado) fica abaixo do marco; a
  # margem de segundos antes da leitura o pega, sem recontar o que a IA já leu.
  def id_reservado = Message.connection.select_value("SELECT nextval('messages_id_seq')")

  it 'a mensagem com id reservado antes da leitura e visível só depois decide de novo', :aggregate_failures do
    reservado = id_reservado
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'E a vaga na garagem?')
    atrasada = lambda do
      create(:message, id: reservado, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                       content: 'E o IPTU?', created_at: 3.seconds.ago)
      'ainda_conversando'
    end
    ia_escolhe(atrasada, 'ainda_conversando')

    execucao = comecar_e_rodar

    expect(reservado).to be < Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'decide').order(:id).first.dados['lido_ate']
    expect(corpos.size).to eq(2)
    expect(ramos(execucao)).to eq(%w[ainda_conversando ainda_conversando])
  end

  it 'a mensagem que a IA já leu, gravada na margem antes da leitura, não decide de novo', :aggregate_failures do
    lida = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Tem vaga?', created_at: 2.seconds.ago)
    ia_escolhe('ainda_conversando')

    execucao = comecar_e_rodar

    expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao).dados['lidas_na_margem']).to include(lida.id)
    expect(corpos.size).to eq(1)
    expect([execucao.estado, execucao.cursor]).to eq(%w[esperando decide])
  end

  it 'na espera, a mensagem com id reservado antes da leitura acorda e decide de novo' do
    reservado = id_reservado
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'E a vaga na garagem?')
    ia_escolhe('ainda_conversando', 'quer_visitar')
    execucao = comecar_e_rodar

    escreve(id: reservado, message_type: :incoming, sender: ana, content: 'Quero visitar', created_at: 1.second.ago)

    expect(ramos(execucao.reload)).to eq(%w[ainda_conversando quer_visitar])
  end

  it 'na espera, a resposta com a hora de antes da leitura acorda e decide de novo', :aggregate_failures do
    ia_escolhe('ainda_conversando', 'quer_visitar')
    execucao = comecar_e_rodar

    travel(10.minutes) { escreve(message_type: :incoming, sender: ana, content: 'Quero visitar', created_at: 1.hour.ago) }

    expect(ramos(execucao.reload)).to eq(%w[ainda_conversando quer_visitar])
    expect(execucao.estado).to eq('concluida')
  end

  # Decisão do Rodrigo (09/11): 24 horas de silêncio encerram sem mandar nada. Os passos depois do "decidir" não rodam.
  it 'sem resposta em 24 horas, a execução acaba sem mandar nada e o passo depois do decidir não roda', :aggregate_failures do
    ia_escolhe('ainda_conversando')
    execucao = comecar_e_rodar(automacao_ligada(account, admin, [decide, mensagem_passo('depois', 'Ainda está aí?')]))
    enviadas = conversa.messages.where(message_type: :outgoing).count

    travel(23.hours + 59.minutes) { varrer }
    expect(execucao.reload.estado).to eq('esperando')

    travel(24.hours + 1.minute) { varrer }

    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao)).to eq([['decide', 'ok', nil], %w[decide pulado prazo_vencido]])
    expect(conversa.messages.where(message_type: :outgoing).count).to eq(enviadas)
    expect(corpos.size).to eq(1)
  end

  # Parecer da Funções no #2689 (G11): a resposta numa caixa que quem ligou não abre não decide.
  it 'a resposta numa caixa que quem ligou não vê não decide de novo', :aggregate_failures do
    atendente = create(:user, account: account, role: :agent)
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
    atendente.account_users.find_by(account: account).update!(custom_role: funcao)
    conversa.inbox.add_members([atendente.id])
    outra = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: ana)
    ia_escolhe('ainda_conversando', 'quer_visitar')
    execucao = comecar_e_rodar(automacao_ligada(account, atendente, [decide]))
    expect(execucao.estado).to eq('esperando')

    travel(10.minutes) { escreve(outra, message_type: :incoming, sender: ana, content: 'Quero visitar') }

    expect([execucao.reload.estado, corpos.size]).to eq(['esperando', 1])
  end

  it 'o erro passageiro da IA tenta de novo sem pedir outra resposta, e a mensagem nova não o adianta', :aggregate_failures do
    ia_escolhe('ainda_conversando', 503, 'quer_visitar')
    execucao = comecar_e_rodar

    travel(10.minutes) { escreve(message_type: :incoming, sender: ana, content: 'Quero visitar') }
    expect([execucao.reload.estado, execucao.tentativas]).to eq(['esperando', 1])

    travel(11.minutes) { escreve(message_type: :incoming, sender: ana, content: 'Oi?') }
    expect([execucao.reload.tentativas, corpos.size]).to eq([1, 2])

    travel(12.minutes) { varrer }

    expect(execucao.reload.estado).to eq('concluida')
    expect(ramos(execucao)).to eq(%w[ainda_conversando quer_visitar])
  end

  it 'no ensaio, o caminho que decide de novo não roda passo nenhum: vencido o prazo, encerra' do
    roteiro = Autonomia::Automacao::Roteiro.new({ 'passos' => [decide, prioridade_passo('depois')] })
    ramos = described_class.ramos_do_ensaio(decide, roteiro) { |primeiro| [primeiro&.fetch('id')] }

    expect(ramos).to eq([{ chave: 'quer_visitar', nome: 'Quer visitar', passos: ['visita'] },
                         { chave: 'so_curiosidade', nome: 'Só curiosidade', passos: ['depois'] },
                         { chave: 'ainda_conversando', nome: 'Ainda conversando', de_novo: true, passos: [] },
                         { chave: 'nenhum', passos: ['depois'] }])
  end

  describe 'o salvar' do
    def problemas(passo)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    it 'aceita o passo do exemplo e o "nenhum" vazio que decide de novo' do
      passo = decide.deep_merge('de_novo' => { 'caminhos' => %w[ainda_conversando nenhum] })

      expect(problemas(passo)).to be_empty
    end

    it 'aceita todos os caminhos marcados com o "nenhum" livre: ele é a saída' do
      todos = decide.merge('caminhos' => decide['caminhos'].map { |item| item.merge('passos' => []) })
                    .deep_merge('de_novo' => { 'caminhos' => %w[quer_visitar so_curiosidade ainda_conversando] })

      expect(problemas(todos)).to be_empty
    end

    it 'recusa a chave que o passo não tem, o caminho com passos e todas as saídas marcadas', :aggregate_failures do
      expect(problemas(decide.deep_merge('de_novo' => { 'caminhos' => %w[ainda_conversando sumiu] })))
        .to eq(['Step decide: "decide again" points to a path this step doesn\'t have (sumiu).'])
      expect(problemas(decide.deep_merge('de_novo' => { 'caminhos' => %w[quer_visitar] })))
        .to eq(['Step decide: the path Quer visitar decides again, so it can\'t have steps. Remove its steps or unmark it.'])
      expect(problemas(decide.merge('nenhum' => [prioridade_passo('n1')]).deep_merge('de_novo' => { 'caminhos' => %w[nenhum] })))
        .to eq(['Step decide: the path None applies decides again, so it can\'t have steps. Remove its steps or unmark it.'])
      todos = decide.merge('caminhos' => decide['caminhos'].map { |item| item.merge('passos' => []) })
                    .deep_merge('de_novo' => { 'caminhos' => %w[quer_visitar so_curiosidade ainda_conversando nenhum] })
      expect(problemas(todos)).to eq(['Step decide: leave at least one way out unmarked (a path or "None applies"), so the automation can move on.'])
    end
  end
end
