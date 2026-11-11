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
end
