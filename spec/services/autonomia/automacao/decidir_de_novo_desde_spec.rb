require 'rails_helper'

# G46 (exemplo 14, o laço dos documentos): o "decidir" com `de_novo.desde`. O caminho marcado roda os passos dele e
# volta ao "esperar até" de antes, que espera o próximo documento; o caminho vazio volta direto. A prova ponta a ponta,
# montada pela API da tela, fica em spec/fechamento/automacao/exemplo_14_documentacao_spec.rb; aqui ficam as bordas: a
# volta, o caminho vazio, a rajada durante a ida à IA e as conferências do salvar.
RSpec.describe Autonomia::Automacao::DecidirDeNovo, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Dona Cida') }
  let(:marcos) { create(:contact, account: account, name: 'Marcos') }
  let(:conversa) { create(:conversation, account: account, contact: marcos, status: :open) }
  let(:corpos) { [] }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  after { Current.reset }

  # A OpenAI devolve, em ordem, o caminho de cada item (o último se repete). Um Proc roda antes de responder (o que
  # chega enquanto a IA pensa) e devolve o caminho.
  def ia_escolhe(*escolhas)
    fila = escolhas.dup
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      atual = fila.size > 1 ? fila.shift : fila.first
      atual = atual.call if atual.is_a?(Proc)
      payload = { id: "resp_#{corpos.size}", output_text: { 'caminho' => atual, 'motivo' => 'Pelo documento.' }.to_json,
                  usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def documento_chegou = { 'campo' => { '$valor' => 'conversa.cliente_mandou_documento' }, 'op' => 'igual', 'valor' => true }

  def espera(condicao = documento_chegou)
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => condicao, 'prazo' => { 'valor' => 2, 'unidade' => 'dias' },
      'se_vencer' => [{ 'id' => 'fim', 'tipo' => 'parar' }] }
  end

  def caminho(nome, chave, passos = [])
    { 'nome' => nome, 'chave' => chave, 'descricao' => "quando é #{nome}", 'passos' => passos }
  end

  def decide(desde: 'espera', marcados: %w[falta_algo ilegivel nenhum])
    { 'id' => 'decide', 'tipo' => 'decidir', 'le' => %w[mensagens_recentes anexos], 'pergunta' => 'O que chegou?',
      'caminhos' => [caminho('Falta algo', 'falta_algo', [prioridade_passo('pede', 'high')]), caminho('Ilegível', 'ilegivel'),
                     caminho('Tudo recebido', 'tudo_recebido', [prioridade_passo('ok', 'low')])],
      'nenhum' => [], 'de_novo' => { 'caminhos' => marcados, 'desde' => desde } }
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def foto(nome = 'cnh.png')
    mensagem = conversa.messages.new(account: account, inbox: conversa.inbox, message_type: :incoming, sender: marcos, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :image)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: nome, content_type: 'image/png', identify: false)
    mensagem.tap(&:save!)
  end

  def manda_foto(nome = 'cnh.png')
    mensagem = foto(nome)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
  end

  def comecar_e_rodar
    definicao = automacao_ligada(account, admin, [espera, decide])
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado)

  def ramos(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'decide').order(:id).map { |item| item.dados['ramo'] }

  it '"falta algo" roda o caminho e volta a esperar o próximo documento; "tudo recebido" segue', :aggregate_failures do
    ia_escolhe('falta_algo', 'tudo_recebido')
    execucao = comecar_e_rodar

    travel(3.hours) { manda_foto }
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera])
    expect(execucao.due_at).to be_within(1.minute).of(3.hours.from_now + 2.days)
    expect(conversa.reload.priority).to eq('high')
    expect(registros(execucao)).to eq([%w[espera ok], %w[espera ok], %w[decide ok], %w[pede ok], %w[espera ok]])
    expect(conversa.messages.where(private: true)).to be_empty

    travel(5.hours) { manda_foto('crlv.png') }
    expect(execucao.reload.estado).to eq('concluida')
    expect(ramos(execucao)).to eq(%w[falta_algo tudo_recebido])
    expect(conversa.reload.priority).to eq('low')
  end

  it 'o caminho vazio ("ilegível", "nenhum") volta direto ao "esperar até"', :aggregate_failures do
    ia_escolhe('ilegivel', 'nenhum')
    execucao = comecar_e_rodar

    travel(1.hour) { manda_foto }
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera])
    travel(2.hours) { manda_foto }
    expect([execucao.reload.estado, execucao.cursor, corpos.size]).to eq(['esperando', 'espera', 2])
    expect(ramos(execucao)).to eq(%w[ilegivel nenhum])
  end

  # A 2ª e a 3ª foto chegam enquanto a IA lê a 1ª: a execução está andando, e ninguém a acorda. A volta ao mesmo
  # "esperar até" na mesma rodada começa quando ele foi cumprido, e as duas contam: a IA decide de novo, sem esperar.
  it 'a rajada que chega enquanto a IA pensa não se perde: o laço roda de novo na mesma rodada', :aggregate_failures do
    rajada = lambda do
      # O relógio do spec está parado: as duas chegam 1 segundo depois, enquanto a IA lê.
      2.times { |i| foto("foto-#{i}.png").update_column(:created_at, 1.second.from_now) } # rubocop:disable Rails/SkipsModelValidations
      'falta_algo'
    end
    ia_escolhe(rajada, 'tudo_recebido')
    execucao = comecar_e_rodar

    travel(1.hour) { manda_foto }

    expect(corpos.size).to eq(2)
    expect(ramos(execucao)).to eq(%w[falta_algo tudo_recebido])
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'sem documento no prazo, sai pelo "se vencer" do "esperar até"', :aggregate_failures do
    ia_escolhe('falta_algo')
    execucao = comecar_e_rodar
    travel(1.hour) { manda_foto }

    travel(1.hour + 2.days + 1.minute) { varrer }

    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao).last(2)).to eq([%w[espera pulado], %w[fim ok]])
    expect(corpos.size).to eq(1)
  end

  describe 'o salvar' do
    def problemas(passos)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    it 'aceita o laço do exemplo, com passos no caminho que volta e a resposta do cliente no lugar do documento', :aggregate_failures do
      respondeu = { 'campo' => { '$valor' => 'conversa.cliente_respondeu' }, 'op' => 'igual', 'valor' => true }

      expect(problemas([espera, decide])).to be_empty
      expect(problemas([espera('todas' => [respondeu, documento_chegou]), decide])).to be_empty
    end

    it 'recusa o desde que não existe, que não é um "esperar até" de antes ou que não espera o cliente', :aggregate_failures do
      expect(problemas([espera, decide(desde: 'sumiu')]))
        .to eq(['Step decide: "go back to wait" points to a step this automation doesn\'t have (sumiu).'])
      nao_anterior = 'Step decide: "go back to wait" must be a "wait until" that comes before this step, in the same list'
      expect(problemas([decide, espera]).sole).to start_with(nao_anterior)
      expect(problemas([prioridade_passo('antes'), espera, decide(desde: 'antes')]).sole).to start_with(nao_anterior)
      dentro = espera.merge('se_vencer' => [espera.merge('id' => 'espera2', 'se_vencer' => [])])
      expect(problemas([dentro, decide(desde: 'espera2')]).sole).to start_with(nao_anterior)
      equipe = { 'campo' => { '$valor' => 'conversa.equipe_respondeu' }, 'op' => 'igual', 'valor' => true }
      diferente = documento_chegou.merge('op' => 'diferente')
      [equipe, diferente, { 'alguma' => [documento_chegou, equipe] }].each do |condicao|
        expect(problemas([espera(condicao), decide]).sole).to start_with('Step decide: the "wait until" espera must wait for the customer')
      end
    end
  end
end
