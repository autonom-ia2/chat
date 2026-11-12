require 'rails_helper'

# #2858 (F7): a consulta Premium do começo ao fim, com a BigDataCorp dublada (zero chamada real). Os termos de aceite
# da F7 que dá para provar sem produção: 20 grátis por card e por conta a cada mês, a 21ª cobrada pelo custo × 1,5, o
# "não havia registro" contado, a fonte lenta e o 504 que não contam, o cache do dia, sem limite diário no Premium, a
# recusa do contato de pessoa física sem chamar a fonte, a flag que corta tudo e a credencial que nunca aparece.
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
  let(:cnj) { { 'consulta' => 'cnj', 'cnpj' => '11.222.333/0001-81' } }
  let(:certidao_negativa) do
    [{ 'Origin' => 'CNJ', 'BaseStatus' => 'NEGATIVA',
       'AdditionalOutputData' => { 'EmissionDate' => '2026-11-10 10:00:00Z', 'RawResultFile' => 'https://arquivo.exemplo.test/x.pdf',
                                   'TaxPayer' => FerramentasPremiumHelper::CNPJ_EXEMPLO } }]
  end
  let(:logs) { StringIO.new }

  def criar_agente(conta)
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def cnj_responde(dado = certidao_negativa, **)
    bigdatacorp_responde('/ondemand', 'ondemand_cnj_negative_certificate_company', 'OnlineCertificates', dado, **)
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
  end

  it 'a primeira consulta do card é grátis e fica na telemetria com conta, card, dataset, custo, preço, resultado e dia' do
    cnj_responde

    resposta = executar_premium(certidoes, cnj)

    expect(resposta['situacao']).to eq('encontrado')
    expect(resposta['dados']).to include('situacao' => 'NEGATIVA', 'emitida_em' => '2026-11-10')
    expect(resposta.to_json).not_to include('arquivo.exemplo.test', FerramentasPremiumHelper::CNPJ_EXEMPLO)
    expect(registros_premium.sole).to have_attributes(
      account_id: account.id, autonomia_agent_id: agent.id, fonte: 'certidoes_empresa', consulta: 'cnj',
      dataset: 'ondemand_cnj_negative_certificate_company', resultado: 'encontrado', cobranca: 'gratis', numero: 1, do_cache: false,
      custo: BigDecimal('0.10'), preco: 0, dia: Time.zone.today, id_na_fonte: 'query-exemplo-ondemand_cnj_negative_certificate_company'
    )
    expect(a_bigdatacorp.with(body: hash_including('q' => "doc{#{FerramentasPremiumHelper::CNPJ_EXEMPLO}}"))).to have_been_made.once
  end

  it 'da 21ª em diante a consulta é cobrada pelo custo × 1,5, e um card não mexe no contador do outro' do
    cnj_responde
    bigdatacorp_responde('/empresas', 'kyc', 'KycData', { 'IsCurrentlySanctioned' => false })
    saldo_premium!(account, 'certidoes_empresa', 20)

    executar_premium(certidoes, cnj)
    executar_premium(raio_x, 'consulta' => 'sancoes', 'cnpj' => FerramentasPremiumHelper::CNPJ_EXEMPLO)

    cobrada, outra = registros_premium.to_a
    expect(cobrada).to have_attributes(fonte: 'certidoes_empresa', numero: 21, cobranca: 'cobrada', custo: BigDecimal('0.10'),
                                       preco: BigDecimal('0.15'))
    expect(outra).to have_attributes(fonte: 'raio_x_empresa', numero: 1, cobranca: 'gratis', preco: 0)
  end

  it 'as 20 grátis renovam todo mês: o mês passado cheio não cobra a primeira do mês' do
    cnj_responde
    saldo_premium!(account, 'certidoes_empresa', 35, mes: Autonomia::FerramentasProntas::Premium.mes_da_conta(account).prev_month)

    executar_premium(certidoes, cnj)

    expect(registros_premium.sole).to have_attributes(numero: 1, cobranca: 'gratis', preco: 0)
    expect(saldos.order(:mes).pluck(:contadas)).to eq([35, 1])
  end

  it 'o fuso da conta é um só, o mesmo da execução, com a volta para a plataforma quando não dá para ler' do
    allow(Crm::Timezone::Resolver).to receive(:new).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect(Autonomia::FerramentasProntas.fuso_da_conta(account)).to eq(Time.zone)
    expect(Autonomia::FerramentasProntas::Premium.hoje_da_conta(account)).to eq(Time.current.in_time_zone(Time.zone).to_date)
    expect(logs.string).to include('fuso da conta indisponível')
  end

  it 'o mês das grátis é o do fuso da conta' do
    account.update!(custom_attributes: { 'timezone' => 'America/Sao_Paulo' })
    travel_to(Time.utc(2026, 12, 1, 2, 0, 0)) do
      expect(Autonomia::FerramentasProntas::Premium.mes_da_conta(account)).to eq(Date.new(2026, 11, 1))
    end
  end

  it 'a 20ª ainda é grátis' do
    cnj_responde
    saldo_premium!(account, 'certidoes_empresa', 19)

    executar_premium(certidoes, cnj)

    expect(registros_premium.sole).to have_attributes(numero: 20, cobranca: 'gratis', preco: 0)
  end

  it 'sem registro: a resposta diz "não havia registro" e a consulta conta' do
    cnj_responde(nil)
    saldo_premium!(account, 'certidoes_empresa', 20)

    resposta = executar_premium(certidoes, cnj)

    expect(resposta['situacao']).to eq('nao_encontrado')
    expect(resposta['orientacao']).to include('não havia registro')
    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'cobrada', preco: BigDecimal('0.15'))
    expect(usos.sole.nao_encontradas).to eq(1)
  end

  it 'o código de "nenhum resultado" da BigDataCorp também é sem registro' do
    cnj_responde([], code: -204, message: 'NO RESULTS FOUND FOR THE PROVIDED PARAMETERS')

    expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_encontrado')
    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'gratis', numero: 1)
  end

  it 'a fonte lenta (DATASET IS TOO SLOW) não conta para o cliente' do
    cnj_responde(nil, code: -1201, message: 'DATASET IS TOO SLOW. PLEASE TRY AGAIN IN A FEW MINUTES')

    resposta = executar_premium(certidoes, cnj)

    expect(resposta['situacao']).to eq('nao_consegui_consultar')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', cobranca: 'sem_cobranca', numero: nil, custo: 0,
                                                      motivo: 'fonte_lenta')
    expect(saldos.count).to eq(0)
    expect(usos.sole.motivos).to eq('bigdatacorp.fonte_lenta' => 1)
  end

  it 'o 504 não conta e não é repetido (consulta paga não repete)' do
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return(status: 504, body: '')

    expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', cobranca: 'sem_cobranca', motivo: 'http_504', custo: 0)
    expect(a_bigdatacorp).to have_been_made.once
    expect(saldos.count).to eq(0)
  end

  it 'a mesma consulta no mesmo dia vem do cache, sem custo novo; outra conta não lê o cache desta' do
    cnj_responde
    da_outra = incluir_pronta('certidoes_empresa', conta: outra_conta, agente: criar_agente(outra_conta))

    executar_premium(certidoes, cnj)
    repetida = executar_premium(certidoes, cnj)
    executar_premium(da_outra, cnj)

    expect(repetida['situacao']).to eq('encontrado')
    expect(a_bigdatacorp).to have_been_made.twice
    primeira, do_cache, outra = registros_premium.to_a
    expect(primeira).to have_attributes(do_cache: false, numero: 1)
    expect(do_cache).to have_attributes(do_cache: true, cobranca: 'sem_cobranca', custo: 0, preco: 0, numero: nil,
                                        resultado: 'encontrado')
    expect(outra).to have_attributes(account_id: outra_conta.id, do_cache: false, numero: 1)
  end

  it 'o "sem registro" do dia também vem do cache, sem contar de novo' do
    cnj_responde(nil)

    executar_premium(certidoes, cnj)
    expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_encontrado')

    expect(a_bigdatacorp).to have_been_made.once
    expect(registros_premium.last).to have_attributes(do_cache: true, resultado: 'sem_registro', cobranca: 'sem_cobranca')
  end

  it 'o Premium não tem limite diário: o contador do dia passa de qualquer teto sem recusar' do
    cnj_responde
    certidoes
    usos.create!(account: account, fonte: 'certidoes_empresa', dia: Time.zone.today, consultas: 10_000)

    expect(executar_premium(certidoes, cnj)['situacao']).to eq('encontrado')
    expect(usos.sole).to have_attributes(consultas: 10_001, recusadas: 0)
    expect(Autonomia::FerramentasProntas::Acesso.sole.limite_do_dia).to be_nil
  end

  it 'pedido de contato de pessoa física (um CPF no card de contato) é recusado sem chamar a BigDataCorp' do
    resposta = executar_premium(contato, 'consulta' => 'telefone', 'cnpj' => '111.444.777-35')

    expect(resposta['situacao']).to eq('pedido_invalido')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.count).to eq(0)
  end

  # A vistoria está desligada na BigDataCorp desde 12/11 (#2946): o card volta a ter a consulta quando ela religar, e a
  # regra dela (o vazio não tem custo) tem de continuar certa.
  it 'a vistoria sem registro conta para o cliente, mas não tem custo da BigDataCorp' do
    desligar_na_fonte!([])
    bigdatacorp_responde('/marketplace', 'partner_rede_vistorias_address', 'RedeVistoriasData', nil)

    executar_premium(risco, 'consulta' => 'vistoria', 'cep' => '01001-000', 'numero' => '10')

    expect(registros_premium.sole).to have_attributes(resultado: 'sem_registro', cobranca: 'gratis', numero: 1, custo: 0)
    expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/marketplace")
             .with(body: hash_including('q' => 'zipcode{01001000},addressnumber{10}'))).to have_been_made.once
  end

  # #2946: a consulta desligada na BigDataCorp que o modelo pede pelo nome (um agente com o schema antigo, um modelo que
  # insiste) é recusada antes da fonte: nada sai, nada conta.
  it 'a consulta desligada pedida pelo nome é recusada: pedido inválido, sem chamar a BigDataCorp, sem registro nem uso' do
    resposta = executar_premium(certidoes, 'consulta' => 'divida_uniao', 'cnpj' => '11.222.333/0001-81')

    expect(resposta['situacao']).to eq('pedido_invalido')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.count).to eq(0)
    expect(usos.sum(:consultas)).to eq(0)
  end

  it 'com a flag do Premium desligada, nada é consultado nem registrado' do
    certidoes
    account.disable_features!(Autonomia::FerramentasProntas::Premium::FLAG)

    expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.count).to eq(0)
  end

  it 'sem a credencial na plataforma, falha sem contar e sem chamar' do
    certidoes
    with_modified_env(BIGDATACORP_USER: nil, BIGDATACORP_PASSWORD: nil) do
      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
    end

    expect(chamou_a_bigdatacorp?).to be(false)
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'nao_configurada', cobranca: 'sem_cobranca')
  end

  it 'a credencial, o token e o documento consultado nunca aparecem em log, resposta ou telemetria' do
    cnj_responde
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/empresas").to_return(status: 500, body: FerramentasPremiumHelper::SENHA_FALSA)

    textos = [executar_premium(certidoes, cnj).to_json,
              executar_premium(raio_x, 'consulta' => 'processos', 'cnpj' => FerramentasPremiumHelper::CNPJ_EXEMPLO).to_json,
              registros_premium.map(&:attributes).to_json, logs.string]

    textos.each do |texto|
      expect(texto).not_to include(FerramentasPremiumHelper::SENHA_FALSA, FerramentasPremiumHelper::USUARIO_FALSO,
                                   FerramentasPremiumHelper::TOKEN_FALSO, FerramentasPremiumHelper::CNPJ_EXEMPLO)
    end
    expect(registros_premium.last).to have_attributes(resultado: 'falha', motivo: 'http_500')
  end

  it 'não existe mais o alerta de 80% do orçamento (decisão do Rodrigo, 11/11)' do
    expect(defined?(Autonomia::FerramentasProntas::Premium::Orcamento)).to be_nil
    expect(defined?(AdministratorNotifications::PremiumMailer)).to be_nil
  end

  describe 'a telemetria' do
    it 'conta e registro andam juntos: se o registro falha, o contador volta atrás e a resposta segue' do
      cnj_responde
      allow(Autonomia::FerramentasProntas::Premium::Registro).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('encontrado')
      expect(saldos.count).to eq(0)
      expect(logs.string).to include('telemetria premium falhou', 'ActiveRecord::RecordInvalid')
    end

    it 'duplicidade em outro índice não é a entrega incerta: sobe como defeito da execução, ao rastreador' do
      cnj_responde
      allow(Autonomia::FerramentasProntas::Premium::Registro).to receive(:create!)
        .and_raise(ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint "outro_indice"')
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
      expect(usos.sole.motivos).to eq('defeito' => 1)
      expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(ActiveRecord::RecordNotUnique), account: account)
      expect(logs.string).not_to include('já fechada como entrega incerta')
    end

    it 'erro que não é do banco não é tratado como telemetria: sobe como defeito da execução, ao rastreador' do
      cnj_responde
      allow(Autonomia::FerramentasProntas::Premium::Cobranca).to receive(:registrar!).and_raise(NoMethodError)
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
      expect(usos.sole.motivos).to eq('defeito' => 1)
      expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(NoMethodError), account: account)
      expect(logs.string).not_to include('telemetria premium falhou')
    end
  end

  describe 'a resposta da BigDataCorp fora do formato' do
    it 'vai ao rastreador e ao log com a classe do erro e o dataset, sem o valor consultado' do
      cnj_responde('texto solto')
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      resposta = executar_premium(certidoes, cnj)

      expect(resposta['situacao']).to eq('nao_consegui_consultar')
      expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'resposta_invalida')
      expect(logs.string).to include('[autonomia][premium] resposta_invalida dataset=ondemand_cnj_negative_certificate_company')
      expect(logs.string).not_to include(FerramentasPremiumHelper::CNPJ_EXEMPLO, 'texto solto')
      expect(ChatwootExceptionTracker).to have_received(:new)
    end
  end

  # Revisor (MÉDIO, execucao.rb:54): o defeito nosso ao ler, depois de a BigDataCorp responder, não pode sumir com o
  # custo dela. A linha vira falha por defeito, com o custo do dataset (sem contar para o cliente), e o defeito sobe.
  it 'o defeito ao ler a resposta grava o custo como falha por defeito e sobe ao rastreador' do
    cnj_responde
    allow(Autonomia::FerramentasProntas::Premium::Leitura).to receive(:de).and_raise(NoMethodError)
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
    expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'defeito', cobranca: 'sem_cobranca', numero: nil,
                                                      custo: BigDecimal('0.10'), preco: 0)
    expect(saldos.count).to eq(0)
    expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(NoMethodError), account: account)
  end

  describe 'o token e o prazo da chamada' do
    it 'o token vale para as consultas seguintes do processo enquanto não vence' do
      cnj_responde

      executar_premium(certidoes, cnj)
      executar_premium(certidoes, cnj.merge('cnpj' => '11.444.777/0001-61'))

      expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/tokens/gerar")).to have_been_made.once
      expect(a_bigdatacorp).to have_been_made.twice
    end

    it 'o token guardado que a BigDataCorp recusa (401) é apagado, e um reenvio com token novo responde' do
      Autonomia::FerramentasProntas::Premium::BigDataCorp::TOKENS.write(
        Autonomia::Prospecting::Research::BigDataCorpClient::Token.new(access_token: 'token-velho', token_id: 'id-velho', expires_at: Float::INFINITY)
      )
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand")
        .with(headers: { 'AccessToken' => 'token-velho' }).to_return(status: 401, body: '')
      corpo = corpo_da_bigdatacorp('ondemand_cnj_negative_certificate_company', 'OnlineCertificates', certidao_negativa).to_json
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand")
        .with(headers: { 'AccessToken' => FerramentasPremiumHelper::TOKEN_FALSO }).to_return(status: 200, body: corpo)

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('encontrado')
      expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/tokens/gerar")).to have_been_made.once
      expect(a_bigdatacorp).to have_been_made.twice
      expect(Autonomia::FerramentasProntas::Premium::BigDataCorp::TOKENS.read.access_token).to eq(FerramentasPremiumHelper::TOKEN_FALSO)
      expect(registros_premium.sole).to have_attributes(resultado: 'encontrado', numero: 1)
    end

    it 'o 401 depois do reenvio é falha que não conta, e o token recusado não fica guardado' do
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return(status: 401, body: '')

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
      expect(a_bigdatacorp).to have_been_made.twice
      expect(Autonomia::FerramentasProntas::Premium::BigDataCorp::TOKENS.read).to be_nil
      expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'http_401', cobranca: 'sem_cobranca')
    end

    it 'o token que não chega no prazo curto tem uma tentativa só, e a consulta não sai' do
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/tokens/gerar").to_timeout

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
      expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/tokens/gerar")).to have_been_made.once
      expect(a_bigdatacorp).not_to have_been_made
      expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'token', cobranca: 'sem_cobranca')
    end

    it 'o prazo total da chamada cabe no prazo da consulta (e no da ferramenta)' do
      cliente = Autonomia::FerramentasProntas::Premium::BigDataCorp.new(nil, prazo: 20).send(:novo_cliente)
      opcoes = cliente.instance_variable_get(:@options)

      expect(opcoes).to include(max_provider_attempts: 1, max_token_attempts: 1,
                                token_timeout: Autonomia::FerramentasProntas::Premium::BigDataCorp::PRAZO_DO_TOKEN)
      expect(Autonomia::FerramentasProntas::Catalogo.premium.flat_map(&:consultas))
        .to all(satisfy { |consulta| consulta.dataset.prazo <= consulta.prazo_total })
      expect(Autonomia::FerramentasProntas::Catalogo.premium)
        .to all(satisfy { |fonte| fonte.consultas.map { |consulta| consulta.dataset.prazo }.max < fonte.prazo_maximo + 1 })
    end

    it 'a chamada que passa do prazo total vira tempo esgotado, sem contar' do
      cnj_responde
      allow(Timeout).to receive(:timeout).and_call_original
      allow(Timeout).to receive(:timeout).with(Autonomia::FerramentasProntas::Premium::Dataset::PRAZO_SOB_DEMANDA).and_raise(Timeout::Error)

      expect(executar_premium(certidoes, cnj)['situacao']).to eq('nao_consegui_consultar')
      expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'tempo_esgotado', cobranca: 'sem_cobranca')
      expect(saldos.count).to eq(0)
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
    expect(Autonomia::FerramentasProntas.executor_para(certidoes, params: cnj)).to be_a(described_class)
    expect(Autonomia::FerramentasProntas.executor_para(incluir_pronta('cep', conta: account, agente: agent), params: {}).class)
      .to eq(Autonomia::FerramentasProntas::Execucao)
    expect(Autonomia::FerramentasProntas.calculada_aqui?(certidoes)).to be(false)
  end

  # O Experimente do card Premium (decisão A do Rodrigo, 11/11) está em `experimente_premium_spec.rb`.
end
