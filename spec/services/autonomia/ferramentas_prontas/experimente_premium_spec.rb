require 'rails_helper'

# #2858 F7 — o "Experimente" do card Premium (decisão A do Rodrigo, 11/11). O teste é uma consulta normal: usa as 20
# grátis do mês do card, vai à mesma telemetria e à mesma cobrança, e lê e grava o mesmo cache do dia que o agente usa.
# Roda pelo caminho do agente (`FerramentasProntas.executor_para`, a `Premium::Execucao`): o CPF ou o CNPJ com dígito
# errado é recusado sem contar, o -114/-155 conta, e o 504/-1201 não conta. Acabadas as grátis, só consulta quando a
# pessoa clica no botão com o preço (`confirmou_preco`). Um clique é uma consulta que vale, no máximo. O modelo da
# conta é dublado e a BigDataCorp vem do WebMock: nenhuma chamada real.
RSpec.describe Autonomia::FerramentasProntas::Experimente do
  let(:account) { create(:account) }
  let(:credencial) { { api_key: 'chave-de-teste', api_base: 'https://api.openai.com', source: :system } }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:cnpj) { FerramentasPremiumHelper::CNPJ_EXEMPLO }
  let(:pgfn) { { consulta: 'divida_uniao', cnpj: '11.222.333/0001-81' } }
  let(:saidas_ao_modelo) { [] }
  let(:certidao_negativa) do
    [{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA', 'AdditionalOutputData' => { 'EmissionDate' => '2026-11-10 10:00:00Z' } }]
  end

  def experimentar(fonte, valor, confirmou_preco: false)
    described_class.new(account: account, fonte: fonte, valor: valor, confirmou_preco: confirmou_preco).call
  end

  def chamada(argumentos, nome: 'pronta_certidoes_empresa', id: 'c1')
    { 'name' => nome, 'call_id' => id, 'arguments' => argumentos.to_json }
  end

  # O modelo dublado: cada rodada é uma lista de chamadas; guarda o que cada uma recebeu de volta.
  def modelo_faz(*rodadas)
    allow(cliente).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      rodadas.each { |chamadas| saidas_ao_modelo.concat(executor.call(chamadas)) }
      { text: { mais_provavel: false }.to_json }
    end
  end

  def pgfn_responde(dado = certidao_negativa, **)
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', dado, **)
  end

  def a_bigdatacorp
    a_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand")
  end

  around { |example| com_credencial_da_bigdatacorp { example.run } }

  before do
    ligar_premium(account)
    cache_em_memoria
    token_da_bigdatacorp
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account)
                                                       .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  it 'consulta de verdade, usa uma das 20 grátis do card, vai à telemetria e devolve o contador novo' do
    pgfn_responde
    modelo_faz([chamada(pgfn)])

    resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')

    expect(resultado).to include('situacao' => 'encontrado')
    expect(resultado['dados']).to include('situacao' => 'NEGATIVA')
    expect(resultado['premium']).to eq('gratis' => 20, 'restantes' => 19, 'precos' => %w[0.06 0.15], 'confere_documento' => true)
    expect(registros_premium.sole).to have_attributes(account_id: account.id, autonomia_agent_id: nil, fonte: 'certidoes_empresa',
                                                      consulta: 'divida_uniao', resultado: 'encontrado', cobranca: 'gratis',
                                                      numero: 1, do_cache: false)
    expect(a_bigdatacorp).to have_been_made.once
  end

  it 'lê o mesmo cache do dia que o agente: a consulta que o agente já fez não sai de novo nem custa' do
    pgfn_responde
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active,
                                              enabled: true, instruction: 'Atenda.')
    executar_premium(incluir_pronta('certidoes_empresa', conta: account, agente: agente), pgfn.stringify_keys)
    modelo_faz([chamada(pgfn)])

    resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')

    expect(resultado['situacao']).to eq('encontrado')
    expect(registros_premium.last).to have_attributes(do_cache: true, autonomia_agent_id: nil)
    expect(a_bigdatacorp).to have_been_made.once
  end

  it 'CPF com dígito errado é recusado sem chamar a BigDataCorp e sem contar' do
    modelo_faz([chamada({ consulta: 'situacao_cpf', cpf: '111.444.777-36' }, nome: 'pronta_conferir_pessoa')])

    resultado = experimentar('conferir_pessoa', 'situação do CPF 111.444.777-36')

    expect(resultado['situacao']).to eq('pedido_invalido')
    expect(resultado['premium']['restantes']).to eq(20)
    expect(registros_premium).to be_empty
    expect(chamou_a_bigdatacorp?).to be(false)
  end

  it 'o documento que a BigDataCorp recusa (-114) conta, como no agente' do
    pgfn_responde([], code: -114, message: 'INVALID DOC PARAMETER')
    modelo_faz([chamada(pgfn)])

    resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')

    expect(resultado['situacao']).to eq('documento_invalido')
    expect(resultado['premium']['restantes']).to eq(19)
    expect(registros_premium.sole).to have_attributes(resultado: 'documento_invalido', cobranca: 'gratis')
  end

  it 'a fonte lenta (-1201) e o 504 não contam' do
    pgfn_responde(nil, code: -1201, message: 'DATASET IS TOO SLOW. PLEASE TRY AGAIN IN A FEW MINUTES')
    modelo_faz([chamada(pgfn)])
    expect(experimentar('certidoes_empresa', 'dívida com a União')).to include('situacao' => 'nao_consegui_consultar')

    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return(status: 504, body: '')
    resultado = experimentar('certidoes_empresa', 'dívida com a União')

    expect(resultado).to include('situacao' => 'nao_consegui_consultar')
    expect(resultado['premium']['restantes']).to eq(20)
    expect(registros_premium.pluck(:cobranca)).to eq(%w[sem_cobranca sem_cobranca])
  end

  it 'um clique é uma consulta que vale: a segunda que o modelo pede não sai' do
    pgfn_responde
    modelo_faz([chamada(pgfn), chamada({ consulta: 'trabalhista', cnpj: cnpj }, id: 'c2')])

    experimentar('certidoes_empresa', 'certidões da 11.222.333/0001-81')

    expect(a_bigdatacorp).to have_been_made.once
    expect(registros_premium.count).to eq(1)
    expect(JSON.parse(saidas_ao_modelo.last[:output])).to eq('situacao' => 'limite_do_experimente')
  end

  # Revisor (MÉDIO, com_modelo.rb:36): o CPF ou o CNPJ com dígito errado encerra o clique e mostra a recusa. O modelo
  # não pode "corrigir" o dígito sozinho e consultar outro documento, pago, que a pessoa não pediu.
  it 'o CNPJ com dígito errado encerra o clique: a recusa aparece e nenhum outro documento é consultado' do
    pgfn_responde
    modelo_faz([chamada({ consulta: 'divida_uniao', cnpj: '11.222.333/0001-80' })], [chamada(pgfn, id: 'c2')])

    resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-80')

    expect(resultado['situacao']).to eq('pedido_invalido')
    expect(JSON.parse(saidas_ao_modelo.last[:output])).to eq('situacao' => 'limite_do_experimente')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium).to be_empty
  end

  it 'a recusa que não é do documento (a consulta que não existe) não gasta o clique: o modelo corrige e a consulta sai' do
    pgfn_responde
    modelo_faz([chamada({ consulta: 'nao_existe', cnpj: cnpj })], [chamada(pgfn, id: 'c2')])

    expect(experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')['situacao']).to eq('encontrado')
    expect(a_bigdatacorp).to have_been_made.once
  end

  context 'with as 20 grátis do mês usadas' do
    before { saldo_premium!(account, 'certidoes_empresa', 20) }

    it 'sem o clique no preço, nada é consultado: a resposta pede a confirmação e traz o contador' do
      modelo_faz([chamada(pgfn)])

      resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')

      expect(resultado).to eq('situacao' => 'confirmar_preco',
                              'premium' => { 'gratis' => 20, 'restantes' => 0, 'precos' => %w[0.06 0.15], 'confere_documento' => true })
      expect(cliente).not_to have_received(:create_with_tool_executor)
      expect(chamou_a_bigdatacorp?).to be(false)
      expect(registros_premium).to be_empty
    end

    it 'com o clique no preço, consulta e cobra como a consulta do agente' do
      pgfn_responde
      modelo_faz([chamada(pgfn)])

      resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81', confirmou_preco: true)

      expect(resultado['situacao']).to eq('encontrado')
      expect(registros_premium.sole).to have_attributes(cobranca: 'cobrada', numero: 21, preco: BigDecimal('0.15'))
    end
  end

  # Revisor (ALTO 2): a conferência das grátis roda fora da trava do saldo. Dois cliques com 1 grátis restante passam
  # os dois por ela, e o segundo vira a 21ª do mês sem o clique no preço. Aqui o outro clique levou a última grátis
  # entre a conferência (que ainda leu 1 restante) e a consulta: a 21ª nunca é gravada como cobrada, o custo fica
  # conosco e o caso vai ao log.
  it 'corrida nas grátis: a 21ª sem o clique no preço não é cobrada; o custo fica conosco e vai ao log' do
    saldo_premium!(account, 'certidoes_empresa', 20)
    lida_antes = { 'gratis' => 20, 'restantes' => 1, 'precos' => %w[0.06 0.15], 'confere_documento' => true }
    leituras = 0
    allow(Autonomia::FerramentasProntas::Premium).to receive(:para_tela).and_wrap_original do |original, *args|
      (leituras += 1) == 1 ? { 'certidoes_empresa' => lida_antes } : original.call(*args)
    end
    allow(Rails.logger).to receive(:warn)
    pgfn_responde
    modelo_faz([chamada(pgfn)])

    resultado = experimentar('certidoes_empresa', 'dívida com a União da 11.222.333/0001-81')

    expect(resultado['situacao']).to eq('encontrado')
    expect(registros_premium.sole).to have_attributes(numero: 21, cobranca: 'sem_cobranca', preco: 0, custo: BigDecimal('0.10'),
                                                      motivo: 'sem_clique_no_preco')
    expect(Rails.logger).to have_received(:warn).with(a_string_including('sem o clique no preço'))
  end

  it 'sem a flag do Premium, nada roda' do
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)

    expect(experimentar('certidoes_empresa', 'dívida com a União')).to eq('situacao' => 'desligada')
    expect(chamou_a_bigdatacorp?).to be(false)
  end
end
