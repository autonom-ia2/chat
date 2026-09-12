require 'rails_helper'

# A PROPOSTA DE UMA SEGURADORA SÓ (entrega 8 do Agente de Cotação, #396 — termos 1, 3 e 4).
#
# O que estes exemplos travam: o cliente pede a proposta de UMA seguradora e recebe a DAQUELA, não o
# comparativo (termo 1); quem não cotou é dito, com a lista de quem cotou, em vez do comparativo em
# silêncio (termo 3); duas seguradoras são dois arquivos na mesma execução, e NENHUMA cotação nova
# (termo 4 — `quote_start` nunca é chamado daqui). O casamento do nome é comparação de texto contra o
# mapa que a cotação gravou (`nomes_entregues`): exato ou prefixo de um só nome casa; prefixo de mais
# de um é ambíguo e pergunta; semelhança não existe ("Portu" não é "Porto").
#
# Os nomes são os REAIS do portal em 11/09/2026: 8 "Porto", 48 "Bp", 55 "Bp Assinatura", 20 "Suhai".
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceProposal do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let!(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: 77) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:nomes) { { '8' => 'Porto', '48' => 'Bp', '55' => 'Bp Assinatura', '20' => 'Suhai' } }
  # O conector é um dublê ESTRITO: qualquer chamada fora de `quote_proposal` (um `quote_start`, um
  # `open_session`) levanta — é assim que "não cota de novo" e "não abre login" ficam provados.
  let(:connector) { instance_double(Autonomia::Insurance::Connector::Mock) }
  # Os códigos pedidos ao portal, na ordem.
  let(:pedidos) { [] }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    allow(connector).to receive(:quote_proposal) do |**kwargs|
      pedidos << kwargs[:insurer_code]
      { 'quote_id' => kwargs[:quote_id], 'url' => "https://arquivos.exemplo.test/proposta-#{kwargs[:insurer_code]}.pdf" }
    end
    allow(connector).to receive(:quote_start)
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  # A cotação que a proposta lê: encerrada, com preço entregue e o mapa código -> nome (entrega 8),
  # como a ferramenta de cotação a deixa.
  def cotacao_com_precos(mapa: nomes, conversa: conversation, quote_id: 'q1', status: 'done',
                         arguments: { 'produto' => 'auto', 'vehicle' => { 'plate' => 'abc-1d23' } })
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agent, conversation_id: conversa.id, slug: cotacao.slug, status: status,
      execution_key: SecureRandom.uuid, arguments: arguments,
      handle: { 'quote_id' => quote_id, 'produto' => arguments['produto'], cotacao::DELIVERED_KEY => mapa.keys,
                cotacao::NOMES_KEY => mapa }
    )
  end

  def arquivo(entrega)
    Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
  end

  # No JOB a ferramenta nasce sem `delivery` e com a conversa da execução (`AsyncRunJob#ferramenta`).
  def no_job(*seguradoras)
    described_class.new(agent: agent, params: { 'seguradoras' => seguradoras }, conversation: conversation)
  end

  # No TURNO ela nasce com o `delivery` (`Bound#accept_async`).
  def no_turno(*seguradoras)
    described_class.new(agent: agent, params: { 'seguradoras' => seguradoras }, delivery: delivery)
  end

  it 'e assincrona: gerar a proposta e chamada ao portal de ate 60 s, e o turno nao espera' do
    expect(described_class.async?).to be(true)
  end

  # ARRAY OBRIGATÓRIO em strict mode: fora de `required` (ou anulável) o agente fica MUDO.
  it 'declara `seguradoras` como array de texto obrigatorio, sem null' do
    schema = described_class.openai_schema
    parametro = schema[:parameters][:properties]['seguradoras']

    expect(schema[:parameters][:required]).to eq(['seguradoras'])
    expect(parametro['type']).to eq('array')
    expect(parametro['items']).to eq('type' => 'string')
  end

  describe '#start — a proposta da escolhida (termo 1)' do
    it 'pede ao portal a proposta da seguradora escolhida, pelo codigo do mapa da cotacao, e nao o comparativo' do
      # Arrange
      cotacao_com_precos

      # Act
      handle = no_job('Porto').start

      # Assert
      expect(handle[described_class::GERADAS]).to eq([{ 'code' => '8', 'name' => 'Porto', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' }])
      expect(handle['quote_id']).to eq('q1')
      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '8', quote_id: 'q1')).once
      expect(connector).not_to have_received(:quote_start)
    end

    it 'casa o nome como o cliente escreveu: maiuscula, acento e espaco a mais nao importam' do
      cotacao_com_precos(mapa: nomes.merge('3' => 'Mapfre São Paulo'))

      expect(no_job('  PORTO ').start[described_class::GERADAS].pluck('code')).to eq(['8'])
      expect(no_job('mapfre sao  paulo').start[described_class::GERADAS].pluck('code')).to eq(['3'])
    end

    it 'casa pelo prefixo quando ele e de um nome so' do
      cotacao_com_precos

      expect(no_job('Suh').start[described_class::GERADAS].pluck('code')).to eq(['20'])
    end

    # NADA DE SEMELHANÇA: um nome que não é prefixo de ninguém não cotou, mesmo que "pareça".
    it 'nao casa por semelhanca: "Portu" nao e Porto' do
      cotacao_com_precos

      handle = no_job('Portu').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O CASO REAL DO HOMÔNIMO: no portal, 48 chama-se "Bp" e 55 "Bp Assinatura" — um total anual e
    # uma assinatura mensal. "Bp" é prefixo das duas: ambíguo, e a resposta lista as duas. Dar ao
    # exato a vitória mandaria a proposta da 48 a quem talvez tenha lido a 55.
    it 'homonimo: "Bp" com 48 e 55 cotadas e ambiguo, e a resposta lista as candidatas' do
      cotacao_com_precos

      handle = no_job('Bp').start

      expect(handle['motivo']).to eq('seguradora_ambigua')
      expect(handle['pedido']).to include('Bp pode ser Bp ou Bp Assinatura')
      expect(handle['faltando']).to eq(['seguradoras'])
      expect(connector).not_to have_received(:quote_proposal)
    end

    it '"Bp Assinatura" e uma so, mesmo com a Bp cotada' do
      cotacao_com_precos

      expect(no_job('Bp Assinatura').start[described_class::GERADAS].pluck('code')).to eq(['55'])
    end

    it 'quando so a Bp Assinatura cotou, "Bp" e ela' do
      cotacao_com_precos(mapa: nomes.except('48'))

      expect(no_job('Bp').start[described_class::GERADAS].pluck('code')).to eq(['55'])
    end

    it 'dois nomes que casam com a mesma seguradora sao UMA proposta' do
      cotacao_com_precos

      handle = no_job('Porto', 'porto').start

      expect(handle[described_class::GERADAS].pluck('code')).to eq(['8'])
      expect(connector).to have_received(:quote_proposal).once
    end
  end

  # TERMO 3 — se a seguradora pedida não cotou, a resposta diz isso e lista quem cotou, em vez de
  # mandar o comparativo de todas em silêncio. E nenhuma chamada ao portal.
  describe '#start — quem nao cotou (termo 3)' do
    it 'diz que nao tem preco daquela e lista quem cotou' do
      cotacao_com_precos

      handle = no_job('Zurich').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(handle['pedido']).to include('Não tenho preço de Zurich nesta cotação')
      expect(handle['pedido']).to include('Porto', 'Bp', 'Bp Assinatura', 'Suhai')
      expect(handle['pedido']).not_to include('Comparativo')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'com duas pedidas e uma que nao cotou, a resposta e a recusa daquela — sem mandar a outra em silencio' do
      cotacao_com_precos

      handle = no_job('Porto', 'Zurich').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(handle['pedido']).to include('Zurich')
      expect(connector).not_to have_received(:quote_proposal)
    end

    # O portal dizendo "não cotou" (422, `:validation`) contra o nosso mapa: é a mesma recusa, não
    # `tool_execution_error`. O cliente lê quem cotou; a divergência vai ao log.
    it 'o portal recusando a seguradora como "nao cotou" vira a mesma recusa nomeada, nao erro' do
      cotacao_com_precos
      allow(connector).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'insurer did not quote'))

      handle = no_job('Porto').start

      expect(handle['motivo']).to eq('seguradora_nao_cotou')
      expect(handle['pedido']).to include('Porto')
    end

    it 'qualquer outra falha do portal sobe, para o job decidir entre tentar de novo e desistir' do
      cotacao_com_precos
      allow(connector).to receive(:quote_proposal).and_raise(Autonomia::Insurance::Connector::Error.new(:unavailable, 'X-Amz-Signature=abc'))

      expect { no_job('Porto').start }.to raise_error(Autonomia::Insurance::Connector::Error)
    end

    it 'resposta do portal sem URL e falha, nao proposta vazia' do
      cotacao_com_precos
      allow(connector).to receive(:quote_proposal).and_return({ 'quote_id' => 'q1' })

      expect { no_job('Porto').start }.to raise_error(Autonomia::Insurance::Connector::Error)
    end
  end

  # TERMO 4 — duas seguradoras, dois arquivos, na MESMA execução; e nenhuma cotação nova.
  describe '#start — duas seguradoras (termo 4)' do
    it 'gera as duas propostas na mesma execucao, uma chamada por seguradora, sem abrir cotacao' do
      cotacao_com_precos

      handle = no_job('Porto', 'Suhai').start

      expect(handle[described_class::GERADAS].pluck('code')).to eq(%w[8 20])
      expect(pedidos).to eq(%w[8 20])
      expect(connector).not_to have_received(:quote_start)
    end

    it 'quando o portal recusa uma das duas, sai a que saiu e o aviso da outra' do
      cotacao_com_precos
      allow(connector).to receive(:quote_proposal) do |**kwargs|
        raise Autonomia::Insurance::Connector::Error.new(:validation, 'nao cotou') if kwargs[:insurer_code] == '20'

        { 'quote_id' => 'q1', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' }
      end

      handle = no_job('Porto', 'Suhai').start

      expect(handle[described_class::GERADAS].pluck('code')).to eq(['8'])
      expect(handle[described_class::NAO_SAIU]).to eq(['Suhai'])
    end

    it 'mais de duas e recusa nomeada, antes de qualquer chamada' do
      cotacao_com_precos

      handle = no_job('Porto', 'Suhai', 'Bp Assinatura').start

      expect(handle['motivo']).to eq('proposta_acima_do_teto')
      expect(handle['pedido']).to include('até duas')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'nenhuma seguradora e recusa nomeada' do
      cotacao_com_precos

      expect(no_job.start['motivo']).to eq('proposta_sem_seguradora')
      expect(no_job('  ').start['motivo']).to eq('proposta_sem_seguradora')
    end
  end

  describe '#start — qual cotacao' do
    it 'sem cotacao com preco nesta conversa e recusa nomeada, sem tocar no portal' do
      handle = no_job('Porto').start

      expect(handle['motivo']).to eq('proposta_sem_cotacao')
      expect(handle['pedido']).to include('Não encontrei nesta conversa uma cotação')
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'a cotacao de OUTRA conversa nao conta' do
      cotacao_com_precos(conversa: create(:conversation, account: account, inbox: inbox, assignee: nil))

      expect(no_job('Porto').start['motivo']).to eq('proposta_sem_cotacao')
    end

    it 'a cotacao sem preco entregue nao conta' do
      cotacao_com_precos(mapa: {})

      expect(no_job('Porto').start['motivo']).to eq('proposta_sem_cotacao')
    end

    # A cotação anterior à entrega 8 tem `entregues` e não tem o mapa: não há como casar o nome.
    it 'a cotacao anterior a entrega 8, sem o mapa de nomes, nao conta' do
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, conversation_id: conversation.id, slug: cotacao.slug,
                                         status: 'done', execution_key: SecureRandom.uuid, arguments: {},
                                         handle: { 'quote_id' => 'velha', cotacao::DELIVERED_KEY => ['8'] })

      expect(no_job('Porto').start['motivo']).to eq('proposta_sem_cotacao')
    end

    # A MAIS RECENTE POR ID, seja qual for o status: a cotação supersedida por um pedido novo que ainda
    # não tem preço continua sendo a que o cliente leu.
    it 'usa a cotacao mais recente com preco, mesmo supersedida' do
      cotacao_com_precos(quote_id: 'antiga')
      cotacao_com_precos(quote_id: 'nova', status: 'superseded')
      cotacao_com_precos(quote_id: 'sem-preco', mapa: {}, status: 'running')

      handle = no_job('Porto').start

      expect(handle['quote_id']).to eq('nova')
      expect(connector).to have_received(:quote_proposal).with(hash_including(quote_id: 'nova'))
    end

    it 'guarda no handle o que o poll precisa: a linha da cotacao e o sufixo do nome do arquivo' do
      linha = cotacao_com_precos

      handle = no_job('Porto').start

      expect(handle['cotacao_run_id']).to eq(linha.id)
      expect(handle['sufixo']).to eq('placa ABC1D23')
    end
  end

  # A CONFERÊNCIA DO TURNO: o que dá para saber sem o portal responde ao modelo na hora, e nenhuma
  # execução é aberta. O portal NUNCA é chamado dentro do turno — nem login, nem proposta.
  describe '#precheck — no turno, sem portal' do
    it 'devolve ao modelo a ambiguidade, com as candidatas, e nao toca no portal' do
      cotacao_com_precos

      conferencia = no_turno('Bp').precheck

      expect(conferencia).to be_a(Autonomia::Agents::Tools::Native::Conferencia)
      expect(conferencia.motivo).to eq('seguradora_ambigua')
      expect(conferencia.to_s).to include('Bp Assinatura')
      expect(conferencia.faltando).to eq(['seguradoras'])
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'devolve ao modelo quem nao cotou, com a lista de quem cotou' do
      cotacao_com_precos

      conferencia = no_turno('Zurich').precheck

      expect(conferencia.motivo).to eq('seguradora_nao_cotou')
      expect(conferencia.to_s).to include('Quem cotou: Bp, Bp Assinatura, Porto e Suhai')
    end

    it 'sem cotacao na conversa, diz isso ao modelo' do
      expect(no_turno('Porto').precheck.motivo).to eq('proposta_sem_cotacao')
    end

    it 'deixa passar quando ha o que gerar — e ainda assim nao chama o portal no turno' do
      cotacao_com_precos

      expect(no_turno('Porto', 'Suhai').precheck).to be_nil
      expect(connector).not_to have_received(:quote_proposal)
    end

    it 'sem sessao viva o turno segue igual: a conferencia nao depende do portal' do
      cotacao_com_precos
      Autonomia::Insurance::Connection.for_account(account).sole.forget_session!

      expect(no_turno('Porto').precheck).to be_nil
      expect(no_turno('Bp').precheck.motivo).to eq('seguradora_ambigua')
    end
  end

  describe '#poll — os arquivos, e o registro na cotacao' do
    let(:handle) do
      { 'quote_id' => 'q1', 'cotacao_run_id' => linha.id, 'sufixo' => 'placa ABC1D23',
        described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'https://arquivos.exemplo.test/proposta-8.pdf' },
                                     { 'code' => '20', 'name' => 'Suhai', 'url' => 'https://arquivos.exemplo.test/proposta-20.pdf' }] }
    end
    let(:linha) { cotacao_com_precos }

    it 'entrega um arquivo por proposta, nomeado pela seguradora e pela placa, com legenda e reserva' do
      progresso = no_job('Porto', 'Suhai').poll(handle: handle, attempt: 1)

      expect(progresso).to be_done
      arquivos = progresso.deliveries.map { |entrega| arquivo(entrega) }
      expect(arquivos.map(&:nome)).to eq(['Proposta Porto — placa ABC1D23.pdf', 'Proposta Suhai — placa ABC1D23.pdf'])
      expect(arquivos.map(&:legenda)).to eq(['Proposta da Porto.', 'Proposta da Suhai.'])
      expect(arquivos.first.reserva).to eq("Proposta da Porto:\nhttps://arquivos.exemplo.test/proposta-8.pdf")
      expect(arquivos.first.url).to eq('https://arquivos.exemplo.test/proposta-8.pdf')
    end

    it 'nomeia pelo ramo quando a cotacao nao tem placa' do
      progresso = no_job('Porto').poll(handle: handle.merge('sufixo' => 'fianca locaticia'), attempt: 1)

      expect(arquivo(progresso.deliveries.first).nome).to eq('Proposta Porto — fianca locaticia.pdf')
    end

    # O REGISTRO É NA LINHA DA COTAÇÃO, que já está `done`: é ela que "virou proposta", e é lá que a
    # medida da entrega 7 lê. Uma escrita que exigisse linha viva contaria zero para sempre.
    it 'anota na linha da COTACAO quais propostas sairam, e a medida conta' do
      no_job('Porto', 'Suhai').poll(handle: handle, attempt: 1)

      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(%w[20 8])
      expect(linha.status).to eq('done')
      expect(Autonomia::Insurance::Medida.new(conta: account, inicio: nil, fim: nil).call)
        .to include(cotacoes: 1, cotacoes_com_proposta: 1, propostas_emitidas: 2)
    end

    it 'acumula sem repetir quando o cliente pede outra depois' do
      no_job('Porto').poll(handle: handle.merge(described_class::GERADAS => handle[described_class::GERADAS].first(1)), attempt: 1)
      no_job('Porto', 'Suhai').poll(handle: handle, attempt: 1)

      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(%w[20 8])
    end

    it 'entrega o aviso da seguradora que o portal recusou, depois dos arquivos' do
      progresso = no_job('Porto', 'Suhai').poll(handle: handle.merge(described_class::GERADAS => handle[described_class::GERADAS].first(1),
                                                                     described_class::NAO_SAIU => ['Suhai']), attempt: 1)

      expect(progresso.deliveries.size).to eq(2)
      expect(progresso.deliveries.last).to eq('Não consegui gerar a proposta de Suhai agora; as demais estão aqui em cima.')
    end

    it 'entrega a recusa do start ao cliente e acaba' do
      progresso = no_job('Zurich').poll(handle: { 'pedido' => 'Não tenho preço de Zurich.', 'motivo' => 'seguradora_nao_cotou' }, attempt: 1)

      expect(progresso).to be_done
      expect(progresso.deliveries).to eq(['Não tenho preço de Zurich.'])
    end

    # A URL VEM DE FORA: se não cabe na forma segura, vai o link em texto — a falha da forma não
    # apaga a entrega (a mesma regra do comparativo).
    it 'quando a URL do portal nao tem a forma segura, entrega o link em texto' do
      inseguro = handle.merge(described_class::GERADAS => [{ 'code' => '8', 'name' => 'Porto', 'url' => 'http://arquivos.exemplo.test/p.pdf' }])

      progresso = no_job('Porto').poll(handle: inseguro, attempt: 1)

      expect(progresso.deliveries).to eq(["Proposta da Porto:\nhttp://arquivos.exemplo.test/p.pdf"])
    end

    it 'falha nomeada quando o handle nao tem proposta nem pedido' do
      progresso = no_job('Porto').poll(handle: { 'quote_id' => 'q1' }, attempt: 1)

      expect(progresso).to be_failed
      expect(progresso.failure_code).to eq('sem_proposta')
    end
  end

  # O CAMINHO REAL: o `AsyncRunJob` monta a ferramenta sem `delivery` e com a conversa da execução —
  # é assim que `start` acha a cotação DA CONVERSA fora do turno. Depois, o publicador baixa o PDF e
  # o anexa com o nome da seguradora, e a cotação fica marcada.
  describe 'pelo job' do
    let(:pdf) { "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n%%EOF\n" }

    before do
      register_async_tool(described_class)
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('arquivos.exemplo.test').and_return(['93.184.216.34'])
      stub_request(:get, 'https://arquivos.exemplo.test/proposta-8.pdf')
        .to_return(status: 200, body: pdf, headers: { 'Content-Type' => 'application/pdf' })
    end

    def execucao(*seguradoras)
      run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: { 'seguradoras' => seguradoras },
                                             scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
      run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 3.minutes.from_now)
      run
    end

    def bot_messages
      conversation.messages.reload.where(sender_type: 'AgentBot').order(:id)
    end

    it 'acha a cotacao da conversa em start, anexa a proposta em poll e marca a cotacao' do
      # Arrange
      linha = cotacao_com_precos
      run = execucao('Porto')

      # Act — a passada de submissão e a de consulta
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 0)
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 1)

      # Assert
      expect(connector).to have_received(:quote_proposal).with(hash_including(insurer_code: '8', quote_id: 'q1')).once
      expect(connector).not_to have_received(:quote_start)
      expect(bot_messages.map(&:content)).to eq(['Proposta da Porto.'])
      expect(bot_messages.sole.attachments.sole.file.filename.to_s).to eq('Proposta Porto — placa ABC1D23.pdf')
      expect(run.reload).to have_attributes(status: 'done', handle: hash_including(described_class::GERADAS => [hash_including('code' => '8')]))
      # A marca fica na cotação, não na execução da proposta: é a cotação que a medida soma.
      expect(run.handle).not_to have_key(cotacao::PROPOSTAS_KEY)
      expect(linha.reload.handle[cotacao::PROPOSTAS_KEY]).to eq(['8'])
    end

    it 'sem cotacao na conversa, o cliente le a recusa e nenhuma chamada ao portal sai' do
      run = execucao('Porto')

      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 0)
      Autonomia::Agents::Tools::AsyncRunJob.new.perform(run.id, 1)

      expect(bot_messages.map(&:content)).to eq([described_class::SEM_COTACAO])
      expect(connector).not_to have_received(:quote_proposal)
      expect(run.reload.status).to eq('done')
    end
  end

  describe '.available_for?' do
    it 'segue a porta da cotacao: modulo ligado e conexao pronta' do
      expect(described_class.available_for?(agent)).to be(true)
      expect(described_class.available_for?(agent)).to eq(cotacao.available_for?(agent))

      Autonomia::Insurance::Connection.for_account(account).sole.update!(status: 'degraded')
      expect(described_class.available_for?(agent)).to be(false)
    end
  end
end
