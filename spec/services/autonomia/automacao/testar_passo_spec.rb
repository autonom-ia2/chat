require 'rails_helper'

# "Testar este passo" (#2500 C2): o que vai à IA no teste é o que vai na execução (o `consulta` de cada passo e a mesma
# leitura). O modelo é a OpenAI simulada no HTTP; os corpos das duas idas são comparados.
RSpec.describe Autonomia::Automacao::TestarPasso, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Bruno', email: 'bruno@exemplo.com', phone_number: '+5511999990000') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:le) { %w[mensagens_recentes contato] }
  let(:corpos) { [] }
  let(:passos) do
    {
      'decidir' => { 'id' => 'p1', 'tipo' => 'decidir', 'le' => le, 'pergunta' => 'Sobre o que é?', 'nenhum' => [],
                     'caminhos' => [{ 'nome' => 'Sinistro', 'chave' => 'sinistro', 'descricao' => 'bateu', 'passos' => [] },
                                    { 'nome' => 'Cotação', 'chave' => 'cotacao', 'descricao' => 'preço', 'passos' => [] }] },
      'escrever' => { 'id' => 'p1', 'tipo' => 'escrever', 'le' => le, 'instrucao' => 'Agradeça o contato.', 'destino' => 'sugestao' },
      'resumir' => { 'id' => 'p1', 'tipo' => 'resumir', 'le' => le, 'linhas' => 2, 'destino' => 'nota' }
    }
  end
  let(:respostas) do
    { 'decidir' => { caminho: 'sinistro', motivo: 'bateu' }, 'escrever' => { texto: 'Obrigado!' }, 'resumir' => { resumo: 'Bateu o carro.' } }
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'Bati o carro ontem')
  end

  after { Current.reset }

  def openai_devolve(resposta)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: resposta.to_json, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def o_que_vai_a_ia(corpo) = corpo.slice('model', 'instructions', 'input', 'text')

  %w[decidir escrever resumir].each do |tipo|
    it "#{tipo}: o teste manda à IA o mesmo que a execução", :aggregate_failures do
      openai_devolve(respostas[tipo])
      definicao = automacao_ligada(account, admin, [passos[tipo]])

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
      pedido = described_class::Pedido.new(receita: definicao.versao_ativa.receita, passo_id: 'p1')
      teste = described_class.new(pedido: pedido, conta: account, account_user: admin.account_users.first).resultado(com_valores: true)

      expect(corpos.size).to eq(2)
      expect(o_que_vai_a_ia(corpos.last)).to eq(o_que_vai_a_ia(corpos.first))
      expect(corpos.last['input']).not_to include('bruno@exemplo.com', '5511999990000')
      expect(teste[:conversa]).to include(conversa_id: conversa.display_id)
    end
  end

  it 'o gatilho de card testa nas conversas recentes de quem pede, com o aviso' do
    openai_devolve(respostas['resumir'])
    receita = { 'gatilho' => { 'tipo' => 'card.criado' }, 'passos' => [passos['resumir']] }

    pedido = described_class::Pedido.new(receita: receita, passo_id: 'p1')
    teste = described_class.new(pedido: pedido, conta: account, account_user: admin.account_users.first).resultado(com_valores: false)

    expect(teste).to include(aviso: 'gatilho_sem_conversa', candidatas: [conversa.display_id])
  end

  it 'conversa sem nada para ler não chama a IA' do
    openai_devolve(respostas['resumir'])
    conversa.messages.destroy_all
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passos['resumir'].merge('le' => %w[mensagens_recentes])] }

    pedido = described_class::Pedido.new(receita: receita, passo_id: 'p1')
    teste = described_class.new(pedido: pedido, conta: account, account_user: admin.account_users.first).resultado(com_valores: true)

    expect([teste[:conversa][:motivo], corpos]).to eq(['nada_para_ler', []])
  end
end
