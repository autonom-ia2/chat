require 'rails_helper'

# R17 DA RECEITA DE RAMO: AS SEIS RODADAS NO MANUAL, LIGADAS À CONSTANTE.
#
# `Runner::RODADAS_DE_FERRAMENTA` (o especialista) e `Builder::RODADAS_DA_LIA` (a Lia) são seis desde a #585, e nenhum
# manual dizia isso ao modelo: a recusa grátis da conferência, que se corrige no turno, podia virar pergunta ao cliente.
# Agora a §I do bloco comum e o bloco dos especialistas do manual da Lia dizem, cada um perto da ação. Cada frase aqui
# tem o que a sustenta; a frase some, o exemplo reprova; a constante muda, o exemplo reprova.
#
# PENDÊNCIA (decisão do Rodrigo, 25/09/2026, opção a): a recusa PAGA de uma seguradora por valor seria recotada uma vez,
# sozinha, só nas seguradoras que recusaram por valor. Esse recote NÃO EXISTE no código hoje, e o manual diz só o que é
# verdade: a recusa paga chega fora do turno e não se corrige nas rodadas. Quando o recote existir, a frase muda e entra
# aqui ligada ao código que o faz.
module RodadasNoManual
  BUILDER = Autonomia::Insurance::QuoteAgent::Builder
  RUNNER = Autonomia::Agents::Specialists::Runner
  COMUM = BUILDER::INSTRUCOES.join(BUILDER::ARQUIVO_COMUM_DO_ESPECIALISTA)
  PRINCIPAL = BUILDER::INSTRUCOES.join(BUILDER::ARQUIVO_DO_PRINCIPAL)
  COTACAO = Autonomia::Agents::Tools::Native::InsuranceQuote
  SEIS = 6

  # CADA FRASE NOVA, E O QUE A SUSTENTA. As sustentações rodam no exemplo (`instance_exec`), com os ajudantes dele.
  PROMESSAS_DO_COMUM = {
    # O Runner dá seis rodadas ao especialista: a constante, e o que ele passa de fato ao cliente de IA.
    '**A conferência recusou:** você tem até seis rodadas de ferramenta neste turno' => lambda {
      RUNNER::RODADAS_DE_FERRAMENTA == SEIS && rodadas_do_especialista == SEIS
    },
    # A recusa grátis volta ao modelo no mesmo turno, e nada é aberto: é o que deixa conferir de novo sem custo.
    'leia a recusa, ajuste o valor e confira de novo' => -> { recusa_gratis_volta_no_turno? },
    # DECISÃO 4 (chat#718): a conferência pode chamar a busca paga do segurado (`quote/enrich`); repetida com o mesmo
    # documento na conversa, a que teve resposta não sai de novo (`Insurance::BuscaDoSeguradoGuardada`). A que falhou
    # (erro, ou `lookup_failed` do adapter) sai de novo: por isso "que já teve resposta" (revisão da chat#718).
    'com o mesmo documento, a busca paga do segurado que já teve resposta não se repete' => lambda {
      busca_paga_uma_vez? && busca_que_falhou_repete?
    },
    # A cotação paga é assíncrona: a recusa da seguradora chega depois do turno, e o motivo vai para a nota da equipe.
    'essa recusa chega fora do turno, com a cotação já paga' => lambda {
      COTACAO.async? && COTACAO::RECUSOU.include?('recusou e escreveu no portal')
    }
  }.freeze

  PROMESSAS_DA_LIA = {
    # O Builder dá seis rodadas à Lia no Agente de Cotação: a constante, e o que ele devolve para o turno.
    '**Você tem até seis rodadas de ferramenta neste turno.**' => lambda {
      BUILDER::RODADAS_DA_LIA == SEIS && rodadas_da_lia == SEIS
    },
    # Quem corrige a recusa é o especialista, nas seis rodadas dele, e a recusa volta no turno.
    'lendo a recusa, ajustando o valor e conferindo de novo' => -> { rodadas_do_especialista == SEIS && recusa_gratis_volta_no_turno? },
    'com o mesmo documento, a busca paga do segurado que já teve resposta não se repete' => lambda {
      busca_paga_uma_vez? && busca_que_falhou_repete?
    },
    'A recusa de uma seguradora é outra coisa: chega fora do turno' => -> { COTACAO.async? }
  }.freeze

  module_function

  # A §I do bloco comum, do título até a §J.
  def secao_i(texto)
    inicio = texto.index('## I. Quando algo dá errado')
    inicio && texto[inicio...texto.index("\n## J.", inicio)]
  end

  # O parágrafo das rodadas no manual da Lia, até a linha em branco.
  def paragrafo_da_lia(texto)
    inicio = texto.index('**Você tem até seis rodadas de ferramenta neste turno.**')
    inicio && texto[inicio...texto.index("\n\n", inicio)]
  end
end

