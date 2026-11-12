require 'rails_helper'
require 'timeout'

# #2858 (F7): a 20ª e a 21ª consulta do mês ao mesmo tempo, em duas conexões reais do Postgres, com as duas chamadas à
# BigDataCorp (dublada) seguras no meio até as duas chegarem. Uma sai grátis e a outra cobrada: nem grátis a mais, nem
# cobrança dupla. Sem a transação do exemplo (cada thread tem a sua conexão), então limpa tudo no after.
RSpec.describe Autonomia::FerramentasProntas::Premium::Saldo do
  self.use_transactional_tests = false

  let!(:account) { Account.create!(name: 'Conta EXEMPLO concorrência') }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  around { |example| com_credencial_da_bigdatacorp { Timeout.timeout(60) { example.run } } }

  after do
    conta = account.id
    Autonomia::FerramentasProntas::Premium::Registro.where(account_id: conta).delete_all
    described_class.where(account_id: conta).delete_all
    Autonomia::FerramentasProntas::Uso.where(account_id: conta).delete_all
    Autonomia::FerramentasProntas::Acesso.where(account_id: conta).delete_all
    Autonomia::Agents::Tool.where(account_id: conta).delete_all
    Autonomia::Agents::Agent.where(account_id: conta).delete_all
    account.destroy!
  end

  def segurar_a_bigdatacorp(chegaram, libera)
    corpo = corpo_da_bigdatacorp('ondemand_pgfn_company', 'OnlineCertificates', [{ 'BaseStatus' => 'NEGATIVA' }]).to_json
    stub_request(:post, "#{FerramentasPremiumHelper::BDC}/ondemand").to_return do |_pedido|
      chegaram << 1
      libera.pop
      { status: 200, body: corpo, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def consultar_em_paralelo(ferramenta, cnpjs, resultados)
    cnpjs.map do |cnpj|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          tool = Autonomia::Agents::Tool.find(ferramenta.id)
          resultados << executar_premium(tool, 'consulta' => 'divida_uniao', 'cnpj' => cnpj)['situacao']
        end
      rescue StandardError => e
        resultados << "erro #{e.class}"
      end
    end
  end

  it 'a 20ª e a 21ª ao mesmo tempo: uma grátis e uma cobrada' do
    ligar_premium(account)
    cache_em_memoria
    token_da_bigdatacorp
    ferramenta = incluir_pronta('certidoes_empresa', conta: account, agente: agent)
    saldo_premium!(account, 'certidoes_empresa', 19)
    chegaram = Queue.new
    libera = Queue.new
    resultados = Queue.new
    segurar_a_bigdatacorp(chegaram, libera)

    threads = consultar_em_paralelo(ferramenta, %w[11.222.333/0001-81 11.444.777/0001-61], resultados)
    Timeout.timeout(15) { 2.times { chegaram.pop } }
    2.times { libera << true }
    threads.each { |thread| expect(thread.join(20)).to be_truthy }

    expect(Array.new(2) { resultados.pop }).to eq(%w[encontrado encontrado])
    linhas = Autonomia::FerramentasProntas::Premium::Registro.where(account_id: account.id).order(:numero)
    expect(linhas.map { |linha| [linha.numero, linha.cobranca, linha.preco] }).to eq([[20, 'gratis', 0], [21, 'cobrada', BigDecimal('0.15')]])
    expect(described_class.find_by!(account_id: account.id, fonte: 'certidoes_empresa').contadas).to eq(21)
  end
end
