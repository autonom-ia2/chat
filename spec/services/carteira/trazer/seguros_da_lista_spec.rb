require 'rails_helper'

# E4 (#2897) — o que o "Desfazer" de uma lista faz com os seguros que ela pôs na carteira: quais saem, quais voltam ao que
# eram e quais ficam, regra a regra. A lista é gravada pelo caminho da tela (por isso o spec fala com as rotas); o tipo de
# cada ramo é de um dublê. Todos os dados são inventados.
RSpec.describe Carteira::Trazer::SegurosDaLista, :aggregate_failures, type: :request do
  include_context 'with planilha de seguros'

  let(:todos) { %w[EX-001234 EX-005678 EX-009999 VD-000042] }

  def da(importacao)
    described_class.new(importacao.reload)
  end

  def que_voltam(importacao)
    achados = []
    da(importacao).que_voltam { |bloco| achados.concat(bloco) }
    achados.map { |apolice, colunas| [apolice.numero, colunas.transform_keys(&:to_s)] }
  end

  describe 'o que a lista criou' do
    it 'sai o seguro em que ninguém mexeu, e nenhum segura a pessoa' do
      importacao = trazer_tudo(planilha_de(seguros_bons))
      lista = da(importacao)

      expect([lista.tem?, lista.trouxe_seguros?]).to eq([true, true])
      expect(lista.saem.pluck(:numero)).to match_array(todos)
      expect(lista.que_ficam).to be_empty
      expect(lista.previa).to eq(saem: 4, ficam: 0, voltam: 0)
    end

    {
      'foi corrigido à mão' => ->(seguro) { seguro.update!(bem: 'Moto Corrigida', corrigido_a_mao: ['bem']) },
      'tem uma dúvida anotada' => ->(seguro) { seguro.update!(duvidas: ['bem']) },
      'foi cancelado' => ->(seguro) { seguro.update!(cancelado_em: Time.current) },
      'ganhou o PDF' => ->(seguro) { guardar_pdf_na(seguro) },
      'tem na história um passo que não é da lista' => ->(seguro) { seguro.eventos.create!(tipo: 'corrigido', quando: Time.current, user: admin) },
      'teve o desfecho da renovação' => ->(seguro) { seguro.update!(renovado_em: Time.current) },
      'tem a apólice nova da renovação' => lambda { |seguro|
        criar_apolice(seguro.contact, seguradora: seguro.seguradora, numero: 'EX-NOVA-1', apolice_anterior: seguro)
      },
      'passou a ser de outra fonte' => ->(seguro) { seguro.update!(origem: 'pdf') },
      'é de outra corretora' => ->(seguro) { seguro.update!(de_fora: true) }
    }.each do |o_que_houve, mexer|
      it "fica o seguro que #{o_que_houve}" do
        importacao = trazer_tudo(planilha_de(seguros_bons))
        mexido = apolice('EX-009999')
        instance_exec(mexido, &mexer)
        lista = da(importacao)

        expect(lista.saem.pluck(:numero)).to match_array(todos - ['EX-009999'])
        expect(lista.sai?(mexido)).to be(false)
        expect(lista.que_ficam.where(campaign_import_id: importacao.id).pluck(:numero)).to eq(['EX-009999'])
        expect(lista.previa).to include(saem: 3, ficam: 1)
      end
    end

    it 'fica o seguro que outra lista trouxe de novo depois' do
      importacao = trazer_tudo(planilha_de(seguros_bons))
      mudada = 'Bruno Brandolim;11987650002;;EX-009999;Seguradora Exemplo;Automóvel;05/01/2026;05/01/2027;2.500;Moto Exemplo XYZ9A87'
      trazer_tudo(planilha_de(mudada))

      expect(da(importacao).saem.pluck(:numero)).to match_array(todos - ['EX-009999'])
    end
  end

  describe 'o que a lista só completou' do
    let(:pessoa) { create(:contact, account: account, name: 'Ana A.', phone_number: '+5511987650001') }
    # O seguro do carro já estava na carteira, com outro valor.
    let!(:carro) do
      criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-001234', inicio_vigencia: Date.new(2026, 3, 10),
                            fim_vigencia: Date.new(2027, 3, 10), valor_centavos: 100_000, bem: 'Carro Exemplo ABC1D23')
    end

    it 'volta com o valor de antes de cada campo que a lista mudou, e não sai' do
      importacao = trazer_tudo(planilha_de(seguros_bons))

      expect(carro.reload.valor_centavos).to eq(341_000)
      expect(que_voltam(importacao)).to eq([['EX-001234', { 'valor_centavos' => 100_000 }]])
      expect(da(importacao).saem.pluck(:numero)).to match_array(todos - ['EX-001234'])
      expect(da(importacao).previa).to eq(saem: 3, ficam: 0, voltam: 1)
    end

    it 'mudado por duas listas, só a última pode voltar, e para o valor que ela encontrou' do
      primeira = trazer_tudo(planilha_de(seguros_bons))
      mudada = "#{ana};EX-001234;Seguradora Exemplo;Automóvel;10/03/2026;10/03/2027;R$ 3.900;Carro Exemplo ABC1D23"
      segunda = trazer_tudo(planilha_de(mudada))

      # Depois da primeira veio a segunda: a primeira não desfaz por cima.
      expect(que_voltam(primeira)).to eq([])
      expect(que_voltam(segunda)).to eq([['EX-001234', { 'valor_centavos' => 341_000 }]])
    end

    it 'não volta se alguém mudou o campo depois, se o seguro foi cancelado ou se veio um passo de outra origem' do
      importacao = trazer_tudo(planilha_de(seguros_bons))

      carro.reload.update!(valor_centavos: 90_000)
      expect(que_voltam(importacao)).to eq([])

      carro.update!(valor_centavos: 341_000, cancelado_em: Time.current)
      expect(que_voltam(importacao)).to eq([])

      carro.update!(cancelado_em: nil)
      expect(que_voltam(importacao)).to eq([['EX-001234', { 'valor_centavos' => 100_000 }]])
      carro.eventos.create!(tipo: 'pdf_anexado', quando: Time.current, user: admin)
      expect(que_voltam(importacao)).to eq([])
      expect(da(importacao).previa).to eq(saem: 3, ficam: 1, voltam: 0)
    end

    it 'o seguro que já existia continua segurando a pessoa na base' do
      importacao = trazer_tudo(planilha_de(seguros_bons))

      expect(da(importacao).que_ficam.pluck(:id)).to eq([carro.id])
    end
  end

  describe 'de quem é' do
    it 'a lista sem seguros não tem nada para desfazer na carteira, e os seguros da conta continuam segurando as pessoas' do
      de_antes = criar_apolice(create(:contact, account: account), seguradora: 'Seguradora Exemplo', numero: 'EX-000001')
      importacao = ler_planilha
      responder(importacao, seguros: 'nao')
      ler_de_novo
      trazer(importacao)
      gravar_a_lista
      lista = da(importacao)

      expect([lista.tem?, lista.trouxe_seguros?]).to eq([false, false])
      expect(lista.que_ficam.pluck(:id)).to eq([de_antes.id])
    end

    it 'só olha os seguros da conta da lista' do
      outra = conta_com_carteira
      de_fora = criar_apolice(create(:contact, account: outra), seguradora: 'Seguradora Exemplo', numero: 'EX-001234')
      importacao = trazer_tudo(planilha_de(seguros_bons))
      lista = da(importacao)

      expect(lista.saem.pluck(:account_id).uniq).to eq([account.id])
      expect(lista.que_ficam.pluck(:id)).not_to include(de_fora.id)
      expect(lista.sai?(de_fora)).to be(false)
    end
  end
end
