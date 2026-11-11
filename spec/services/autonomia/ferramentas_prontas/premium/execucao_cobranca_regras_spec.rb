require 'rails_helper'

# #2858 (F7): as regras de cobrança que o revisor e o testador apontaram no lote final, com a BigDataCorp dublada (zero
# chamada real). Decisões do Rodrigo: consulta sem resultado e documento inválido são cobrados; DATASET IS TOO SLOW e
# 504 não; o documento com dígito errado que NÓS recusamos antes de chamar a BigDataCorp não conta ("A, não conta",
# 11/11).
RSpec.describe Autonomia::FerramentasProntas::Premium::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:certidoes) { incluir_pronta('certidoes_empresa', conta: account, agente: agent) }
  let(:pessoa) { incluir_pronta('conferir_pessoa', conta: account, agente: agent) }
  let(:saldos) { Autonomia::FerramentasProntas::Premium::Saldo }
  let(:pgfn) { { 'consulta' => 'divida_uniao', 'cnpj' => '11.222.333/0001-81' } }

  def pgfn_responde(dado, **)
    bigdatacorp_responde('/ondemand', 'ondemand_pgfn_company', 'OnlineCertificates', dado, **)
  end

  around { |example| com_credencial_da_bigdatacorp { example.run } }

  before do
    ligar_premium(account)
    cache_em_memoria
    token_da_bigdatacorp
  end

  describe 'documento inválido' do
    # C04e do testador: o dígito errado é recusado por nós, antes de qualquer gasto, e não é consulta do cliente.
    it 'CPF ou CNPJ com dígito errado é recusado por nós, sem chamar a BigDataCorp, e NÃO conta como consulta' do
      cnpj = executar_premium(certidoes, pgfn.merge('cnpj' => '11.222.333/0001-82'))
      cpf = executar_premium(pessoa, 'consulta' => 'situacao_cpf', 'cpf' => '111.444.777-36')

      expect([cnpj['situacao'], cpf['situacao']]).to eq(%w[pedido_invalido pedido_invalido])
      expect([cnpj['campo'], cpf['campo']]).to eq(%w[cnpj cpf])
      expect(chamou_a_bigdatacorp?).to be(false)
      expect(registros_premium).to be_empty
      expect(saldos.count).to eq(0)
    end

    # C04d do testador: o -114 "INVALID DOC PARAMETER" é a BigDataCorp recusando o documento depois de receber o pedido.
    it 'o documento recusado PELA BigDataCorp (-114) conta e tem custo, como o sem registro, e o agente confere o documento' do
      pgfn_responde(nil, code: -114, message: 'INVALID DOC PARAMETER')

      resposta = executar_premium(certidoes, pgfn)

      expect(resposta).to include('situacao' => 'documento_invalido')
      expect(resposta['orientacao']).to include('confira', 'cliente')
      expect(registros_premium.sole).to have_attributes(resultado: 'documento_invalido', cobranca: 'gratis', numero: 1,
                                                        custo: BigDecimal('0.10'), preco: 0)
    end

    it 'da 21ª em diante o documento inválido da BigDataCorp é cobrado, como qualquer consulta contada' do
      pgfn_responde(nil, code: -114, message: 'INVALID DOC PARAMETER')
      saldo_premium!(account, 'certidoes_empresa', 20)

      executar_premium(certidoes, pgfn)

      expect(registros_premium.sole).to have_attributes(resultado: 'documento_invalido', cobranca: 'cobrada', numero: 21,
                                                        preco: BigDecimal('0.15'))
    end

    it 'o código do CAR recusado pela BigDataCorp (-155) também é documento inválido' do
      leitura = Autonomia::FerramentasProntas::Premium::Leitura.pelo_status({ 'Code' => -155, 'Message' => 'INVALID CAR NUMBER PARAMETER' }, nil)

      expect(leitura.situacao).to eq('documento_invalido')
    end

    it 'o mesmo documento inválido no mesmo dia vem do cache e não conta de novo' do
      pgfn_responde(nil, code: -114, message: 'INVALID DOC PARAMETER')

      executar_premium(certidoes, pgfn)
      segunda = executar_premium(certidoes, pgfn)

      expect(segunda['situacao']).to eq('documento_invalido')
      expect(a_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand")).to have_been_made.once
      expect(registros_premium.last).to have_attributes(resultado: 'documento_invalido', do_cache: true, cobranca: 'sem_cobranca', custo: 0)
      expect(saldos.sole.contadas).to eq(1)
    end
  end

  # Aceite 11: a telemetria bate com o painel da BigDataCorp. A falha em que o pedido já saiu pode ter sido cobrada lá:
  # o custo do dataset fica na linha, sem contar para o cliente (o padrão do `entrega_incerta!`).
  describe 'o custo da falha depois de o pedido sair' do
    def falha_registrada
      registros_premium.sole.tap do |registro|
        expect(registro).to have_attributes(resultado: 'falha', cobranca: 'sem_cobranca', numero: nil, preco: 0)
      end
    end

    it 'a resposta 200 num formato que não lemos: custo do dataset, sem contar' do
      pgfn_responde('texto solto')

      executar_premium(certidoes, pgfn)

      expect(falha_registrada).to have_attributes(motivo: 'resposta_invalida', custo: BigDecimal('0.10'))
      expect(saldos.count).to eq(0)
    end

    it 'o tempo esgotado esperando a resposta (o pedido saiu): custo do dataset, sem contar' do
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_raise(Net::ReadTimeout)

      executar_premium(certidoes, pgfn)

      expect(falha_registrada).to have_attributes(motivo: 'tempo_esgotado', custo: BigDecimal('0.10'))
    end

    it 'o teto da chamada inteira (o token já veio, a consulta estava no ar): custo do dataset, sem contar' do
      pgfn_responde([])
      allow(Timeout).to receive(:timeout).and_call_original
      allow(Timeout).to receive(:timeout).with(Autonomia::FerramentasProntas::Premium::Dataset::PRAZO_SOB_DEMANDA).and_raise(Timeout::Error)

      executar_premium(certidoes, pgfn)

      expect(falha_registrada).to have_attributes(motivo: 'tempo_esgotado', custo: BigDecimal('0.10'))
    end

    it 'a entrega incerta (a conexão caiu com o pedido no ar, ou 200 sem JSON): custo do dataset, sem contar' do
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_raise(Errno::ECONNRESET)

      executar_premium(certidoes, pgfn)

      expect(falha_registrada).to have_attributes(motivo: 'entrega_incerta', custo: BigDecimal('0.10'))
    end

    it 'a conexão que nem abriu (o pedido não saiu): sem custo' do
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_raise(Net::OpenTimeout)

      executar_premium(certidoes, pgfn)

      expect(falha_registrada).to have_attributes(motivo: 'tempo_esgotado', custo: 0)
    end

    it 'DATASET IS TOO SLOW e o 504 continuam sem custo' do
      pgfn_responde(nil, code: -1201, message: 'DATASET IS TOO SLOW. PLEASE TRY AGAIN IN A FEW MINUTES')
      executar_premium(certidoes, pgfn)
      stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return(status: 504, body: '')
      executar_premium(certidoes, pgfn.merge('cnpj' => '11.444.777/0001-61'))

      expect(registros_premium.map { |registro| [registro.motivo, registro.custo] }).to eq([['fonte_lenta', 0], ['http_504', 0]])
    end
  end

  # Revisor (execucao.rb:41): a cobrança vinha antes de montar a resposta. Se a montagem levantava, a linha ficava
  # cobrada e o cliente recebia "não consegui".
  describe 'a cobrança depois de montar a resposta' do
    it 'a montagem que levanta não cobra o cliente: a linha é falha por defeito, com o nosso custo' do
      pgfn_responde([{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA' }])
      allow(Autonomia::FerramentasProntas::Resposta).to receive(:encontrado).and_raise(NoMethodError)

      resposta = executar_premium(certidoes, pgfn)

      expect(resposta['situacao']).to eq('nao_consegui_consultar')
      expect(registros_premium.sole).to have_attributes(resultado: 'falha', motivo: 'defeito', cobranca: 'sem_cobranca', numero: nil,
                                                        custo: BigDecimal('0.10'), preco: 0)
      expect(saldos.count).to eq(0)
    end

    it 'a resposta montada é cobrada uma vez só' do
      pgfn_responde([{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA' }])

      expect(executar_premium(certidoes, pgfn)['situacao']).to eq('encontrado')
      expect(registros_premium.sole).to have_attributes(resultado: 'encontrado', cobranca: 'gratis', numero: 1)
    end
  end

  # Revisor (execucao.rb:68): o log some e o Sentry está desligado em produção. A falha da telemetria deixa marca no
  # contador do dia (`Uso#motivos`), que a conferência do dia lê.
  describe 'o rastro da telemetria que falha' do
    it 'a falha do banco ao gravar a linha marca premium.telemetria_falhou no contador do dia, e a resposta segue' do
      pgfn_responde([{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA' }])
      allow(Autonomia::FerramentasProntas::Premium::Registro).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect(executar_premium(certidoes, pgfn)['situacao']).to eq('encontrado')
      uso = Autonomia::FerramentasProntas::Uso.sole
      expect(uso).to have_attributes(account_id: account.id, fonte: 'certidoes_empresa', dia: Time.zone.today)
      expect(uso.motivos).to include('premium.telemetria_falhou' => 1)
    end

    it 'a marca também falhando não derruba a resposta' do
      pgfn_responde([{ 'Origin' => 'PGFN', 'BaseStatus' => 'NEGATIVA' }])
      allow(Autonomia::FerramentasProntas::Premium::Registro).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Autonomia::FerramentasProntas::Uso).to receive(:anotar!).and_call_original
      allow(Autonomia::FerramentasProntas::Uso).to receive(:anotar!).with(hash_including(motivos: ['premium.telemetria_falhou']))
                                                                    .and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(executar_premium(certidoes, pgfn)['situacao']).to eq('encontrado')
    end
  end
end
