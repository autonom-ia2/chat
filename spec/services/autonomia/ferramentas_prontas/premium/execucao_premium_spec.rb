require 'rails_helper'

# #2858 (F7): a consulta Premium do começo ao fim, com a BigDataCorp dublada (zero chamada real). Os termos de aceite
# da F7 que dá para provar sem produção: 20 grátis por card e por conta, a 21ª cobrada pelo custo × 1,5, o "não havia
# registro" contado, a fonte lenta e o 504 que não contam, o cache do dia, o limite diário por conta e card, a recusa do
# contato de pessoa física sem chamar a fonte, o alerta de 80% do orçamento, a flag que corta tudo e a credencial que
# nunca aparece.
RSpec.describe Autonomia::FerramentasProntas::Premium::Execucao do
  let(:account) { create(:account) }
  let(:outra_conta) { create(:account) }
  let(:agent) { criar_agente(account) }
  let(:certidoes) { incluir_pronta('certidoes_empresa', conta: account, agente: agent) }
  let(:raio_x) { incluir_pronta('raio_x_empresa', conta: account, agente: agent) }
  let(:contato) { incluir_pronta('contato_empresa', conta: account, agente: agent) }
  let(:risco) { incluir_pronta('risco_endereco', conta: account, agente: agent) }
  let(:saldos) { Autonomia::FerramentasProntas::Premium::Saldo }
  let(:usos) { Autonomia::FerramentasProntas::Uso }
  let(:pgfn) { { 'consulta' => 'divida_uniao', 'cnpj' => '11.222.333/0001-81' } }
  let(:certidao_negativa) do
    [{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA',
       'AdditionalOutputData' => { 'EmissionDate' => '2026-11-10 10:00:00Z', 'RawResultFile' => 'https://arquivo.exemplo.test/x.pdf',
                                   'TaxPayer' => FerramentasPremiumHelper::CNPJ_EXEMPLO } }]
  end
  let(:logs) { StringIO.new }

  def criar_agente(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def pgfn_responde(dado = certidao_negativa, **)
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', dado, **)
  end

  def a_bigdatacorp(rota = '/ondemand')
    a_request(:post, "#{FerramentasPremiumHelper::BDC}#{rota}")
  end

  around { |example| com_credencial_da_bigdatacorp { example.run } }

  before do
    ligar_premium(account)
    ligar_premium(outra_conta)
    cache_em_memoria
    token_da_bigdatacorp
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(logs))
    chave_do_alerta = Autonomia::FerramentasProntas::Premium::Orcamento::CHAVE_DO_ALERTA
    Redis::Alfred.with { |conn| conn.del("#{chave_do_alerta}:#{Time.zone.today.strftime('%Y-%m')}") }
  end

  it 'a primeira consulta do card é grátis e fica na telemetria com conta, card, dataset, custo, preço, resultado e dia' do
    pgfn_responde

    resposta = executar_premium(certidoes, pgfn)

    expect(resposta['situacao']).to eq('encontrado')
    expect(resposta['dados']).to include('situacao' => 'NEGATIVA', 'emitida_em' => '2026-11-10 10:00:00Z')
    expect(resposta.to_json).not_to include('arquivo.exemplo.test', FerramentasPremiumHelper::CNPJ_EXEMPLO)
    expect(registros_premium.sole).to have_attributes(
      account_id: account.id, autonomia_agent_id: agent.id, fonte: 'certidoes_empresa', consulta: 'divida_uniao',
      dataset: 'ondemand_pgfn_company', resultado: 'encontrado', cobranca: 'gratis', numero: 1, do_cache: false,
      custo: BigDecimal('0.10'), preco: 0, dia: Time.zone.today, id_na_fonte: 'query-exemplo-ondemand_pgfn_company'
    )
    expect(a_bigdatacorp.with(body: hash_including('q' => "doc{#{FerramentasPremiumHelper::CNPJ_EXEMPLO}}"))).to have_been_made.once
  end

  it 'da 21ª em diante a consulta é cobrada pelo custo × 1,5, e um card não mexe no contador do outro' do
    pgfn_responde
    bigdatacorp_responde('/empresas', 'kyc', 'KycData', { 'IsCurrentlySanctioned' => false })
    saldos.create!(account: account, fonte: 'certidoes_empresa', contadas: 20)

    executar_premium(certidoes, pgfn)
    executar_premium(raio_x, 'consulta' => 'sancoes', 'cnpj' => FerramentasPremiumHelper::CNPJ_EXEMPLO)

    cobrada, outra = registros_premium.to_a
    expect(cobrada).to have_attributes(fonte: 'certidoes_empresa', numero: 21, cobranca: 'cobrada', custo: BigDecimal('0.10'),
                                       preco: BigDecimal('0.15'))
    expect(outra).to have_attributes(fonte: 'raio_x_empresa', numero: 1, cobranca: 'gratis', preco: 0)
  end

  it 'a 20ª ainda é grátis' do
    pgfn_responde
    saldos.create!(account: account, fonte: 'certidoes_empresa', contadas: 19)

    executar_premium(certidoes, pgfn)

    expect(registros_premium.sole).to have_attributes(numero: 20, cobranca: 'gratis', preco: 0)
  end

  it 'sem registro: a resposta diz "não havia registro" e a consulta conta' do
    pgfn_responde(nil)
    saldos.create!(account: account, fonte: 'certidoes_empresa', contadas: 20)

    resposta = executar_premium(certidoes, pgfn)

    expect(resposta['situacao']).to eq('nao_encontrado')
    expect(resposta['orientacao']).to include('não havia registro')
    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'cobrada', preco: BigDecimal('0.15'))
    expect(usos.sole.nao_encontradas).to eq(1)
  end

  it 'o código de "nenhum resultado" da BigDataCorp também é sem registro' do
    pgfn_responde([], code: -204, message: 'NO RESULTS FOUND FOR THE PROVIDED PARAMETERS')

    expect(executar_premium(certidoes, pgfn)['situacao']).to eq('nao_encontrado')
    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'gratis', numero: 1)
  end

  it 'a fonte lenta (DATASET IS TOO SLOW) não conta para o cliente' do
    pgfn_responde(nil, code: -1201, message: 'DATASET IS TOO SLOW. PLEASE TRY AGAIN IN A FEW MINUTES')

    resposta = executar_premium(certidoes, pgfn)

    expect(resposta['situacao']).to eq('nao_consegui_consultar')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', cobranca: 'sem_cobranca', numero: nil, custo: 0,
                                                      motivo: 'fonte_lenta')
    expect(saldos.count).to eq(0)
    expect(usos.sole.motivos).to eq('bigdatacorp.fonte_lenta' => 1)
  end

  it 'o 504 não conta e não é repetido (consulta paga não repete)' do
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return(status: 504, body: '')

    expect(executar_premium(certidoes, pgfn)['situacao']).to eq('nao_consegui_consultar')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', cobranca: 'sem_cobranca', motivo: 'http_504', custo: 0)
    expect(a_bigdatacorp).to have_been_made.once
    expect(saldos.count).to eq(0)
  end

  it 'a mesma consulta no mesmo dia vem do cache, sem custo novo; outra conta não lê o cache desta' do
    pgfn_responde
    da_outra = incluir_pronta('certidoes_empresa', conta: outra_conta, agente: criar_agente(outra_conta))

    executar_premium(certidoes, pgfn)
    repetida = executar_premium(certidoes, pgfn)
    executar_premium(da_outra, pgfn)

    expect(repetida['situacao']).to eq('encontrado')
    expect(a_bigdatacorp).to have_been_made.twice
    primeira, do_cache, outra = registros_premium.to_a
    expect(primeira).to have_attributes(do_cache: false, numero: 1)
    expect(do_cache).to have_attributes(do_cache: true, cobranca: 'sem_cobranca', custo: 0, preco: 0, numero: nil,
                                        resultado: 'encontrado')
    expect(outra).to have_attributes(account_id: outra_conta.id, do_cache: false, numero: 1)
  end

  it 'o "sem registro" do dia também vem do cache, sem contar de novo' do
    pgfn_responde(nil)

    executar_premium(certidoes, pgfn)
    expect(executar_premium(certidoes, pgfn)['situacao']).to eq('nao_encontrado')

    expect(a_bigdatacorp).to have_been_made.once
    expect(registros_premium.last).to have_attributes(do_cache: true, resultado: 'sem_registro', cobranca: 'sem_cobranca')
  end

  it 'o limite diário estourado bloqueia só aquela conta naquele card' do
    pgfn_responde
    bigdatacorp_responde('/empresas', 'kyc', 'KycData', { 'IsCurrentlySanctioned' => false })
    da_outra = incluir_pronta('certidoes_empresa', conta: outra_conta, agente: criar_agente(outra_conta))
    certidoes
    Autonomia::FerramentasProntas::Acesso.find_by!(account_id: account.id, fonte: 'certidoes_empresa').update!(limite_diario: 1)

    executar_premium(certidoes, pgfn)
    bloqueada = executar_premium(certidoes, pgfn.merge('cnpj' => '11.444.777/0001-61'))

    expect(bloqueada['situacao']).to eq('nao_consegui_consultar')
    expect(usos.find_by(account_id: account.id, fonte: 'certidoes_empresa').motivos).to eq('limite_diario' => 1)
    expect(executar_premium(da_outra, pgfn)['situacao']).to eq('encontrado')
    expect(executar_premium(raio_x, 'consulta' => 'sancoes', 'cnpj' => FerramentasPremiumHelper::CNPJ_EXEMPLO)['situacao']).to eq('encontrado')
    expect(registros_premium.where(account_id: account.id, fonte: 'certidoes_empresa').count).to eq(1)
  end

  it 'pedido de contato de pessoa física (um CPF no card de contato) é recusado sem chamar a BigDataCorp' do
    resposta = executar_premium(contato, 'consulta' => 'telefone', 'cnpj' => '111.444.777-35')

    expect(resposta['situacao']).to eq('pedido_invalido')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.count).to eq(0)
  end

  it 'a vistoria sem registro conta para o cliente, mas não tem custo da BigDataCorp' do
    bigdatacorp_responde('/marketplace', 'partner_rede_vistorias_address', 'RedeVistoriasData', nil)

    executar_premium(risco, 'consulta' => 'vistoria', 'cep' => '01001-000', 'numero' => '10')

    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'gratis', numero: 1, custo: 0)
    expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/marketplace")
             .with(body: hash_including('q' => 'zipcode{01001000},addressnumber{10}'))).to have_been_made.once
  end

  it 'com a flag do Premium desligada, nada é consultado nem registrado' do
    certidoes
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)

    expect(executar_premium(certidoes, pgfn)['situacao']).to eq('nao_consegui_consultar')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.count).to eq(0)
  end

  it 'sem a credencial na plataforma, falha sem contar e sem chamar' do
    certidoes
    with_modified_env(BIGDATACORP_USER: nil, BIGDATACORP_PASSWORD: nil) do
      expect(executar_premium(certidoes, pgfn)['situacao']).to eq('nao_consegui_consultar')
    end

    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'nao_configurada', cobranca: 'sem_cobranca')
  end

  it 'a credencial, o token e o documento consultado nunca aparecem em log, resposta ou telemetria' do
    pgfn_responde
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/empresas").to_return(status: 500, body: FerramentasPremiumHelper::SENHA_FALSA)

    textos = [executar_premium(certidoes, pgfn).to_json,
              executar_premium(raio_x, 'consulta' => 'processos', 'cnpj' => FerramentasPremiumHelper::CNPJ_EXEMPLO).to_json,
              registros_premium.map(&:attributes).to_json, logs.string]

    textos.each do |texto|
      expect(texto).not_to include(FerramentasPremiumHelper::SENHA_FALSA, FerramentasPremiumHelper::USUARIO_FALSO,
                                   FerramentasPremiumHelper::TOKEN_FALSO, FerramentasPremiumHelper::CNPJ_EXEMPLO)
    end
    expect(registros_premium.last).to have_attributes(resultado: 'falha', motivo: 'http_500')
  end

  describe 'orçamento do mês' do
    it 'avisa a equipe uma vez quando o custo passa de 80% do orçamento' do
      pgfn_responde
      with_modified_env(Autonomia::FerramentasProntas::Premium::Orcamento::CONFIG => '0,12') do
        expect { executar_premium(certidoes, pgfn) }
          .to have_enqueued_mail(AdministratorNotifications::PremiumMailer, :orcamento_do_mes).once
        expect { executar_premium(certidoes, pgfn.merge('cnpj' => '11.444.777/0001-61')) }
          .not_to have_enqueued_mail(AdministratorNotifications::PremiumMailer, :orcamento_do_mes)
      end
      expect(logs.string).to include('[autonomia][premium] orcamento_80')
    end

    it 'abaixo de 80%, não avisa; e o padrão vale quando a configuração é inválida' do
      pgfn_responde
      with_modified_env(Autonomia::FerramentasProntas::Premium::Orcamento::CONFIG => 'abc') do
        expect(Autonomia::FerramentasProntas::Premium::Orcamento.valor).to eq(BigDecimal(500))
        expect { executar_premium(certidoes, pgfn) }.not_to have_enqueued_mail(AdministratorNotifications::PremiumMailer, :orcamento_do_mes)
      end
    end
  end

  it 'a Cotação e a Prospecção não leem a flag do Premium: o cliente de empresas segue igual com ela desligada' do
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/empresas")
      .with(body: hash_including('Datasets' => 'basic_data', 'Limit' => 3))
      .to_return(status: 200, body: { 'Result' => [], 'QueryId' => 'q' }.to_json)

    resposta = Autonomia::Prospecting::Research::BigDataCorpClient.new.search_companies(query: 'name{EXEMPLO}')

    expect(resposta.payload).to include('QueryId' => 'q')
  end

  it 'no turno e em segundo plano, a pronta Premium executa pela Premium::Execucao e não é "calculada aqui"' do
    expect(Autonomia::FerramentasProntas.executor_para(certidoes, params: pgfn)).to be_a(described_class)
    expect(Autonomia::FerramentasProntas.executor_para(incluir_pronta('cep', conta: account, agente: agent), params: {}).class)
      .to eq(Autonomia::FerramentasProntas::Execucao)
    expect(Autonomia::FerramentasProntas.calculada_aqui?(certidoes)).to be(false)
  end

  it 'o Experimente da vitrine não roda consulta paga' do
    resposta = Autonomia::FerramentasProntas::Experimente.new(account: account, fonte: 'certidoes_empresa', valor: '11222333000181').call

    expect(resposta).to eq('situacao' => 'premium')
    expect(chamou_a_bigdatacorp?).to be(false)
  end
end
