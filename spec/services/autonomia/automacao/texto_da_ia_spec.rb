require 'rails_helper'

# #2679 (lote 2, item c): o texto que o "escrever" e o "resumir" produzem fica na execução, e um passo seguinte o lê
# como `{"$valor": "ia.<passo>"}`. Fora da janela ele sai dentro do modelo aprovado; o "mesmo resumo" não vai outra vez
# à IA. A IA é a OpenAI simulada no HTTP; a Graph também.
RSpec.describe 'Texto da IA entre passos', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Ana', phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: '5511937016094') }
  let(:conversa) { create(:conversation, inbox: canal.inbox, contact: contato, contact_inbox: contact_inbox, account: account) }
  let(:corpos) { [] }
  let(:pedidos) { [] }
  let(:escrever) { { 'id' => 'p1', 'tipo' => 'escrever', 'instrucao' => 'Pergunte como ela está', 'destino' => 'guardar' } }
  let(:texto_da_ia) { 'Oi Ana, tudo bem com você depois do procedimento?' }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:inbox_member, user: admin, inbox: canal.inbox)
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' }).to_return do |pedido|
      pedidos << JSON.parse(pedido.body)
      { status: 200, body: { messages: [{ id: 'wamid.AUTOMACAO' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    canal.update!(message_templates: [{ 'name' => 'retomar', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Olá! {{1}}' }] }])
  end

  after { Current.reset }

  def openai_devolve(resposta)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: resposta.to_json, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def rodar(*passos)
    automacao = automacao_ligada(account, admin, passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def recebida(quando)
    create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, content: 'Fiz o botox ontem',
                     source_id: "in-#{SecureRandom.hex(3)}", created_at: quando)
  end

  def mandada = conversa.messages.outgoing.where(private: false).last

  def mensagem_do_texto(id = 'p2', modelo: nil)
    passo = mensagem_passo(id, { '$valor' => 'ia.p1' })
    modelo ? passo.merge('modelo' => { 'nome' => 'retomar', 'idioma' => 'pt_BR', 'variaveis' => [[{ '$valor' => 'ia.p1' }]] }) : passo
  end

  it 'fora da janela, o texto da IA sai dentro do modelo aprovado, até a Graph', :aggregate_failures do
    recebida(30.hours.ago)
    openai_devolve('texto' => texto_da_ia)

    execucao = rodar(escrever, mensagem_do_texto(modelo: true))

    expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p2', 'ok', nil]])
    expect(mandada.content).to eq("Olá! #{texto_da_ia}")
    SendReplyJob.perform_now(mandada.id)
    expect(pedidos.last.dig('template', 'name')).to eq('retomar')
    expect(pedidos.last.to_json).to include(texto_da_ia)
  end

  it 'fora da janela, o texto da IA que estoura os 1024 caracteres do modelo para antes da Graph', :aggregate_failures do
    recebida(30.hours.ago)
    openai_devolve('texto' => 'a' * 1020)

    execucao = rodar(escrever, mensagem_do_texto(modelo: true))

    expect(registros(execucao)).to eq([['p1', 'ok', nil], %w[p2 falhou modelo_texto_longo]])
    expect(execucao.reload.estado).to eq('parada')
    expect(mandada).to be_nil
    expect(pedidos).to be_empty
  end

  it 'fora da janela, o texto da IA que cabe exato nos 1024 caracteres sai pelo modelo', :aggregate_failures do
    recebida(30.hours.ago)
    openai_devolve('texto' => 'a' * 1020)
    canal.update!(message_templates: [{ 'name' => 'retomar', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}' }] }])

    execucao = rodar(escrever, mensagem_do_texto(modelo: true))

    expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p2', 'ok', nil]])
    expect(mandada.content.length).to eq(1024)
  end

  it 'dentro da janela, o mesmo texto vai direto, sem o modelo', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('texto' => texto_da_ia)

    execucao = rodar(escrever, mensagem_do_texto(modelo: true))

    expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p2', 'ok', nil]])
    expect(mandada.content).to eq(texto_da_ia)
  end

  it 'o texto fica entre rodadas: depois de esperar um dia, o passo seguinte ainda o lê', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('texto' => texto_da_ia)

    execucao = rodar(escrever, esperar_passo('e1'), mensagem_do_texto('p3'))
    expect(execucao.reload.textos).to eq('p1' => texto_da_ia)
    travel 25.hours do
      recebida(1.hour.ago)
      varrer
    end

    expect(registros(execucao).last).to eq(['p3', 'ok', nil])
    expect(mandada.content).to eq(texto_da_ia)
    expect(corpos.size).to eq(1)
  end

  it 'o "mesmo resumo": o aviso seguinte manda o resumo guardado, sem outra ida à IA', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('resumo' => 'Cliente quer remarcar a manutenção.')
    resumir = { 'id' => 'p1', 'tipo' => 'resumir', 'destino' => 'nota' }
    aviso = avisar_passo('p2', { 'pessoas' => [admin.id] }, 'De novo: ', { '$valor' => 'ia.p1' })

    execucao = rodar(resumir, aviso)

    expect(registros(execucao)).to eq([['p1', 'ok', nil], ['p2', 'ok', nil]])
    expect(corpos.size).to eq(1)
    expect(conversa.messages.where(private: true).last.content).to include('De novo: Cliente quer remarcar a manutenção.')
  end

  it 'quando a execução termina, o texto some', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('texto' => texto_da_ia)

    execucao = rodar(escrever, mensagem_do_texto)

    expect(execucao.reload.estado).to eq('concluida')
    expect(execucao.textos).to eq({})
  end

  it 'antes do passo de IA rodar, o valor está vazio e o passo pula com faltou_valor', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('texto' => texto_da_ia)

    execucao = rodar(mensagem_do_texto('p0'), escrever)

    expect(registros(execucao).first).to eq(%w[p0 pulado faltou_valor])
  end

  it 'o texto nunca vai para o log nem para o registro', :aggregate_failures do
    recebida(1.hour.ago)
    openai_devolve('texto' => texto_da_ia)
    log = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log))

    execucao = rodar(escrever, mensagem_do_texto)

    expect(log.string).not_to include(texto_da_ia)
    expect(Autonomia::Automacao::Registro.where(execucao: execucao).to_json).not_to include(texto_da_ia)
  end

  describe 'ao salvar' do
    def problemas(*passos)
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user: admin)).problemas
    end

    it 'aceita o texto de um "escrever" ou "resumir" da receita' do
      expect(problemas(escrever, mensagem_do_texto)).to be_empty
    end

    it 'recusa o texto da IA no "Só se" do gatilho, onde nenhum passo rodou' do
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida',
                                 'filtros' => [{ 'campo' => { '$valor' => 'ia.p1' }, 'op' => 'contem', 'valor' => 'oi' }] },
                  'passos' => [escrever] }
      problemas = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user: admin)).problemas

      expect(problemas.join).to include('ia.p1', 'gatilho')
    end

    it 'recusa o id que não é de um passo que escreve', :aggregate_failures do
      passo = mensagem_passo('p2', { '$valor' => 'ia.p9' })

      expect(problemas(escrever, passo).join).to include('ia.p9')
      expect(problemas(prioridade_passo('p1'), mensagem_do_texto).join).to include('ia.p1')
    end
  end

  it 'o ensaio não chama a IA: mostra onde o texto entraria', :aggregate_failures do
    recebida(1.hour.ago)
    conversa.update!(status: :resolved)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [escrever, mensagem_do_texto] }

    passos = Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: admin).resultado[:conversas].first[:passos]

    expect(passos.first).to include(faria: 'ia_escrever', dados: { destino: 'guardar' })
    expect(passos.last.dig(:dados, :texto)).to eq('[the text the AI would write in step p1]')
    expect(corpos).to be_empty
  end
end
