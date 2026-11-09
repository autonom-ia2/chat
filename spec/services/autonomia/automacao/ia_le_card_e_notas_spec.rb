require 'rails_helper'

# #2679 (lote 2, item d): a IA lê o card (`le: card`) e as notas internas da conversa (`le: notas`). O card vai só se
# quem ligou a automação o vê, e o valor só com a permissão (#2597). A IA é a OpenAI simulada no HTTP.
RSpec.describe 'IA lê o card e as notas', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [admin]) }
  let(:contato) { account.contacts.create!(name: 'Rose', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:card) do
    funil, etapa = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: funil, stage: etapa, inbox: inbox, contact: contato, primary_conversation: conversa,
                              title: 'Festa da Lara', custom_attributes: { 'tema' => 'Frozen', 'convidados' => '40' })
  end
  let(:corpos) { [] }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_ia', 'automacao_gatilhos')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      payload = { id: "resp_#{corpos.size}", output_text: { 'resumo' => 'Festa Frozen, 40 convidados.' }.to_json,
                  usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  after { Current.reset }

  def resumir(leituras) = { 'id' => 'r1', 'tipo' => 'resumir', 'le' => leituras, 'destino' => 'nota' }

  def rodar(passos, alvo, por: admin, gatilho: { 'tipo' => 'card.ganho' })
    definicao = automacao_ligada(account, por, passos, gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: gatilho['tipo']).call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  def registros(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  def entrada = corpos.sole['input'].to_json

  it 'no gatilho de card, a IA lê o título, a etapa e os campos do card', :aggregate_failures do
    execucao = rodar([resumir(%w[card])], card)

    expect(registros(execucao)).to eq([['r1', 'ok', nil]])
    expect(entrada).to include('Festa da Lara', 'Frozen', '40')
  end

  it 'o valor do card vai só para quem pode vê-lo (#2597)', :aggregate_failures do
    card.update!(value_cents: 1_234_500)
    allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)

    rodar([resumir(%w[card])], card)

    expect(entrada).to include('Festa da Lara')
    expect(entrada).not_to include('12345')
  end

  # #2780 (Rodrigo, 09/11): o valor da venda só decide, em qualquer automação. O passo de IA que escreve não o leva à
  # IA; o "decidir" leva.
  describe 'o valor da venda só decide' do
    let(:da_conversa) { { 'tipo' => 'conversa.resolvida' } }
    let(:escrever) { { 'id' => 'e1', 'tipo' => 'escrever', 'le' => %w[card], 'instrucao' => 'Escreva ao cliente', 'destino' => 'guardar' } }
    let(:decidir) do
      { 'id' => 'd1', 'tipo' => 'decidir', 'le' => %w[card], 'pergunta' => 'É venda grande?', 'nenhum' => [],
        'caminhos' => [{ 'nome' => 'Grande', 'chave' => 'grande', 'descricao' => 'valor alto', 'passos' => [] },
                       { 'nome' => 'Pequena', 'chave' => 'pequena', 'descricao' => 'valor baixo', 'passos' => [] }] }
    end

    before { card.update!(value_cents: 1_234_500) }

    it 'o escrever e o resumir não levam o valor ao texto da IA', :aggregate_failures do
      rodar([escrever], conversa, gatilho: da_conversa)
      expect(entrada).to include('Festa da Lara')
      expect(entrada).not_to include('12345')

      corpos.clear
      rodar([resumir(%w[card])], conversa, gatilho: da_conversa)
      expect(entrada).to include('Festa da Lara')
      expect(entrada).not_to include('12345')
    end

    it 'o decidir leva o valor: só decide' do
      rodar([decidir], conversa, gatilho: da_conversa)

      expect(entrada).to include('12345')
    end

    # Decisão 3 (09/11): em qualquer automação. Quem ligou tem a chave do valor e, mesmo assim, só o decidir o recebe.
    it 'na automação de card, com a chave de quem ligou, o escrever não leva o valor e o decidir leva', :aggregate_failures do
      rodar([escrever], card)
      expect(entrada).to include('Festa da Lara')
      expect(entrada).not_to include('12345')

      corpos.clear
      rodar([decidir], card)
      expect(entrada).to include('12345')
    end
  end

  it 'quem ligou e não vê o card: a IA lê o resto, sem o card', :aggregate_failures do
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'Quero mudar o tema')
    allow(Autonomia::Automacao::ComIa).to receive(:ve_o_card?).and_return(false)

    rodar([resumir(%w[card mensagens_recentes])], card)

    expect(entrada).to include('Quero mudar o tema')
    expect(entrada).not_to include('Festa da Lara')
  end

  it 'a IA lê as notas internas da conversa, só com `le: notas`', :aggregate_failures do
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, private: true,
                     content: 'Mecânico: trocar a pastilha na próxima', sender: admin)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, content: 'Obrigado!')

    rodar([resumir(%w[notas mensagens_recentes])], conversa, gatilho: { 'tipo' => 'conversa.resolvida' })
    rodar([resumir(%w[mensagens_recentes])], conversa, gatilho: { 'tipo' => 'conversa.resolvida' })

    expect(corpos.first['input'].to_json).to include('trocar a pastilha', 'Obrigado!')
    expect(corpos.last['input'].to_json).not_to include('trocar a pastilha')
  end

  it 'o motivo da perda vai só para a IA da Automação, nunca ao Decisor dos Agentes', :aggregate_failures do
    card.update!(lost_reason: 'Achou mais barato')

    da_automacao = Autonomia::Decisores::Estado.new(card: card, leituras: %w[card], motivo_da_perda: true).conversa[:card]
    do_decisor = Autonomia::Decisores::Estado.new(card: card, leituras: %w[card]).conversa[:card]

    expect(da_automacao[:lost_reason]).to eq('Achou mais barato')
    expect(do_decisor).not_to have_key(:lost_reason)
  end

  it 'card vazio e nada mais para ler: pula sem chamar a IA', :aggregate_failures do
    conversa_sem_card = create_crm_conversation(account: account, inbox: inbox, contact: contato)

    execucao = rodar([resumir(%w[card])], conversa_sem_card, gatilho: { 'tipo' => 'conversa.resolvida' })

    expect(registros(execucao)).to eq([%w[r1 pulado nada_para_ler]])
    expect(corpos).to be_empty
  end
end
