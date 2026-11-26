require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::CotarSeguroViagem do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:params) do
    { 'destinos' => ['pt'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45], 'motivo' => nil }
  end

  before do
    enable_test_encryption!
    travel_to Time.utc(2026, 11, 24, 15, 0, 0)
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok',
                                                  capacidades: { 'tarifa_acordo' => true })
    stub_request(:get, "#{base}/v1/destinos").to_return(status: 200, body: file_fixture('../universal/destinos.json').read)
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: file_fixture('../universal/cotacao.json').read)
  end

  def ferramenta(argumentos)
    described_class.new(agent: contratado, params: argumentos, delivery: delivery)
  end

  it 'cota, guarda e devolve só o resumo' do
    saida = JSON.parse(ferramenta(params).call)
    esperado = [
      { 'codigo' => 'P1', 'nome' => 'Especial UA 100K BRL', 'destaque' => 'mais_recomendada', 'preco_total' => 'R$ 360,00',
        'por_dia_por_pessoa' => 'R$ 72,00', 'max_parcelas' => 12,
        'principais' => { 'despesas_medicas' => 'R$ 100.000', 'bagagem' => 'R$ 2.000', 'cancelamento' => 'R$ 2.500' },
        'anual' => false, 'dias_por_viagem' => nil },
      { 'codigo' => 'P2', 'nome' => 'Especial UA 30K BRL', 'destaque' => 'mais_economica', 'preco_total' => 'R$ 210,00',
        'por_dia_por_pessoa' => 'R$ 42,00', 'max_parcelas' => 12,
        'principais' => { 'despesas_medicas' => 'R$ 30.000', 'bagagem' => 'R$ 1.000', 'cancelamento' => nil },
        'anual' => false, 'dias_por_viagem' => nil }
    ]
    expect(saida['planos']).to eq(esperado)
    expect(saida['pdf_vai_junto']).to be(true)
    cotacao = Autonomia::Agents::CotacaoDeViagem.last
    expect(cotacao.id_cotacao).to eq('COT-TESTE-1')
    expect(cotacao.pedido.except('universal')).to eq('destinos' => ['PT'], 'destinos_nomes' => ['Portugal'],
                                                     'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06',
                                                     'idades' => [45], 'motivo' => nil)
    expect(cotacao.pedido['universal']['passageiros']).to eq([{ 'nome' => 'Viajante 1', 'dataNascimento' => '1981-08-02' }])
    expect(cotacao.idades).to eq([45])
    expect(a_request(:post, "#{base}/v1/Cotacao").with(body: hash_including('tipoTarifa' => 2, 'classificacoes' => [1]))).to have_been_made
  end

  it 'o PDF fica marcado como cartão do turno, e a ferramenta não posta nada (#3223)' do
    ferramenta(params).call
    cotacao = Autonomia::Agents::CotacaoDeViagem.last
    expect(delivery.cartoes).to eq([{ 'tipo' => 'comparativo_viagem', 'chave' => cotacao.id.to_s, 'rich_message' => nil }])
    expect(conversa.messages.count).to eq(0)
  end

  it 'devolve a viagem conferida e nenhum campo interno da seguradora (R2)' do
    texto = ferramenta(params).call
    expect(JSON.parse(texto)['cotacao']).to eq('destinos' => ['PT'], 'data_saida' => '2027-02-02',
                                               'data_retorno' => '2027-02-06', 'idades' => [45])
    %w[comissao markup rank quotationPorcentagem valorSemDesconto].each { |campo| expect(texto).not_to include(campo) }
    expect(Autonomia::Agents::CotacaoDeViagem.last.planos.to_json).not_to include('comissao', 'markup', 'rank')
  end

  it 'lista de destinos fora: consulta uma vez, cota e guarda a sigla no lugar do nome' do
    destinos = stub_request(:get, "#{base}/v1/destinos").to_timeout
    ferramenta(params).call
    expect(destinos).to have_been_requested.once
    expect(Autonomia::Agents::CotacaoDeViagem.last.pedido['destinos_nomes']).to eq(['PT'])
  end

  it 'catálogo sem id conhecido de despesas médicas e idade recusada: um aviso só no log' do
    resposta = JSON.parse(file_fixture('../universal/cotacao.json').read)
    resposta['beneficios'] = resposta['beneficios'].map { |b| b.merge('idBeneficio' => b['idBeneficio'] + 90_000) }
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: resposta.to_json)
    allow(Rails.logger).to receive(:warn)
    ferramenta(params.merge('idades' => [100])).call
    expect(Rails.logger).to have_received(:warn).with(a_string_including('catálogo sem id conhecido')).once
  end

  describe 'o turno que já foi superado não cota (#3223)' do
    let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil, origin_message_id: 77) }

    def marca_do_debounce(mensagem)
      conversa.update!(additional_attributes: { Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY => { 'pending_message_id' => mensagem } })
    end

    before { Autonomia::Agents::Fase2.ligar!(account) }

    it 'o cliente escreveu de novo: recusa curta, sem chamar a seguradora, sem cotação e sem cartão' do
      marca_do_debounce(78)
      expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('turno_superado', anything)
      expect(ferramenta(params).call).to eq(described_class::TURNO_SUPERADO)
      expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
      expect(Autonomia::Agents::CotacaoDeViagem.count).to eq(0)
      expect(delivery.cartoes).to be_empty
    end

    it 'a recusa de turno superado fica só no log, fora da nota da equipe' do
      expect(Autonomia::Agents::Tools::RecusasRecentes::NA_NOTA).not_to include('turno_superado')
    end

    it 'a marca aponta para a mensagem deste turno: cota' do
      marca_do_debounce(77)
      expect(JSON.parse(ferramenta(params).call)['pdf_vai_junto']).to be(true)
    end

    # #3225: o turno que leu a mensagem nova no meio responde por ela, e a cotação dele vale.
    it 'a mensagem nova já foi lida por este turno (com a chave): cota' do
      account.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      marca_do_debounce(78)
      delivery.ler_no_turno([78])
      expect(JSON.parse(ferramenta(params).call)['pdf_vai_junto']).to be(true)
    end

    # #3225 (revisão): B chegou depois da última leitura do laço. Com o leitor do turno, a ferramenta lê antes de conferir:
    # B conta como lida, a cotação sai, e B vai ao modelo na próxima leitura.
    it 'com o leitor do turno, a mensagem nova ainda não lida: a ferramenta lê, e cota', :aggregate_failures do
      account.enable_features!(Autonomia::Agents::Operate::LeituraNoTurno::FLAG)
      ancora = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'Portugal')
      nova = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, content: 'Conhece lá?')
      marca_do_debounce(nova.id)
      entrega = Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil, origin_message_id: ancora.id)
      entrega.leitura = Autonomia::Agents::Operate::LeituraNoTurno.new(conversation: conversa, agent: contratado, delivery: entrega,
                                                                       ancora: ancora.id, &:content)

      saida = described_class.new(agent: contratado, params: params, delivery: entrega).call

      expect(JSON.parse(saida)['pdf_vai_junto']).to be(true)
      expect(entrega.lidas_no_turno).to eq([nova.id])
      expect(entrega.leitura.na_rodada.last[:content].first[:text]).to eq('Conhece lá?')
    end

    it 'este turno leu outra, não a mais nova: recusa' do
      marca_do_debounce(79)
      delivery.ler_no_turno([78])
      expect(ferramenta(params).call).to eq(described_class::TURNO_SUPERADO)
    end
  end

  describe 'planos anuais só quando pedidos (#3226)' do
    let(:resposta) { JSON.parse(file_fixture('../universal/cotacao.json').read) }
    let(:anual) do
      resposta['produtos'][0].merge('descricao' => 'Anual Multiviagens UA 100 (30 Dias)', 'multiviagem' => true,
                                    'diasMultiviagem' => 30)
    end

    def cotar_com(produtos, argumentos = params)
      stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: resposta.merge('produtos' => produtos).to_json)
      JSON.parse(ferramenta(argumentos).call)
    end

    it 'sem incluir_anuais: o anual fica fora da cotação guardada, do resumo e do PDF, e os códigos são só dos únicos' do
      saida = cotar_com(resposta['produtos'] + [anual])
      expect(saida['planos'].pluck('codigo', 'anual')).to eq([['P1', false], ['P2', false]])
      expect(saida).not_to have_key('aviso')
      expect(Autonomia::Agents::CotacaoDeViagem.last.planos.pluck('multiviagem')).to eq([false, false])
    end

    it 'com incluir_anuais: true, o anual entra, sem destaque' do
      saida = cotar_com(resposta['produtos'] + [anual], params.merge('incluir_anuais' => true))
      expect(saida['planos'].pluck('codigo', 'anual', 'destaque'))
        .to eq([['P1', false, 'mais_recomendada'], ['P2', false, 'mais_economica'], ['P3', true, nil]])
    end

    it 'incluir_anuais em texto ("true"), como a ferramenta nativa recebe sem conversão: inclui; "false" não' do
      expect(cotar_com(resposta['produtos'] + [anual], params.merge('incluir_anuais' => 'true'))['planos'].pluck('anual'))
        .to eq([false, false, true])
      expect(cotar_com(resposta['produtos'] + [anual], params.merge('incluir_anuais' => 'false'))['planos'].pluck('anual'))
        .to eq([false, false])
    end

    it 'só anuais e o cliente não pediu: devolve os anuais e avisa que só há anuais' do
      saida = cotar_com([anual])
      expect(saida['planos'].pluck('anual')).to eq([true])
      expect(saida['aviso']).to eq(described_class::SO_ANUAIS)
    end
  end

  it 'duas cotações no mesmo turno: duas cotações, e um comparativo só, o da última' do
    2.times { ferramenta(params).call }
    expect(a_request(:post, "#{base}/v1/Cotacao")).to have_been_made.twice
    expect(delivery.cartoes.pluck('chave')).to eq([Autonomia::Agents::CotacaoDeViagem.order(:id).last.id.to_s])
  end

  describe 'o nome de cada país (#3223)' do
    before do
      stub_request(:get, "#{base}/v1/destinos")
        .to_return(status: 200, body: [{ 'pais' => 'FRANCA', 'siglaPais' => 'FR' }, { 'pais' => 'ITALIA', 'siglaPais' => 'IT' }].to_json)
    end

    def nomes_guardados(argumentos)
      ferramenta(params.merge(argumentos)).call
      Autonomia::Agents::CotacaoDeViagem.last.pedido['destinos_nomes']
    end

    it 'o nome que o modelo escreveu no idioma da conversa' do
      expect(nomes_guardados('destinos' => %w[fr it], 'nomes_dos_destinos' => [' França ', 'Itália'])).to eq(%w[França Itália])
    end

    it 'sem o nome, com outro tamanho ou com nome em branco: o nome da Universal' do
      expect(nomes_guardados('destinos' => ['fr'])).to eq(['FRANCA'])
      expect(nomes_guardados('destinos' => ['fr'], 'idades' => [46], 'nomes_dos_destinos' => %w[França Itália])).to eq(['FRANCA'])
      expect(nomes_guardados('destinos' => ['fr'], 'idades' => [47], 'nomes_dos_destinos' => [' '])).to eq(['FRANCA'])
    end

    it 'nome acima do teto: o nome da Universal; no teto, o do modelo' do
      teto = described_class::TETO_DO_NOME_DO_PAIS
      expect(nomes_guardados('destinos' => ['fr'], 'nomes_dos_destinos' => ['F' * (teto + 1)])).to eq(['FRANCA'])
      expect(nomes_guardados('destinos' => ['fr'], 'idades' => [46], 'nomes_dos_destinos' => ['F' * teto])).to eq(['F' * teto])
    end
  end

  describe 'região e Brasil (#3226)' do
    it 'Brasil com país de fora: cota sem o Brasil, guarda sem o nome dele e devolve aviso_brasil' do
      saida = JSON.parse(ferramenta(params.merge('destinos' => %w[BR PT], 'nomes_dos_destinos' => %w[Brasil Portugal])).call)
      expect(saida['cotacao']['destinos']).to eq(['PT'])
      expect(saida['aviso_brasil']).to eq(described_class::BRASIL_FORA)
      expect(Autonomia::Agents::CotacaoDeViagem.last.pedido['destinos_nomes']).to eq(['Portugal'])
      expect(a_request(:post, "#{base}/v1/Cotacao").with(body: hash_including('destinos' => ['PT']))).to have_been_made
    end

    it 'só o Brasil: cota o Brasil, sem aviso_brasil' do
      saida = JSON.parse(ferramenta(params.merge('destinos' => ['BR'])).call)
      expect(saida['cotacao']['destinos']).to eq(['BR'])
      expect(saida).not_to have_key('aviso_brasil')
    end

    it 'região pelo código da Universal: cota com o código e guarda o nome da região' do
      stub_request(:get, "#{base}/v1/destinos").to_return(status: 200, body: [{ 'pais' => 'EUROPA', 'siglaPais' => 'X6' }].to_json)
      ferramenta(params.merge('destinos' => ['x6'], 'nomes_dos_destinos' => ['Europa'])).call
      expect(a_request(:post, "#{base}/v1/Cotacao").with(body: hash_including('destinos' => ['X6']))).to have_been_made
      expect(Autonomia::Agents::CotacaoDeViagem.last.pedido['destinos_nomes']).to eq(['Europa'])
    end
  end

  it 'sem conversa não cota' do
    expect(described_class.new(agent: contratado, params: params, delivery: nil).call).to include('cotacao_sem_conversa')
    expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
  end

  it 'data errada recusa com o campo e registra a recusa (não trava a escrita do turno)' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pedido_invalido', hash_including(faltando: ['data_saida']))
    ferramenta(params.merge('data_saida' => '2020-01-01')).call
  end

  it 'destino que a seguradora não atende: recusa sem cotar' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('destino_invalido', hash_including(faltando: ['destinos']))
    expect(ferramenta(params.merge('destinos' => %w[PT XX])).call).to include('XX')
    expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
  end

  it 'idade que nenhum plano aceita: idade_fora_do_limite' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('idade_fora_do_limite', hash_including(faltando: ['idades']))
    ferramenta(params.merge('idades' => [70])).call
  end

  it 'resposta sem plano: sem_plano, e nada é guardado' do
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: { 'idCotacao' => 'c-0', 'produtos' => [] }.to_json)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_plano', anything)
    ferramenta(params).call
    expect(Autonomia::Agents::CotacaoDeViagem.count).to eq(0)
  end

  it 'timeout não levanta e passa pelas falhas' do
    stub_request(:post, "#{base}/v1/Cotacao").to_timeout
    expect(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas).to receive(:tratar)
      .with(an_instance_of(Autonomia::Seguradoras::Universal::Cliente::Erro), acao: 'cotar_seguro_viagem',
                                                                              agent: contratado, conversation: conversa).and_call_original
    expect { ferramenta(params).call }.not_to raise_error
  end
end
