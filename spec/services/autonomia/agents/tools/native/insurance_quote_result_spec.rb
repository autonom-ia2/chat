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
  let(:risco) { { 'kind' => 'risco', 'text' => 'Risco sem aceitação para este cenário nesta seguradora.' } }

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

    it 'seguradora sem proposta com o motivo que a regra libera: o nome e o texto do portal' do
      cotacao_com(status: 'done')

      texto = no_turno('Sancor').precheck.to_s

      expect(texto).to include('Sancor não fez proposta nesta cotação.', risco['text'])
    end

    # CREDENCIAL DA CORRETORA: o modelo recebe só que a seguradora não fez proposta.
    it 'seguradora que recusou a credencial: não fez proposta, sem motivo e sem palavra de conta' do
      cotacao_com(status: 'done')

      texto = no_turno('Mitsui').precheck.to_s

      expect(texto).to eq("Mitsui não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
      expect(texto.downcase).not_to match(/login|senha|permiss|credencia|acesso|corretor|risco sem/)
    end

    # A REGRA É APLICADA DE NOVO NA LEITURA: um motivo guardado por uma regra mais frouxa não passa.
    it 'motivo guardado com termo de conta não chega ao modelo' do
      entrada = { 'nome' => 'Sancor', 'desfecho' => 'sem_proposta',
                  'motivo' => { 'kind' => 'risco', 'text' => 'Senha expirou. Declinando cálculo.' } }
      cotacao_com(status: 'done', guardado: false, handle: { cotacao::RESULTADO_KEY => { '19' => entrada } })

      texto = no_turno('sancor').precheck.to_s

      expect(texto).to eq("Sancor não fez proposta nesta cotação. #{described_class::SEM_MOTIVO}")
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
      expect(ferramenta.aceite).to include('Porto Seguro fez proposta', 'Sancor não fez proposta nesta cotação.', risco['text'])
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

    it 'publica os itens escritos por QuoteOffers.item, na ordem da lista de preços' do
      cotacao_com(status: 'done')
      handle = no_motor.start

      progresso = no_motor.poll(handle: handle, attempt: 1)

      itens = [cotou('8', 'Porto Seguro', 2119.18), cotou('5', 'Allianz', 2402.55)].map do |oferta|
        Autonomia::Insurance::QuoteOffers.item(oferta)
      end
      expect(progresso).to be_done
      expect(progresso.deliveries).to eq([itens.join("\n\n")])
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

  # O HANDLE DE ABERTURA: o que a Lia leu no turno vai para a linha que a abertura cria, e o pedido anterior
  # da mesma cotação que ainda não publicou (e que a abertura vai superseder) entra na lista deste.
  describe 'o handle de abertura' do
    def outra_execucao(status:, handle:, entregas: 0)
      Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: described_class.slug, status: status,
                                         conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                         arguments: {}, handle: handle, delivered_count: entregas)
    end

    it 'grava a cotação lida e os códigos com preço do pedido, e nada quando não há preço' do
      fonte = cotacao_com(status: 'done')

      expect(no_turno('Allianz').handle_de_abertura)
        .to eq(described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['5'])
      expect(no_turno('Sancor').handle_de_abertura).to eq({})
    end

    it 'une os códigos de outra execução viva, sem entrega e sobre a mesma cotação' do
      fonte = cotacao_com(status: 'done')
      outra_execucao(status: 'pending', handle: { described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['8'] })

      expect(no_turno('Allianz').handle_de_abertura[described_class::CODIGOS_KEY]).to contain_exactly('8', '5')
    end

    it 'não une a execução sobre outra cotação, a que já entregou, nem a encerrada' do
      fonte = cotacao_com(status: 'done')
      outra_execucao(status: 'running', entregas: 1,
                     handle: { described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['8'] })
      outra_execucao(status: 'done', handle: { described_class::EXECUCAO_KEY => fonte.id, described_class::CODIGOS_KEY => ['99'] })

      expect(no_turno('Allianz').handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['5'])

      Autonomia::Agents::ToolRun.where(slug: described_class.slug).find_each(&:destroy!)
      outra_execucao(status: 'pending', handle: { described_class::EXECUCAO_KEY => fonte.id + 1000, described_class::CODIGOS_KEY => ['8'] })
      expect(no_turno('Allianz').handle_de_abertura[described_class::CODIGOS_KEY]).to eq(['5'])
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
