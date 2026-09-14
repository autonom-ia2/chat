require 'rails_helper'

# A FERRAMENTA DA LIA QUE VÊ O RESULTADO DA COTAÇÃO (fatia 2 do #420) — a ferramenta sozinha, sobre linhas
# reais de `autonomia_agent_tool_runs`. O caminho pelo turno e pelo motor está em
# `answerer_resultado_da_cotacao_spec`. Dados sintéticos.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuoteResult do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 90) }
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:guardar) { Autonomia::Insurance::ResultadoPorSeguradora }
  let(:risco) { { 'kind' => 'risco', 'text' => 'Tipo de veículo não aceito.' } }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def cotou(code, name, amount)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total',
                     'installments' => { 'count' => 10, 'amount' => (amount / 10).round(2) } } }
  end

  def recusou(code, name, status: 'declined', reason: nil)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status, 'reason' => reason }.compact
  end

  def correndo(code, name)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'running' }
  end

  def ofertas_padrao
    [cotou('8', 'Porto Seguro', 2119.18), cotou('5', 'Allianz', 2402.55), recusou('19', 'Sancor', reason: risco),
     recusou('13', 'Mitsui', status: 'auth_required', reason: risco)]
  end

  # Uma execução de `cotar_seguro` da conversa, com o resultado guardado destas ofertas (ou sem a chave).
  def cotacao_com(status:, ofertas: ofertas_padrao, guardado: true, handle: {}, criada: Time.current)
    base = { 'quote_id' => 'q-1:1' }
    base[cotacao::RESULTADO_KEY] = guardar.unir({}, ofertas) if guardado
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: status,
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                       arguments: {}, handle: base.merge(handle), created_at: criada)
  end

  def no_turno(seguradora = nil)
    described_class.new(agent: agent, params: { 'seguradora' => seguradora }, delivery: delivery)
  end

  # -> o texto que o modelo recebe no turno: o da conferência, ou o do aceite quando a execução abre.
  def ao_modelo(seguradora = nil)
    ferramenta = no_turno(seguradora)
    ferramenta.precheck&.to_s || ferramenta.aceite
  end

  describe 'o que chega ao modelo no turno, sem preço a publicar (nenhuma execução aberta)' do
    it 'sem cotação na conversa' do
      conferencia = no_turno.precheck

      expect(conferencia.to_s).to eq(described_class::SEM_COTACAO)
      expect(conferencia.motivo).to eq('resultado_respondido_no_turno')
    end

    it 'cotação encerrada antes desta versão, sem o resultado guardado' do
      cotacao_com(status: 'done', guardado: false)

      expect(no_turno.precheck.to_s).to eq(described_class::SEM_RESULTADO)
    end

    # A MAIS NOVA É UMA RECUSA DO `start` (faltou dado): ela nunca teve número no portal, e esconde a anterior
    # com preço. O modelo ouve que ela não chegou às seguradoras, e não que o resultado "não ficou guardado".
    it 'a cotação mais nova encerrada sem número do portal não chegou às seguradoras' do
      cotacao_com(status: 'done', criada: 10.minutes.ago)
      cotacao_com(status: 'done', guardado: false, criada: 1.minute.ago,
                  handle: { 'quote_id' => nil, 'pedido' => 'Qual o ano do veículo?', 'motivo' => 'faltam_dados' })

      expect(no_turno.precheck.to_s).to eq(described_class::NAO_CHEGOU)
      expect(no_turno('Porto').precheck.to_s).to eq(described_class::NAO_CHEGOU)
    end

    it 'a cotação correndo que ainda não recebeu número do portal está ainda sem preço' do
      cotacao_com(status: 'running', guardado: false, handle: { 'quote_id' => nil })

      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO_AINDA)
    end

    # ENVIO INCERTO (terceira rodada de revisão): o job decidiu submeter e o número nunca chegou. O cliente ouviu
    # que um atendente vai conferir, e a cotação pode existir no portal: o modelo não ouve que ela não chegou.
    it 'a cotação encerrada com envio incerto: pode ter chegado às seguradoras, e um atendente vai conferir' do
      incerta = { 'quote_id' => nil, Autonomia::Agents::ToolRun::INTENCOES => 1 }
      run = cotacao_com(status: 'failed', guardado: false, handle: incerta)
      expect(no_turno.precheck.to_s).to eq(described_class::ENVIO_INCERTO)
      expect(no_turno('Porto').precheck.to_s).to eq(described_class::ENVIO_INCERTO)

      run.update!(status: 'running')
      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO_AINDA)
    end

    it 'cotação em voo no deploy, correndo e ainda sem o resultado guardado' do
      cotacao_com(status: 'running', guardado: false)

      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO_AINDA)
    end

    it 'só recusas: ainda correndo, e depois de encerrada' do
      so_recusas = [recusou('19', 'Sancor', reason: risco)]
      run = cotacao_com(status: 'running', ofertas: so_recusas)
      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO_AINDA)

      run.update!(status: 'done')
      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO)
    end

    it 'seguradora sem proposta com o motivo classificado: o nome e a categoria, nunca o texto do portal' do
      cotacao_com(status: 'done')

      texto = no_turno('Sancor').precheck.to_s

      expect(texto).to eq("Sancor não fez proposta nesta cotação. #{described_class::MOTIVOS.fetch('veiculo')}")
      expect(texto).not_to include(risco['text'])
    end

    it 'seguradora recusada pela região: a categoria da região' do
      cotacao_com(status: 'done', ofertas: [recusou('19', 'Sancor', reason: { 'kind' => 'risco', 'text' => 'CEP sem aceitação.' })])

      expect(no_turno('Sancor').precheck.to_s).to eq("Sancor não fez proposta nesta cotação. #{described_class::MOTIVOS.fetch('regiao')}")
    end

    # NENHUM TEXTO DO PORTAL CHEGA AO MODELO (decisão do CEO, sétima rodada): o corpus do conector, no kind e no status
    # que o conector dá, e os textos das revisões. O modelo lê uma de três falas fechadas; a conta e a pessoa, o genérico.
    it 'o modelo nunca recebe texto do portal, em nenhuma mensagem do corpus nem das revisões' do
      genericos = TextosDoMotivo::CONTA + TextosDoMotivo::PESSOA + TextosDoMotivo::REVISOES
      linhas = TextosDoMotivo::CORPUS.map { |linha| linha.first(3) } + genericos.map { |texto| [texto, 'risco', 'declined'] }
      cotacao_com(status: 'done', ofertas: linhas.each_with_index.map do |(texto, kind, status), i|
        recusou(i.to_s, "Seguradora #{i}", status: status, reason: { 'kind' => kind, 'text' => texto })
      end)

      falas = linhas.each_index.map do |i|
        no_turno("Seguradora #{i}").precheck.to_s.delete_prefix("Seguradora #{i} não fez proposta nesta cotação. ")
      end

      expect(falas.uniq - [described_class::SEM_MOTIVO, *described_class::MOTIVOS.values]).to be_empty
      expect(linhas.each_with_index.select { |(texto, _, _), i| falas[i].include?(texto) }).to be_empty
      expect(falas.last(genericos.size)).to all(eq(described_class::SEM_MOTIVO))
    end

    # CREDENCIAL DA CORRETORA: o modelo recebe só que a seguradora não fez proposta.
    it 'seguradora que recusou a credencial: não fez proposta, sem motivo e sem palavra de conta' do
      cotacao_com(status: 'done')

      texto = no_turno('Mitsui').precheck.to_s

      expect(texto).to eq("Mitsui não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
      expect(texto.downcase).not_to match(/login|senha|permiss|credencia|acesso|corretor|risco sem/)
    end

    # A LEITURA SÓ ACEITA AS CATEGORIAS: um motivo guardado em outra forma (texto, ou uma categoria que não existe) não
    # chega ao modelo.
    it 'motivo guardado fora das categorias não chega ao modelo' do
      ['conta', { 'kind' => 'risco', 'text' => 'Senha expirou. Declinando cálculo.' }].each do |guardado|
        entrada = { 'nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => guardado }
        Autonomia::Agents::ToolRun.where(slug: cotacao.slug).delete_all
        cotacao_com(status: 'done', guardado: false, handle: { cotacao::RESULTADO_KEY => { '19' => entrada } })

        expect(Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation.id).motivo('19')).to be_nil
        expect(no_turno('sancor').precheck.to_s).to eq("Sancor não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
      end
    end

    it 'seguradora ainda sem desfecho: ainda não respondeu enquanto corre; não fez proposta depois de encerrada' do
      run = cotacao_com(status: 'running', ofertas: [correndo('47', 'Justos'), recusou('19', 'Sancor')])
      expect(no_turno('Justos').precheck.to_s).to eq('Justos ainda não respondeu, e a cotação continua correndo.')

      run.update!(status: 'failed')
      expect(no_turno('Justos').precheck.to_s).to eq("Justos não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
    end

    it 'o portal já fechou: quem ficou sem desfecho não fez proposta, mesmo com a execução viva' do
      cotacao_com(status: 'running', ofertas: [correndo('47', 'Justos')], handle: { cotacao::FECHADO_KEY => true })

      expect(no_turno('Justos').precheck.to_s).to start_with('Justos não fez proposta')
    end

    it 'nome que não está na cotação: encerrada, e ainda correndo' do
      run = cotacao_com(status: 'done')
      expect(no_turno('Azul').precheck.to_s).to eq(described_class::NAO_ENCONTRADA)

      run.update!(status: 'running')
      expect(no_turno('Azul').precheck.to_s).to eq(described_class::NAO_ENCONTRADA_AINDA)
    end
  end

  describe 'o que chega ao modelo no turno, com preço a publicar (a execução abre)' do
    it 'o resultado inteiro: a lista sai depois da fala, a cotação ainda corre e há quem não fez proposta' do
      cotacao_com(status: 'running')
      ferramenta = no_turno

      expect(ferramenta.precheck).to be_nil
      expect(ferramenta.aceite.split("\n"))
        .to eq([described_class::LISTA_DEPOIS, described_class::AINDA_CORRENDO, described_class::HA_SEM_PROPOSTA])
    end

    it 'o resultado inteiro de cotação encerrada, só com preços, sem bônus' do
      cotacao_com(status: 'done', ofertas: [cotou('8', 'Porto Seguro', 2119.18)], handle: { cotacao::SEM_BONUS_KEY => true })

      expect(no_turno.aceite.split("\n")).to eq([described_class::LISTA_DEPOIS, described_class::SEM_BONUS])
    end

    it 'uma seguradora com preço' do
      cotacao_com(status: 'done')
      ferramenta = no_turno('a porto')

      expect(ferramenta.precheck).to be_nil
      expect(ferramenta.aceite).to include(described_class::LISTA_DEPOIS,
                                           'Porto Seguro fez proposta: o preço dela sai na lista depois da sua mensagem.')
    end

    it 'uma com preço e uma sem proposta no mesmo pedido: as duas falas, e só a com preço é publicada' do
      cotacao_com(status: 'done')
      ferramenta = no_turno('Sancor e Porto')

      expect(ferramenta.precheck).to be_nil
      expect(ferramenta.aceite).to include('Porto Seguro fez proposta', 'Sancor não fez proposta nesta cotação.',
                                           described_class::MOTIVOS.fetch('veiculo'))
      expect(ferramenta.aceite).not_to include(risco['text'])
      expect(ferramenta.start[described_class::CODIGOS_KEY]).to eq(['8'])
    end
  end

  # NENHUM TEXTO AO MODELO TEM VALOR DE PRÊMIO. Varre todos os estados de cima.
  it 'nenhum texto ao modelo tem valor, em nenhum estado' do
    cotacao_com(status: 'running', handle: { cotacao::SEM_BONUS_KEY => true })
    textos = [nil, 'Porto', 'Allianz', 'Sancor', 'Mitsui', 'Sancor e Porto', 'Azul'].map { |seguradora| ao_modelo(seguradora) }

    expect(textos).to all(be_present)
    expect(textos.join("\n")).not_to match(/R\$|2119|2\.119|2402|2\.402|211,92|240,26/)
  end

  describe 'qual cotação ela lê' do
    Autonomia::Insurance::ResultadoDaCotacao::FORA.each do |status|
      it "a mais nova que não está #{status}" do
        cotacao_com(status: 'done', ofertas: [cotou('8', 'Porto Seguro', 2119.18)], criada: 10.minutes.ago)
        cotacao_com(status: status, ofertas: [cotou('5', 'Allianz', 2402.55)], criada: 1.minute.ago)

        expect(no_turno.start[described_class::CODIGOS_KEY]).to eq(['8'])
      end
    end

    it 'a mais nova encerrada sem preço vence a anterior com preço' do
      cotacao_com(status: 'done', ofertas: [cotou('8', 'Porto Seguro', 2119.18)], criada: 10.minutes.ago)
      cotacao_com(status: 'failed', ofertas: [recusou('19', 'Sancor')], criada: 1.minute.ago)

      expect(no_turno.precheck.to_s).to eq(described_class::SEM_PRECO)
    end

    it 'não lê cotação de outra conversa' do
      outra = create(:conversation, account: account, inbox: inbox)
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: cotacao.slug, status: 'done',
                                         conversation_id: outra.id, execution_key: SecureRandom.uuid, arguments: {},
                                         handle: { cotacao::RESULTADO_KEY => guardar.unir({}, ofertas_padrao) })

      expect(no_turno.precheck.to_s).to eq(described_class::SEM_COTACAO)
    end
  end

  describe 'a publicação, na passada do motor' do
    let(:execucao) do
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: described_class.slug, status: 'running',
                                         conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                         arguments: { 'seguradora' => nil }, handle: {})
    end

    def no_motor(seguradora = nil)
      execucao.update!(arguments: { 'seguradora' => seguradora })
      described_class.new(agent: agent, params: execucao.arguments, run: execucao)
    end

    it 'publica os itens escritos por QuoteOffers.item, na ordem da lista de preços, e pede a consulta seguinte logo' do
      cotacao_com(status: 'done')
      handle = no_motor.start

      progresso = no_motor.poll(handle: handle, attempt: 1)

      itens = [cotou('8', 'Porto Seguro', 2119.18), cotou('5', 'Allianz', 2402.55)].map do |oferta|
        Autonomia::Insurance::QuoteOffers.item(oferta)
      end
      expect(progresso).to be_running
      expect(progresso.confirmar_logo?).to be(true)
      expect(progresso.deliveries).to eq([itens.join("\n\n")])
    end

    # A LISTA SAI ATÉ SER ACEITA (decisão do CEO, sétima rodada): a passada seguinte encerra só com o aceite gravado ou
    # com a mensagem da lista na conversa; sem nenhum dos dois, a lista sai de novo, no intervalo da tentativa.
    it 'a passada seguinte encerra com a lista aceita ou já publicada, e publica de novo sem nenhum dos dois' do
      cotacao_com(status: 'done')
      execucao.update!(handle: no_motor.start)
      lista = no_motor.poll(handle: execucao.handle, attempt: 1).deliveries.first
      token = execucao.reload.handle.dig(described_class::LISTA_KEY, 'token')

      expect(token).to eq(Autonomia::Agents::Tools::EntregaPublicada.token_de(execucao, lista))
      de_novo = no_motor.poll(handle: execucao.handle, attempt: 2)
      expect(de_novo).to have_attributes(running?: true, deliveries: [lista], confirmar_logo?: false)

      execucao.registrar_entrega_aceita!(token)
      expect(no_motor.poll(handle: execucao.handle, attempt: 3)).to have_attributes(done?: true, deliveries: [])
    end

    it 'com a mensagem da lista na conversa e o aceite não gravado, a passada seguinte encerra' do
      cotacao_com(status: 'done')
      execucao.update!(handle: no_motor.start)
      no_motor.poll(handle: execucao.handle, attempt: 1)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: create(:agent_bot, account: account), content: 'lista',
                       content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE =>
                                               execucao.reload.handle.dig(described_class::LISTA_KEY, 'token') })

      expect(no_motor.poll(handle: execucao.handle, attempt: 2)).to have_attributes(done?: true, deliveries: [])
    end

    # A ÚLTIMA TENTATIVA, NO ENCERRAMENTO: a lista que ainda vale; nada depois do aceite ou com a cotação trocada.
    it 'closing_deliveries entrega a lista que ainda vale e não foi aceita' do
      cotacao_com(status: 'done', criada: 5.minutes.ago)
      execucao.update!(handle: no_motor.start)

      lista = no_motor.closing_deliveries(execucao.handle, trabalho_novo: false)
      expect(lista).to eq(no_motor.poll(handle: execucao.handle, attempt: 1).deliveries)

      execucao.registrar_entrega_aceita!(execucao.reload.handle.dig(described_class::LISTA_KEY, 'token'))
      expect(no_motor.closing_deliveries(execucao.handle)).to eq([])

      Autonomia::Agents::ToolRun.where(slug: described_class.slug).update_all(handle: execucao.handle.except(described_class::LISTA_KEY)) # rubocop:disable Rails/SkipsModelValidations
      cotacao_com(status: 'running', ofertas: [cotou('3', 'Mapfre', 1999.0)], criada: 1.second.from_now)
      expect(no_motor.closing_deliveries(execucao.reload.handle)).to eq([])
    end

    it 'publica só os itens da seguradora perguntada' do
      cotacao_com(status: 'done')
      handle = no_motor('Allianz').start

      expect(no_motor('Allianz').poll(handle: handle, attempt: 1).deliveries)
        .to eq([Autonomia::Insurance::QuoteOffers.item(cotou('5', 'Allianz', 2402.55))])
    end

    it 'não publica quando outra cotação ficou mais nova depois do start' do
      cotacao_com(status: 'done', criada: 5.minutes.ago)
      handle = no_motor.start
      cotacao_com(status: 'running', ofertas: [cotou('3', 'Mapfre', 1999.0)], criada: 1.second.from_now)

      progresso = no_motor.poll(handle: handle, attempt: 1)

      expect(progresso).to be_done
      expect(progresso.deliveries).to be_empty
    end

    # O QUE A LIA LEU NO TURNO É O QUE SAI (revisão da fatia 2, P2): a Sancor cotou entre o aceite e a primeira
    # passada, e a lista continua sendo a dos códigos gravados na abertura.
    it 'o start devolve os códigos gravados na abertura, sem reler a cotação' do
      fonte = cotacao_com(status: 'running', ofertas: [cotou('8', 'Porto Seguro', 2119.18), correndo('19', 'Sancor')])
      execucao.update!(handle: { described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['8'] })
      depois = guardar.unir(fonte.handle[cotacao::RESULTADO_KEY], [cotou('19', 'Sancor', 1800.0)])
      fonte.update!(handle: fonte.handle.merge(cotacao::RESULTADO_KEY => depois))

      handle = no_motor('Porto e Sancor').start

      expect(handle).to eq(described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['8'])
      expect(no_motor('Porto e Sancor').poll(handle: handle, attempt: 1).deliveries)
        .to eq([Autonomia::Insurance::QuoteOffers.item(cotou('8', 'Porto Seguro', 2119.18))])
    end

    it 'sem abertura gravada, o start lê a cotação agora' do
      fonte = cotacao_com(status: 'done')

      expect(no_motor('Allianz').start).to eq(described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['5'])
    end

    it 'publicacao_vale? enquanto a cotação lida for a mais nova, e não depois' do
      cotacao_com(status: 'done', criada: 5.minutes.ago)
      execucao.update!(handle: no_motor.start)
      expect(described_class.publicacao_vale?(execucao)).to be(true)

      cotacao_com(status: 'running', ofertas: [cotou('3', 'Mapfre', 1999.0)], criada: 1.second.from_now)
      expect(described_class.publicacao_vale?(execucao)).to be(false)
      expect(described_class.publicacao_vale?(execucao.tap { |run| run.handle = {} })).to be(false)
    end
  end

  # O HANDLE DE ABERTURA: o que a Lia leu no turno vai para a linha que a abertura cria, e só isso.
  describe 'o handle de abertura' do
    it 'grava a cotação lida e os códigos com preço do pedido, e nada quando não há preço' do
      fonte = cotacao_com(status: 'done')

      expect(no_turno('Allianz').handle_de_abertura)
        .to eq(described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['5'])
      expect(no_turno('Sancor').handle_de_abertura).to eq({})
    end

    it 'não leva os códigos de outra execução da ferramenta' do
      fonte = cotacao_com(status: 'done')
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: described_class.slug, status: 'pending',
                                         conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {},
                                         handle: { described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['8'] })

      expect(no_turno('Allianz').handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['5'])
    end
  end

  # UMA LISTA POR PEDIDO, E NUNCA A MESMA DUAS VEZES (terceira rodada de revisão): a passada que publica leva
  # os códigos das execuções anteriores sem mensagem, e a lista sem mensagem de uma anterior não sai depois que
  # uma mais nova foi despachada.
  describe 'as listas de execuções anteriores da ferramenta' do
    let(:fonte) { cotacao_com(status: 'done') }
    let(:porto) { cotou('8', 'Porto Seguro', 2119.18) }
    let(:allianz) { cotou('5', 'Allianz', 2402.55) }

    # Uma execução da ferramenta da Lia na conversa. `origem` é a mensagem do turno que a abriu (71, se omitida);
    # `expires_at` presente diz que o turno a promoveu.
    def exibicao(status:, codigos:, cotacao_lida: fonte.id, **linha)
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: described_class.slug, status: status,
                                         conversation_id: conversation.id, execution_key: SecureRandom.uuid, arguments: {},
                                         sequence: linha.fetch(:sequence, 0), origin_message_id: linha.fetch(:origem, 71),
                                         expires_at: linha[:expires_at],
                                         handle: { described_class::EXECUCAO_KEY => cotacao_lida, described_class::CODIGOS_KEY => codigos })
    end

    def lista_da(run, pendente:)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: create(:agent_bot, account: account), content: 'lista',
                       content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => "#{run.execution_key}:abc",
                                             'autonomia_envio_pendente' => pendente })
    end

    def publicado_por(run)
      ferramenta = described_class.new(agent: agent, params: run.arguments, run: run)
      ferramenta.poll(handle: run.handle, attempt: 1).deliveries
    end

    def itens(*ofertas)
      [ofertas.map { |oferta| Autonomia::Insurance::QuoteOffers.item(oferta) }.join("\n\n")]
    end

    it 'a lista leva os códigos da anterior supersedida e da encerrada, sem mensagem, sobre a mesma cotação' do
      exibicao(status: 'superseded', codigos: ['8'])
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(porto, allianz))

      Autonomia::Agents::ToolRun.where(slug: described_class.slug).delete_all
      exibicao(status: 'done', codigos: ['8'])
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(porto, allianz))
    end

    it 'a leitura para na anterior que virou mensagem' do
      exibicao(status: 'done', codigos: ['8'])
      exibicao(status: 'done', codigos: ['5'], sequence: 1)
      atual = exibicao(status: 'running', codigos: ['5'])

      expect(publicado_por(atual)).to eq(itens(allianz))
    end

    it 'leva a anterior que falhou; não leva a de outra cotação, a descartada nem a barrada' do
      exibicao(status: 'superseded', codigos: ['8'], cotacao_lida: fonte.id + 1000)
      %w[discarded blocked].each { |status| exibicao(status: status, codigos: ['8']) }
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(allianz))

      Autonomia::Agents::ToolRun.where(slug: described_class.slug).delete_all
      exibicao(status: 'failed', codigos: ['8'])
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(porto, allianz))
    end

    it 'segue lendo depois das que não leva' do
      exibicao(status: 'done', codigos: ['8'])
      exibicao(status: 'discarded', codigos: ['5'])
      atual = exibicao(status: 'running', codigos: ['5'])

      expect(publicado_por(atual)).to eq(itens(porto, allianz))
    end

    # A LISTA ANTERIOR SÓ CONTA COMO LEVADA DEPOIS DE A NOVA SER ACEITA (decisão do CEO, sétima rodada): antes, uma falha
    # na publicação da nova perderia as duas.
    it 'a lista levada só barra a anterior depois de a nova ser aceita ou publicada' do
      anterior = exibicao(status: 'done', codigos: ['8'])
      mais_nova = exibicao(status: 'running', codigos: ['5'])

      publicado_por(mais_nova)
      lista = mais_nova.reload.handle[described_class::LISTA_KEY]
      expect(lista).to include('codigos' => %w[8 5], 'levadas' => [anterior.id])
      expect(described_class.publicacao_vale?(anterior)).to be(true)

      mais_nova.registrar_entrega_aceita!(lista['token'])
      expect(described_class.publicacao_vale?(anterior)).to be(false)
    end

    it 'a lista levada pela nova que já é mensagem barra a anterior, mesmo sem o aceite gravado' do
      anterior = exibicao(status: 'done', codigos: ['8'])
      mais_nova = exibicao(status: 'running', codigos: ['5'])
      publicado_por(mais_nova)

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       sender: create(:agent_bot, account: account), content: 'lista',
                       content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE =>
                                               mais_nova.reload.handle.dig(described_class::LISTA_KEY, 'token') })

      expect(described_class.publicacao_vale?(anterior)).to be(false)
    end

    # A LISTA LEVADA POR UMA QUE NÃO PUBLICOU (sexta rodada de revisão): o varredor abandonou o envio pendente de A depois
    # de B levá-la (a marca sai, e A parece entregue), e a lista de B não saiu. C leva a lista inteira de B, com A.
    it 'leva a lista inteira da anterior, com o que ela já tinha levado' do
      a = exibicao(status: 'done', codigos: ['8'], sequence: 1)
      lista_da(a, pendente: false)
      b = exibicao(status: 'done', codigos: ['5'])
      b.update!(handle: b.handle.merge(described_class::LISTA_KEY => { 'codigos' => %w[5 8], 'levadas' => [a.id], 'token' => 'b' }))
      c = exibicao(status: 'running', codigos: ['5'])

      expect(publicado_por(c)).to eq(itens(porto, allianz))
      expect(c.reload.handle.dig(described_class::LISTA_KEY, 'levadas')).to eq([b.id])
    end

    # A LISTA ANTERIOR QUE VIROU MENSAGEM DEPOIS DE ESTA ABRIR (a publicação adiada que chegou ao teto antes da leitura
    # desta): o cliente a recebeu depois de pedir de novo, e ela é descontada desta.
    it 'desconta os códigos da anterior entregue depois de esta abrir, e encerra quando não sobra nada' do
      anterior = exibicao(status: 'done', codigos: ['8'], sequence: 1)
      atual = exibicao(status: 'running', codigos: %w[8 5])
      atual.update_columns(created_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
      lista_da(anterior, pendente: false)
      expect(publicado_por(atual.reload)).to eq(itens(allianz))

      atual.update_columns(status: 'discarded') # rubocop:disable Rails/SkipsModelValidations
      so_porto = exibicao(status: 'running', codigos: ['8'])
      so_porto.update_columns(created_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.new(agent: agent, params: {}, run: so_porto.reload).poll(handle: so_porto.handle, attempt: 1)).to be_done
    end

    it 'não desconta a anterior entregue antes de esta abrir: a leitura para nela' do
      anterior = exibicao(status: 'done', codigos: ['8'], sequence: 1)
      lista_da(anterior, pendente: false)
      Message.where(conversation_id: conversation.id).update_all(created_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
      atual = exibicao(status: 'running', codigos: %w[8 5])

      expect(publicado_por(atual)).to eq(itens(porto, allianz))
    end

    it 'a mais nova que não levou a lista, sobre outra cotação, não barra' do
      anterior = exibicao(status: 'done', codigos: ['8'])
      outra = exibicao(status: 'running', codigos: ['5'], cotacao_lida: fonte.id + 1000)

      publicado_por(outra)

      expect(described_class.publicacao_vale?(anterior)).to be(true)
    end

    it 'a lista sem mensagem continua valendo com uma mais nova despachada que ainda não publicou' do
      anterior = exibicao(status: 'done', codigos: ['8'])
      exibicao(status: 'running', codigos: ['5'])

      expect(described_class.lista_entregue?(anterior)).to be(false)
      expect(described_class.publicacao_vale?(anterior)).to be(true)
    end

    # A SUPERSEDIDA DE OUTRO TURNO QUE NUNCA FOI DESPACHADA (quarta rodada de revisão): o turno dela não falou, e a
    # lista dela não é promessa.
    it 'a supersedida de outro turno que nunca foi despachada não entra; a despachada e a do mesmo turno entram' do
      exibicao(status: 'superseded', codigos: ['8'], origem: 70)
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(allianz))

      Autonomia::Agents::ToolRun.where(slug: described_class.slug).delete_all
      exibicao(status: 'superseded', codigos: ['8'], origem: 70, expires_at: 5.minutes.from_now)
      atual = exibicao(status: 'running', codigos: ['5'])
      expect(publicado_por(atual)).to eq(itens(porto, allianz))
    end

    # A LISTA COM PENDÊNCIA DE ENVIO (quarta rodada de revisão): está no banco e o cliente não a recebeu. Ela entra na
    # lista da mais nova, e a retomada do envio dela é barrada.
    it 'a lista com pendência de envio não é entregue: a retomada vale até a lista que a leva ser aceita' do
      anterior = exibicao(status: 'done', codigos: ['8'], sequence: 1)
      lista_da(anterior, pendente: true)
      atual = exibicao(status: 'running', codigos: ['5'])

      expect(described_class.lista_entregue?(anterior)).to be(false)
      expect(publicado_por(atual)).to eq(itens(porto, allianz))
      expect(described_class.publicacao_vale?(anterior)).to be(true)

      atual.registrar_entrega_aceita!(atual.reload.handle.dig(described_class::LISTA_KEY, 'token'))
      expect(described_class.publicacao_vale?(anterior)).to be(false)
    end
  end

  # O PREÇO QUE A COTAÇÃO AINDA ESTÁ ENVIANDO (quarta rodada de revisão): o lote aceito pelo publicador e ainda não
  # entregue na conversa não entra na lista da Lia, que diria o mesmo preço duas vezes.
  describe 'o preço que a cotação ainda está enviando' do
    let(:bot) { create(:agent_bot, account: account) }

    # A cotação com Porto e Allianz com preço, cada uma num lote de preço, os dois emitidos há `emitidos` e aceitos
    # (`aceitos`). `entregues` são os lotes que já são mensagem na conversa; `pendentes`, os que são mensagem com
    # pendência de envio.
    def cotacao_com_lotes(entregues: [], pendentes: [], aceitos: %w[porto allianz], mapeados: true, emitidos: 1.minute)
      run = cotacao_com(status: 'running', ofertas: [cotou('8', 'Porto Seguro', 2119.18), cotou('5', 'Allianz', 2402.55)])
      tokens = { 'porto' => "#{run.execution_key}:porto", 'allianz' => "#{run.execution_key}:allianz" }
      aceite = { cotacao::PRECOS_KEY => tokens.values, Autonomia::Agents::Tools::EntregaAceita::CHAVE => tokens.values_at(*aceitos) }
      run.update!(handle: run.handle.merge(aceite).merge(mapeados ? lotes_de(tokens, emitidos) : {}))
      (entregues + pendentes).each { |nome| mensagem_do_lote(tokens[nome], pendente: pendentes.include?(nome)) }
      run
    end

    def lotes_de(tokens, emitidos)
      lote = ->(codigo) { { 'codigos' => [codigo], 'emitido_em' => emitidos.ago.iso8601 } }
      { cotacao::Resultado::LOTES_KEY => { tokens['porto'] => lote.call('8'), tokens['allianz'] => lote.call('5') } }
    end

    def mensagem_do_lote(token, pendente:)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: bot,
                       content: 'lote', content_attributes: { Autonomia::Agents::Tools::EntregaPublicada::CHAVE => token,
                                                              'autonomia_envio_pendente' => pendente })
    end

    it 'com todos os lotes a caminho, o modelo ouve que os preços estão sendo enviados, e nada é aberto' do
      cotacao_com_lotes

      expect(no_turno.precheck.to_s).to eq(described_class::PRECOS_A_CAMINHO)
      expect(no_turno('Allianz').precheck.to_s).to eq('Allianz fez proposta: o preço dela está na fila de envio e chega numa mensagem do sistema.')
    end

    it 'com um lote entregue e outro a caminho, a lista leva só o entregue' do
      cotacao_com_lotes(entregues: ['porto'])
      ferramenta = no_turno

      expect(ferramenta.precheck).to be_nil
      expect(ferramenta.aceite.split("\n").first(2)).to eq([described_class::LISTA_DEPOIS, described_class::PARTE_A_CAMINHO])
      expect(ferramenta.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['8'])
      expect(no_turno('Porto e Allianz').aceite).to include('Porto Seguro fez proposta: o preço dela sai na lista',
                                                            'Allianz fez proposta: o preço dela está na fila de envio')
    end

    # O LOTE COM PENDÊNCIA DE ENVIO (quinta rodada de revisão): publicado na hora com a fila fora, ele volta `blocked`
    # do publicador e fica sem aceite; o varredor ainda o reenvia.
    it 'o lote com pendência de envio está a caminho, com aceite ou sem; o lote não aceito e sem mensagem, não' do
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'])
      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['8'])

      Autonomia::Agents::ToolRun.delete_all
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'], aceitos: ['porto'])
      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['8'])

      Autonomia::Agents::ToolRun.delete_all
      cotacao_com_lotes(entregues: ['porto'], aceitos: ['porto'])
      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(%w[8 5])
    end

    # A PENDÊNCIA QUE O VARREDOR NÃO PROCURA MAIS (sexta rodada de revisão): mais velha que a janela dele, ninguém vai
    # reenviar o lote, e a lista da Lia volta a levar o preço.
    it 'o lote com pendência de envio mais velha que a janela do varredor não está mais a caminho' do
      cotacao_com_lotes(entregues: ['porto'], pendentes: ['allianz'])
      antiga = (Autonomia::Agents::Tools::ReapStaleRunsJob::ENVIO_PENDENTE_JANELA + 1.hour).ago
      conversation.messages.where(content: 'lote').find_each do |mensagem|
        mensagem.update_columns(created_at: antiga) if mensagem.content_attributes['autonomia_envio_pendente'] # rubocop:disable Rails/SkipsModelValidations
      end

      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(%w[8 5])
    end

    # O LOTE ACEITO QUE NUNCA VIROU MENSAGEM (quinta rodada de revisão): passada a janela, a publicação adiada não vem
    # mais, e a lista da Lia volta a levar o preço.
    it 'o lote aceito sem mensagem emitido há mais que a janela não está mais a caminho' do
      cotacao_com_lotes(entregues: ['porto'], emitidos: Autonomia::Insurance::ResultadoDaCotacao::JANELA_DO_LOTE + 1.minute)

      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(%w[8 5])
    end

    it 'o lote a caminho sem os códigos gravados (emitido antes desta versão) segura todos os preços, dentro da janela' do
      run = cotacao_com_lotes(entregues: ['porto'], mapeados: false)
      expect(no_turno.precheck.to_s).to eq(described_class::PRECOS_A_CAMINHO)

      run.update_columns(updated_at: (Autonomia::Insurance::ResultadoDaCotacao::JANELA_DO_LOTE + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations
      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(%w[8 5])
    end

    it 'com todos os lotes entregues, a lista leva todos' do
      cotacao_com_lotes(entregues: %w[porto allianz])

      expect(no_turno.handle_de_abertura[described_class::CODIGOS_KEY]).to eq(%w[8 5])
    end
  end

  describe 'a procura pelo nome que o cliente escreveu' do
    # '99' veio sem nome do portal: sem palavra no nome, ela não pode casar com consulta nenhuma.
    let(:nomes) do
      { '8' => 'Porto Seguro', '19' => 'Sancor', '48' => 'Bp', '55' => 'Bp Assinatura', '12' => 'Liberty Site',
        '11' => 'Tokio', '4' => 'Hdi', '99' => '' }
    end

    before { cotacao_com(status: 'done', ofertas: nomes.map { |code, name| recusou(code, name) }) }

    {
      'porto' => %w[8], 'Porto Seguro' => %w[8], 'Sancor Seguros' => %w[19], 'HDI' => %w[4], 'bp' => %w[48],
      'Bp Assinatura' => %w[55], 'a assinatura' => %w[55], 'liberty' => %w[12], 'Liberty e Porto' => %w[8 12],
      'Tokio Marine' => %w[11], 'Bp e Sancor' => %w[19 48], 'azul' => [], 'seguradora' => [], '' => []
    }.each do |consulta, codigos|
      it "«#{consulta}» nomeia #{codigos.inspect}" do
        resultado = Autonomia::Insurance::ResultadoDaCotacao.da_conversa(conversation.id)

        expect(resultado.procurar(consulta)).to match_array(codigos)
      end
    end
  end

  describe 'os textos de classe' do
    it 'não publicam frase pronta: espera, falha, incerteza, parcial e fecho são vazios' do
      textos = %i[waiting_message failure_message uncertain_message partial_message closing_message]

      expect(textos.map { |texto| described_class.public_send(texto, { 'seguradora' => 'x' }) }).to all(eq(''))
      expect(textos.map { |texto| described_class.public_send(texto) }).to all(eq(''))
    end

    it 'o aceite de classe é o texto da lista, para o modelo' do
      expect(described_class.accepted_message).to eq(described_class::LISTA_DEPOIS)
    end
  end

  describe 'o schema' do
    let(:schema) { described_class.openai_schema }

    it 'tem um parâmetro só, seguradora, opcional pelo tipo e presente em required, sem anyOf' do
      expect(schema[:parameters][:properties].keys).to eq(['seguradora'])
      expect(schema[:parameters][:required]).to eq(['seguradora'])
      expect(schema[:parameters][:properties]['seguradora']['type']).to match_array(%w[string null])
      expect(schema.to_json).not_to include('anyOf')
      expect(schema[:strict]).to be(true)
      expect(schema[:parameters][:additionalProperties]).to be(false)
    end
  end
end