RSpec.describe 'R17: as seis rodadas no manual' do # rubocop:disable RSpec/DescribeClass
  let(:comum) { RodadasNoManual::COMUM.read }
  let(:principal) { RodadasNoManual::PRINCIPAL.read }

  # O especialista roda seis rodadas de verdade: o Runner as passa ao cliente de IA.
  def rodadas_do_especialista
    account = create(:account)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')
    specialist = Autonomia::Agents::Specialist.create!(agent: agent, name: 'Cotação', slug: 'cotacao_auto',
                                                       description: 'cota', instruction: 'Você cota.')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    client = instance_double(Crm::Ai::ResponsesClient)
    recebido = {}
    allow(client).to receive(:create_with_tool_executor) do |**kwargs|
      recebido.merge!(kwargs.slice(:max_rodadas))
      { text: { resposta: 'ok', dados_faltando: [] }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    RodadasNoManual::RUNNER.new(specialist: specialist, request: 'cotar').call
    recebido[:max_rodadas]
  end

  # A recusa volta ao modelo no mesmo turno, como texto, e nada é aberto, pela cotação de verdade: o portal (dublado)
  # recusa na conferência, e o `quote_start`, a chamada paga, não sai. É o que deixa corrigir e conferir de novo.
  def recusa_gratis_volta_no_turno?
    account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
    conversation = create(:conversation, account: account)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')
    portal_que_recusa(account)
    delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1)
    params = { 'cpf' => '042.979.126-78', 'cep' => '31110-210', 'item' => 'Gol', 'vehicle' => { 'plate' => 'TYV8I74' } }
    saida = Autonomia::Agents::Tools::Bound.new(agent: agent, native: RodadasNoManual::COTACAO)
                                           .execute({ 'name' => 'cotar_seguro', 'arguments' => params.to_json }, delivery: delivery)
    saida.include?('não existe nesta cobertura') && Autonomia::Agents::ToolRun.none?
  end

  def portal_que_recusa(account)
    enable_test_encryption!
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    conexao.update!(status: 'ready', metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
    conexao.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    problema = { 'campo' => 'coverage.assistance24h', 'severidade' => 'erro', 'motivo' => '2000 não existe nesta cobertura' }
    portal = instance_double(Autonomia::Insurance::Connector::Mock, quote_validate: { 'valido' => false, 'problemas' => [problema] },
                                                                    vehicle_lookup: { 'plate' => 'TYV8I74', 'vehicle_type' => 'v' },
                                                                    quote_enrich: { 'not_found' => [] })
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(portal)
  end

  # A conferência de verdade, duas vezes no mesmo turno, com o documento e sem o nome: a busca paga sai uma vez só.
  def busca_paga_uma_vez?
    conferir_duas_vezes(lookup_failed: false) == 1
  end

  # A mesma conferência, com o fornecedor fora (`lookup_failed`): a busca sai nas duas, porque a primeira não teve resposta.
  def busca_que_falhou_repete?
    conferir_duas_vezes(lookup_failed: true) == 2
  end

  # -> quantas vezes a busca paga saiu, ou nil quando a recusa não foi a do nome não achado.
  def conferir_duas_vezes(lookup_failed:)
    account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_insurance_enabled' => true })
    conversation = create(:conversation, account: account)
    agent = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                             enabled: true, instruction: 'Atenda.')
    buscas = portal_que_nao_acha_o_nome(account, lookup_failed)
    delivery = Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: 1)
    params = { 'item' => 'Casa', 'produto' => 'residencial', 'cpf' => '04297912678', 'cep' => '01310-100',
               'dados' => { 'configuracoes' => { 'imovelNumero' => '742' } }.to_json }
    recusas = Array.new(2) { RodadasNoManual::COTACAO.new(agent: agent, params: params, delivery: delivery).precheck }
    buscas.size if recusas.all? { |recusa| recusa.try(:faltando) == ['segurado.nome'] } && Autonomia::Agents::ToolRun.none?
  end

  def portal_que_nao_acha_o_nome(account, lookup_failed)
    enable_test_encryption!
    conexao = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    conexao.update!(status: 'ready')
    buscas = []
    portal = instance_double(Autonomia::Insurance::Connector::Mock, quote_validate: { 'valido' => true, 'problemas' => [] })
    allow(portal).to receive(:quote_enrich) do
      buscas << :busca
      { 'input' => {}, 'not_found' => ['segurado.nome'], 'lookup_failed' => lookup_failed }
    end
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(portal)
    buscas
  end

  def rodadas_da_lia
    RodadasNoManual::BUILDER.rodadas_do_turno(Autonomia::Agents::Agent.new(agent_type: 'insurance_quote'))[:max_rodadas]
  end

  { 'no bloco comum do especialista, §I' => [:comum, RodadasNoManual::PROMESSAS_DO_COMUM],
    'no manual da Lia, bloco dos especialistas' => [:principal, RodadasNoManual::PROMESSAS_DA_LIA] }.each do |onde, (texto, promessas)|
    describe onde do
      promessas.each do |frase, sustenta|
        it "«#{frase}» tem o que a sustenta" do
          expect(public_send(texto)).to include(frase)
          expect(instance_exec(&sustenta)).to be(true)
        end
      end
    end
  end

  # O RECOTE AINDA NÃO EXISTE (ver a pendência no topo): as frases novas não o prometem.
  it 'as frases novas não prometem o recote' do
    trechos = [RodadasNoManual.secao_i(comum), RodadasNoManual.paragrafo_da_lia(principal)]

    expect(trechos).to all(be_present)
    trechos.each { |trecho| expect(trecho.downcase).not_to include('recot') }
  end
end
