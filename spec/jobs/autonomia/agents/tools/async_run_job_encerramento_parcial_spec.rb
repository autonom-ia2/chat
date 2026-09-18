require 'rails_helper'

# A FRASE DE ENCERRAMENTO PARCIAL DA COTAÇÃO, PELO CAMINHO REAL (entrega 4).
#
# Quando o prazo estoura e ALGUMAS seguradoras já responderam, o cliente precisa ler "algumas
# SEGURADORAS não responderam a tempo" — e não o texto genérico do `Base`, "algumas consultas". A
# frase de seguros nasceu em 08/09/2026 (`c7ae6997e1`) e nunca rodou: era método de instância, e o
# `AsyncRunJob` publica o fecho pela CLASSE. Rodrigo recebeu a frase genérica em 09/09.
#
# Este exemplo NÃO chama `partial_message` direto (um teste assim passava com o defeito no lugar):
# ele roda o job sobre uma execução da ferramenta de cotação real, no ESTADO PREPARADO em que o
# defeito aparecia — submetida, com um preço contado como entregue, prazo vencido; não passa por
# `start`/`poll` — e lê o que o job publicou na conversa: o comparativo e a frase, nesta ordem.
# Desfazer a correção (voltar `partial_message` para a instância) faz este exemplo falhar — provado
# por mutação em 10/09/2026.
RSpec.describe Autonomia::Agents::Tools::AsyncRunJob, type: :job do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', INSURANCE_QUOTING_ENABLED: 'true',
                      INSURANCE_CONNECTOR_MODE: 'mock') { example.run }
  end

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    register_async_tool(cotacao)
    # O `SafeFetch` resolve o nome antes de conectar (é assim que ele confere o endereço): o host de
    # teste do comparativo ganha um endereço público, e o WebMock responde a chamada.
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.test').and_return(['93.184.216.34'])
  end

  def bot_contents
    conversation.messages.reload.where(sender_type: 'AgentBot').order(:id).map(&:content)
  end

  # O PREÇO COMO O CLIENTE O LÊ, e o comparativo como o portal o entrega. Os dois são ENTREGAS: o
  # que o Arrange precisa montar não é "o handle diz que saiu", é a MENSAGEM na conversa — é ela
  # que o fecho consulta desde a entrega 8a.
  def preco_ao_cliente
    '*Ezze*: R$ 2.050,40 no total'
  end

  def comparativo_do_portal
    Autonomia::Agents::Tools::EntregaDeArquivo.new(
      url: 'https://exemplo.test/comparativo-mock.pdf',
      nome: 'Comparativo de seguro, placa ABC1D23.pdf',
      legenda: cotacao::Comparativo::LEGENDA,
      reserva: "#{cotacao::Comparativo::RESERVA}\nhttps://exemplo.test/comparativo-mock.pdf"
    )
  end

  def stub_comparativo_pdf
    stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf')
      .to_return(status: 200, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
  end

  # PUBLICA PELO CAMINHO REAL (o mesmo publicador do motor) e devolve o TOKEN da entrega. Levanta se
  # a publicação não entrar: um Arrange que mente sobre o que o cliente recebeu não prova nada.
  #
  # `registrar:` é o que o motor faz no ACEITE (`Tools::EntregaAceita`). FALSO reproduz a linha que
  # atravessou o deploy: a publicação aconteceu na versão anterior, que não registrava nada.
  def publicar!(run, entrega, registrar: true)
    resultado = Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
    raise "o Arrange nao publicou a entrega: #{resultado.status}" unless resultado.published?

    Autonomia::Agents::Tools::EntregaAceita.registrar(run, entrega, resultado) if registrar
    Autonomia::Agents::Tools::EntregaPublicada.token_de(run, entrega)
  end

  def abrir_execucao(expires_at: 1.minute.ago, cadeia: 0, origem: nil)
    run = Autonomia::Agents::ToolRun.open!(agent: agent, slug: cotacao.slug,
                                           arguments: { 'produto' => 'auto', 'placa' => 'ABC1D23' },
                                           scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id })
    run.update!(origin_message_id: origem)
    run.promote!(expected_chunks: cadeia, notify_customer: false, expires_at: expires_at)
    run
  end

  # A cotação que o mock já está respondendo: `quote_id` com o carimbo de tempo que põe a consulta
  # no ramo `partial` (Porto Seguro e Mapfre respondem cedo; as outras demoram).
  def cotacao_em_andamento_no_mock
    "mock-#{Time.current.to_i - Autonomia::Insurance::Connector::Mock::PARTIAL_AFTER.to_i}:1"
  end

  # O último pedaço da cadeia de entrega humanizada do turno: enquanto ele não entra, o publicador
  # ADIA. É o que `AsyncPublisher#humanized_chain_open?` procura.
  def fechar_cadeia_do_turno(origem)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     sender: agent_bot, content: 'deixa eu consultar aqui',
                     content_attributes: { 'autonomia_chunk_token' => "#{origem}:0" })
  end

  # As publicações ADIADAS saindo — é o `AsyncPublishJob` que leva ao cliente o que a cadeia segurou.
  def drenar_publicacoes_adiadas
    perform_enqueued_jobs(only: Autonomia::Agents::Tools::AsyncPublishJob)
  end

  # A execução no estado em que o defeito aparecia: submetida, com um preço QUE O CLIENTE RECEBEU
  # (mensagem na conversa, contada na linha) e com o prazo vencido — como em 08/09/2026, quando
  # cinco preços chegaram e a conversa parou.
  def cotacao_com_preco_entregue_e_prazo_vencido
    run = abrir_execucao
    token = publicar!(run, preco_ao_cliente)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], cotacao::PRECOS_KEY => [token],
                                  cotacao::PRECO_LEGADO_KEY => false, 'produto' => 'auto' })
    run
  end

  # A COTAÇÃO COM PREÇO GUARDADO E NADA NA TELA DO CLIENTE (fatia 3 do #420): a consulta real grava quem cotou e
  # não publica lote nenhum. O contador fica em zero.
  def cotacao_com_preco_guardado_e_nada_publicado
    run = abrir_execucao(expires_at: 3.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'produto' => 'auto',
                                  'quote_id' => cotacao_em_andamento_no_mock })
    described_class.new.perform(run.id, 1)
    run.reload
  end

  # A LINHA QUE JÁ ESTAVA EM VOO QUANDO ESTA VERSÃO SUBIU (janela do deploy). O handle é o da
  # versão anterior: tem `entregues` e nenhuma identidade nossa — nem a do preço, nem a marca de
  # cobertura —, porque a passada que emite é a que as grava, e ela já aconteceu. O cliente tem o
  # preço na tela, o contador da linha o conta, e o prazo venceu durante o deploy.
  def cotacao_da_janela_do_deploy
    run = abrir_execucao
    publicar!(run, preco_ao_cliente, registrar: false)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], 'produto' => 'auto' })
    run
  end

  # A MESMA LINHA LEGADA, AINDA VIVA e com o portal ainda respondendo: o preço da versão anterior
  # está na tela (o handle só tem `entregues`), e a próxima consulta ainda tem a Mapfre para
  # entregar. É o estado em que o histórico do handle fica MISTO — parte emitida antes desta
  # versão, parte depois.
  def cotacao_legada_com_preco_antigo_na_tela
    run = abrir_execucao(expires_at: 3.minutes.from_now)
    publicar!(run, preco_ao_cliente)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'produto' => 'auto',
                                  'quote_id' => cotacao_em_andamento_no_mock,
                                  cotacao::DELIVERED_KEY => ['8'] })
    run
  end

  # A LINHA LEGADA CUJO PREÇO A VERSÃO ANTERIOR NÃO ENTREGOU. O handle é o de antes — tem
  # `entregues` e nenhuma identidade nossa —, e o contador da linha é ZERO: a versão anterior
  # emitiu o lote e a publicação foi RECUSADA, então ela não contou entrega nenhuma. O cliente não
  # tem preço na tela, e `entregues` é intenção de quem publicou, não prova.
  def cotacao_legada_sem_aceite_nenhum
    run = abrir_execucao
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], 'produto' => 'auto' })
    run
  end

  # A PUBLICAÇÃO QUE FALHA no meio, como ela falha de verdade: o publicador nunca levanta para fora
  # (`AsyncPublisher#publish` devolve `blocked`), e o handle da ferramenta avança assim mesmo.
  def recusar_publicacao_de(trecho)
    original = Messages::MessageBuilder.method(:new)
    allow(Messages::MessageBuilder).to receive(:new) do |*args|
      raise ActiveRecord::StatementInvalid, 'canal fora' if args[2][:content].to_s.include?(trecho)

      original.call(*args)
    end
  end

  # A MESMA execução, sem preço nenhum: submetida, prazo vencido, nada entregue.
  def cotacao_sem_preco_e_prazo_vencido
    run = abrir_execucao
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1', 'produto' => 'auto' })
    run
  end

  # O PORTAL JÁ TINHA FECHADO E O COMPARATIVO JÁ TINHA SAÍDO — só o `finish!('done')` não chegou a
  # rodar. `Comparativo#concluir_passada` grava `comparativo_enviado` na passada que encontra o comparativo
  # aceito e o `record_attempt!` o persiste; o `finish_done` vem DEPOIS. Morto o worker entre os dois (deploy, hard shutdown do
  # Sidekiq), a linha fica `running` com tudo já entregue ao cliente.
  def cotacao_fechada_no_portal_com_a_linha_abandonada
    run = abrir_execucao
    stub_comparativo_pdf
    preco = publicar!(run, preco_ao_cliente)
    run.record_delivery!
    comparativo = publicar!(run, comparativo_do_portal)
    run.record_delivery!
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'quote_id' => 'cot-1',
                                  cotacao::DELIVERED_KEY => ['4'], cotacao::PDF_SENT_KEY => true,
                                  cotacao::FECHADO_KEY => true, cotacao::PRECOS_KEY => [preco],
                                  cotacao::PRECO_LEGADO_KEY => false,
                                  cotacao::COMPARATIVO_KEY => comparativo, 'produto' => 'auto' })
    run
  end

  # O que o cliente já tinha na tela ANTES do encerramento, nesse estado.
  def tela_de_quem_recebeu_tudo
    [preco_ao_cliente, cotacao::Comparativo::LEGENDA]
  end

  # A FRASE PARCIAL NÃO SAI PARA QUEM RECEBEU TUDO, PELAS DUAS PORTAS DE ENCERRAMENTO.
  #
  # O fecho da cotação afirmava "sempre sobra, por construção", e a construção mentia: com
  # `comparativo_enviado` no handle, o cliente tem os preços E o comparativo, e "algumas seguradoras
  # não responderam a tempo" descreve uma tela que ele não está vendo. O silêncio é a resposta certa
  # — ele já tem tudo, e não há nada de novo a dizer.
  it 'a cotacao que ja entregou tudo fecha em silencio quando o prazo estoura' do
    # Arrange
    run = cotacao_fechada_no_portal_com_a_linha_abandonada

    # Act — a porta do MOTOR (`fail_run`)
    described_class.new.perform(run.id, 5)

    # Assert — nem frase parcial, nem comparativo repetido, nem chamada nova ao portal: a tela do
    # cliente é a mesma de antes do encerramento
    expect(bot_contents).to eq(tela_de_quem_recebeu_tudo)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  it 'o varredor tambem fecha em silencio a cotacao que ja entregou tudo' do
    # Arrange
    run = cotacao_fechada_no_portal_com_a_linha_abandonada
    run.update!(expires_at: 10.minutes.ago)

    # Act — a porta do VARREDOR (`ReapStaleRunsJob`)
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq(tela_de_quem_recebeu_tudo)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  # SEM LOTE DE PREÇO, O PRAZO PEDE O COMPARATIVO PARA QUEM TEM PREÇO GUARDADO (fatia 3 do #420). A consulta não
  # publicou nada, o contador está em zero, e ainda assim o cliente recebe o comparativo e o fecho de quem tem
  # resultado: exigir um lote aceito deixaria toda cotação que acaba pelo prazo sem PDF.
  it 'a cotacao com preco guardado e nada na tela recebe o comparativo e o fecho quando o prazo estoura' do
    run = cotacao_com_preco_guardado_e_nada_publicado
    expect(bot_contents).to be_empty
    run.update!(expires_at: 1.minute.ago)
    stub_comparativo_pdf

    described_class.new.perform(run.id, 5)

    expect(bot_contents).to eq([cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  # E O PDF QUE NÃO SAI NO ENCERRAMENTO: o fecho diz que os valores podem ser pedidos na conversa.
  it 'a cotacao com preco guardado cujo comparativo nao sai no prazo diz que os valores podem ser pedidos' do
    run = cotacao_com_preco_guardado_e_nada_publicado
    run.update!(expires_at: 1.minute.ago)
    stub_request(:get, 'https://exemplo.test/comparativo-mock.pdf').to_return(status: 404, body: 'x')

    described_class.new.perform(run.id, 5)

    expect(bot_contents).to eq([cotacao.valores_message(run.arguments)])
  end

  # NÃO-REGRESSÃO DA COTAÇÃO (Codex, P2). O `fail_run` deixou de filtrar por `delivered_count` e
  # passou a oferecer o encerramento à ferramenta SEMPRE — era o único jeito de um arquivo já gerado
  # sair quando o prazo estoura antes da primeira entrega. A cotação se protege
  # sozinha: `closing_deliveries` não pede comparativo sem preço aceito, então a execução que morre sem
  # preço nenhum continua fechando com a frase de falha, sem comparativo e sem pedir nada ao portal
  # (se pedisse, o PDF do conector `mock` não está stubbado neste exemplo e a mensagem seria outra).
  it 'a cotacao que morre sem preco nenhum nao passa a mandar comparativo' do
    # Arrange
    run = cotacao_sem_preco_e_prazo_vencido

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — uma mensagem só, a de falha; nada do comparativo
    expect(bot_contents).to eq([cotacao.failure_message])
    expect(bot_contents).not_to include(cotacao::Comparativo::LEGENDA)
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', delivered_count: 0)
  end

  # O VARREDOR NÃO PEDE O COMPARATIVO AO PORTAL , e aqui pelo caminho REAL: a mesma
  # cotação abandonada, fechada pelo `ReapStaleRunsJob`. Gerar o comparativo é login mais uma chamada
  # de até 60 s, e o varredor processa até 500 linhas em sequência num cron com 25 s de shutdown —
  # morto no meio, o resto do lote espera a varredura seguinte, 10 min depois. O cliente
  # continua com os preços que leu e recebe o fecho honesto. (O PDF do conector `mock` não está
  # stubbado neste exemplo: se ele fosse pedido, sairia o link de reserva e este exemplo cairia.)
  it 'o varredor fecha a cotacao abandonada sem pedir o comparativo ao portal' do
    # Arrange
    run = cotacao_com_preco_entregue_e_prazo_vencido
    run.update!(expires_at: 10.minutes.ago)

    # Act
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::FECHO_COM_RESULTADO])
    expect(conversation.messages.reload.none? { |mensagem| mensagem.attachments.any? }).to be(true)
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  # A JANELA DO DEPLOY NÃO PODE CUSTAR O COMPARATIVO NEM O FECHO (P1 da rodada 3, 12/09/2026).
  #
  # A rodada 2 fez o fecho perguntar pela MENSAGEM, e a pergunta se faz pelo token que a passada
  # emissora grava no handle. A execução que atravessa o deploy não tem esse token: ela emitiu o
  # preço na versão anterior. O fecho lia "nenhum preço chegou" e o resultado era o pior dos dois
  # mundos — nem comparativo, nem uma palavra — para quem já tinha recebido preço. Ou seja: durante
  # a vida das execuções em voo, o incidente de 08/09/2026 voltava exatamente como era.
  #
  # A saída é a mesma que `portal_fechado?` já usa três métodos abaixo: a marca ANTIGA vale como
  # prova legada, e só quando a nova está AUSENTE do handle. Guardado assim, o fallback alcança só
  # a linha legada — qualquer execução posterior ao deploy que emita preço grava a chave —, então
  # ele não reabre a frase falsa que a rodada 1 corrigiu.
  it 'a execucao que atravessou o deploy recebe o comparativo E o fecho' do
    # Arrange — handle da versão anterior, preço na tela do cliente
    run = cotacao_da_janela_do_deploy
    stub_comparativo_pdf

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — o comparativo sai, e o fecho é o de quem tem preço e ficou faltando coisa
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  # A LISTA DO ACEITE ACUMULA ENTRE PASSADAS, E O HANDLE DA FERRAMENTA NÃO PASSA POR CIMA DELA.
  #
  # Ela é escrita NO MEIO da passada (no aceite de cada entrega) e o handle que a ferramenta devolve
  # foi lido no COMEÇO dela. Fora das marcas do motor (`AsyncRunJob::MARCAS`), o `record_attempt!`
  # do fim da passada regravaria a lista com a cópia velha — o token recém-aceito sumiria, e o fecho
  # de uma linha abandonada depois diria que o comparativo não chegou.
  it 'a lista do aceite acumula entre passadas e sobrevive ao handle da ferramenta' do
    # Arrange — cotação em andamento, com um aceite anterior já registrado na linha
    run = abrir_execucao(expires_at: 3.minutes.from_now)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'produto' => 'auto',
                                  'quote_id' => cotacao_em_andamento_no_mock })
    stub_comparativo_pdf
    described_class.new.perform(run.id, 1)
    run.reload.registrar_entrega_aceita!('aceite-anterior')

    # Act — a passada que fecha a cotação e entrega o comparativo
    travel_to(Autonomia::Insurance::Connector::Mock::COMPLETE_AFTER.from_now) { described_class.new.perform(run.id, 2) }

    # Assert — o aceite anterior continua lá, e o do comparativo entrou
    aceitas = Array(run.reload.handle[Autonomia::Agents::Tools::EntregaAceita::CHAVE])
    expect(aceitas).to eq(['aceite-anterior', run.handle[cotacao::COMPARATIVO_KEY]])
    expect(run.delivered_count).to eq(1)
  end

  # E PELA PORTA DO VARREDOR TAMBÉM (rodada 4). A linha que atravessa o deploy é fechada pelas
  # DUAS portas, e o varredor é a mais provável das duas: um deploy mata a corrente de jobs, e é
  # ele quem encontra a linha 10 min depois. Lá não há comparativo (não se começa trabalho novo no
  # portal), mas a palavra ao cliente é a mesma — e sem este exemplo nada trava o caminho.
  it 'o varredor tambem fecha com a frase certa a execucao que atravessou o deploy' do
    # Arrange
    run = cotacao_da_janela_do_deploy
    run.update!(expires_at: 10.minutes.ago)

    # Act
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert — sem comparativo (o PDF do `mock` nem está stubbado aqui), com o fecho de quem tem preço
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  # ENTREGA ADIADA É ENTREGA ACEITA (P1 do verificador cego, rodada 3 → 4).
  #
  # Com a cadeia de entrega humanizada do turno ainda aberta, o publicador devolve `deferred`: a
  # mensagem AINDA não existe, e ela sai sozinha pelo `AsyncPublishJob` segundos depois. O fecho que
  # perguntava à MENSAGEM lia "nenhum preço chegou" nessa janela — não pedia o comparativo e
  # publicava frase nenhuma (a parcial exige resultado, e a de falha exige contador zero). O cliente
  # recebia os preços pelo job adiado e mais nada: na `main` saíam três entregas.
  #
  # O gatilho é o adiamento NORMAL (até 90 s), não uma avaria: a passada que entrega o preço com a
  # cadeia aberta e a passada seguinte, que encontra o prazo vencido, ficam a um intervalo de
  # distância uma da outra.
  it 'a entrega ADIADA conta como resultado: o cliente recebe comparativo e fecho' do
    # Arrange — cadeia do turno em curso (um pedaço esperado, nenhum postado) e cotação respondendo
    run = abrir_execucao(expires_at: 3.minutes.from_now, cadeia: 1, origem: 4242)
    run.record_attempt!(handle: { described_class::SUBMITTED_KEY => true, 'produto' => 'auto',
                                  'quote_id' => cotacao_em_andamento_no_mock })
    stub_comparativo_pdf

    # Act 1 — a consulta grava o preço e não publica nada
    described_class.new.perform(run.id, 1)
    expect(bot_contents).to be_empty
    expect(run.reload.delivered_count).to eq(0)

    # Act 2 — o prazo estoura antes de a publicação adiada sair
    run.update!(expires_at: 1.minute.ago)
    described_class.new.perform(run.id, 5)

    # Act 3 — a cadeia do turno termina (o pedaço dela é a primeira mensagem do bot) e o que ficou
    # adiado sai
    fechar_cadeia_do_turno(4242)
    expect(bot_contents).to eq(['deixa eu consultar aqui'])
    drenar_publicacoes_adiadas

    # Assert — o comparativo adiado e o fecho encadeado a ele, nesta ordem
    expect(bot_contents.drop(1)).to eq([cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  # O HISTÓRICO MISTO (P1 do verificador cego e apontamento do Codex, rodada 3 → 4).
  #
  # A linha atravessou o deploy com um preço JÁ na tela do cliente e, depois dele, emite um preço
  # novo que a publicação RECUSA (erro transitório do publicador, conversa que mudou de caixa,
  # agente desligado no meio). Com a prova legada guardada pela PRESENÇA da chave nova, essa
  # emissão recusada fazia a linha passar a ser julgada só pelo token novo — e o preço antigo, que
  # está na tela, sumia da conta: nem comparativo, nem uma palavra.
  it 'a linha legada que emite um preco novo recusado nao perde o preco que ja esta na tela' do
    # Arrange — preço da versão anterior na tela; o mock ainda tem a Mapfre para entregar
    run = cotacao_legada_com_preco_antigo_na_tela
    recusar_publicacao_de('Mapfre')
    stub_comparativo_pdf

    # Act 1 — a consulta emite o preço novo e o publicador recusa
    described_class.new.perform(run.id, 1)
    expect(bot_contents).to eq([preco_ao_cliente])

    # Act 2 — o prazo estoura
    run.update!(expires_at: 1.minute.ago)
    described_class.new.perform(run.id, 5)

    # Assert — o cliente continua com o preço antigo, e recebe o comparativo e o fecho dele
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado')
  end

  # A PROVA LEGADA JULGAVA EMISSÃO, E PRECISA JULGAR ACEITE (P1 da rodada 5).
  #
  # `entregues` avança na passada que EMITE, mesmo com a publicação recusada — é o mesmo defeito da
  # rodada 1, e a rodada 4 o deixou aberto para a linha legada: com o contador em ZERO, esta PR
  # publicava o comparativo (login mais uma chamada paga ao portal) e a frase "algumas seguradoras
  # não responderam a tempo, os preços acima são os que chegaram", sem nada acima. A `main`, no
  # mesmo estado, dizia a frase honesta de falha — que é o que ela volta a dizer.
  #
  # O PORTAL NÃO É CHAMADO, e isto se prova por construção: o PDF do conector `mock` não está
  # stubbado aqui, então qualquer pedido de comparativo acrescentaria o link de reserva à lista.
  # DESDE A FATIA 3 DO #420 o preço guardado basta para o comparativo sair no prazo: o cliente sem nada na tela
  # recebe o PDF e o fecho de quem tem resultado, e não a frase de falha sobre uma cotação que deu preço.
  it 'a linha legada sem aceite nenhum recebe o comparativo e o fecho' do
    # Arrange
    run = cotacao_legada_sem_aceite_nenhum
    stub_comparativo_pdf

    # Act — a porta do MOTOR
    described_class.new.perform(run.id, 5)

    # Assert
    expect(bot_contents).to eq([cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'prazo_esgotado', delivered_count: 0)
  end

  # A PORTA DO VARREDOR NÃO ALCANÇA ESTE DEFEITO, e isso foi MEDIDO: as mutações que devolvem a
  # prova por emissão (M31, M32) SOBREVIVEM aqui. Lá `trabalho_novo` é falso, então
  # `closing_deliveries` devolve `[]` sem chegar ao predicado, e o portão externo do fecho é
  # `delivered_count` — zero nesta linha, o que já leva à frase de falha. O exemplo fica como trava
  # da PORTA (o estado existe em produção e ela tem de continuar honesta), não como prova da
  # correção: quem a prova é o exemplo do motor, acima.
  it 'o varredor fecha a linha legada sem aceite nenhum dizendo que os valores podem ser pedidos' do
    # Arrange
    run = cotacao_legada_sem_aceite_nenhum
    run.update!(expires_at: 10.minutes.ago)

    # Act — a porta do VARREDOR, que não pede o comparativo
    Autonomia::Agents::Tools::ReapStaleRunsJob.new.perform

    # Assert
    expect(bot_contents).to eq([cotacao.valores_message(run.arguments)])
    expect(run.reload).to have_attributes(status: 'failed', failure_code: 'execucao_abandonada')
  end

  it 'publica o fecho de quem tem resultado quando o prazo estoura com preço ja entregue' do
    # Arrange — o comparativo do conector `mock` responde como PDF (entrega 11: sai como arquivo)
    run = cotacao_com_preco_entregue_e_prazo_vencido
    stub_comparativo_pdf

    # Act
    described_class.new.perform(run.id, 5)

    # Assert — o preço que o cliente já tinha, depois o comparativo (o que ainda vale entregar) e
    # por fim o fecho DA COTAÇÃO
    expect(bot_contents).to eq([preco_ao_cliente, cotacao::Comparativo::LEGENDA, cotacao::FECHO_COM_RESULTADO])
    # O FECHO É O DA COTAÇÃO, e não o genérico do `Base` — o defeito da entrega 4 era esse. E
    # ele não conta ao cliente quantas seguradoras ficaram pelo caminho (decisão do CEO,
    # 12/09/2026): esse número é de quem opera, e já está no Super Admin.
    expect(bot_contents.last).not_to eq(Autonomia::Agents::Tools::Native::Base.closing_message)
    expect(bot_contents.join(' ')).not_to include('consultas')
    expect(bot_contents.last).not_to include('não responderam')
    expect(run.reload.status).to eq('failed')
  end

  # AS FRASES DO ESPECIALISTA PELO CAMINHO DO MOTOR (12/09/2026). Os dois textos que o motor publica
  # sem instância — o aviso de espera na primeira passada e o fecho no encerramento — passam a ser
  # resolvidos a partir dos ARGUMENTOS da execução. Sem os argumentos viajando até lá, o cliente
  # continua lendo a constante e o especialista escreve para ninguém.
  describe 'as frases do especialista nos textos que o motor publica' do
    let(:escritas) do
      { 'espera' => 'Já pedi os preços e volto aqui assim que tiver notícia.',
        'fecho_com_resultado' => 'Fechei a busca por aqui. Posso retomar quando você quiser.' }
    end

    def abrir_com_frases(expires_at:, notificar: false)
      run = Autonomia::Agents::ToolRun.open!(
        agent: agent, slug: cotacao.slug,
        arguments: { 'produto' => 'auto', 'cpf' => '04297912678', 'cep' => '31110210',
                     'vehicle' => { 'plate' => 'ABC1D23' }, 'frases_ao_cliente' => escritas },
        scope: { conversation_id: conversation.id, agent_inbox_id: agent_inbox.id }
      )
      run.promote!(expected_chunks: 0, notify_customer: notificar, expires_at: expires_at)
      run
    end

    it 'o aviso de espera sai com a frase que o especialista escreveu' do
      run = abrir_com_frases(expires_at: 5.minutes.from_now, notificar: true)

      described_class.new.perform(run.id, 0)

      expect(bot_contents.first).to eq(escritas['espera'])
    end

    it 'o fecho de quem tem resultado sai com a frase que o especialista escreveu' do
      run = abrir_com_frases(expires_at: 1.minute.ago)
      stub_comparativo_pdf
      publicar!(run, preco_ao_cliente)
      run.record_delivery!
      run.merge_handle!({ Autonomia::Agents::ToolRun::SUBMITTED_KEY => true, 'quote_id' => 'abc:1',
                          cotacao::DELIVERED_KEY => ['43'], cotacao::PRECO_LEGADO_KEY => false,
                          cotacao::PRECOS_KEY => [Autonomia::Agents::Tools::EntregaPublicada.token_de(run, preco_ao_cliente)] })

      described_class.new.perform(run.id, 5)

      expect(bot_contents.last).to eq(escritas['fecho_com_resultado'])
    end
  end
end
