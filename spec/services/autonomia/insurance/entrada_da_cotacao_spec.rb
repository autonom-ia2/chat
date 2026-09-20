require 'rails_helper'

# O RESUMO DA ENTRADA DE UMA COTAÇÃO (#515). Dados sintéticos.
RSpec.describe Autonomia::Insurance::EntradaDaCotacao do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO }

  def resumo(argumentos, com_schema: schema)
    described_class.new(argumentos, schema: com_schema).texto
  end

  def renovacao
    { 'produto' => 'auto', 'cep' => '01310-930',
      'quotation' => { 'isRenewal' => true, 'bonusClass' => 9, 'previousClaimsCount' => 1,
                       'previousInsurerCode' => '657' } }
  end

  describe 'o que o modelo lê' do
    it 'a renovação aparece com bônus, seguradora anterior e sinistros' do
      texto = resumo(renovacao)

      expect(texto).to include('renovação de apólice anterior')
      expect(texto).to include('Classe de bônus: 9.')
      expect(texto).to include('Seguradora anterior: HDI.')
      expect(texto).to include('Sinistros na vigência anterior: 1.')
    end

    # O caso do #515: "o bônus da apólice foi considerado?" tem resposta no texto da ferramenta.
    it 'o seguro novo aparece como seguro novo, e o bônus como não informado' do
      texto = resumo({ 'produto' => 'auto', 'cep' => '01310-930' })

      expect(texto).to include('seguro novo')
      expect(texto).not_to include('renovação de apólice anterior')
      expect(texto).to include("Classe de bônus: #{described_class::SEM_INFORMACAO}")
    end

    # NUNCA AFIRMAR O QUE NÃO FOI ENVIADO: o campo ausente entra como ausente, e o modelo lê, junto,
    # o que fazer com ele.
    it 'campo ausente não vira afirmação' do
      texto = resumo(renovacao)

      expect(texto).to include("Franquia: #{described_class::SEM_INFORMACAO}")
      expect(texto).to include("Carro reserva: #{described_class::SEM_INFORMACAO}")
      expect(texto).to include(described_class::AUSENCIA)
    end

    it 'o CEP de pernoite entra como o cliente o informou' do
      texto = resumo(renovacao.merge('vehicle' => { 'overnightZipCode' => '04547000' }))

      expect(texto).to include('CEP onde o veículo dorme: 04547000.')
      expect(texto).to include('CEP do endereço do segurado: 01310930.')
    end

    # QUEM ESCREVE PREÇO É A LIA, a partir dos preços da cotação e conferida (`ConferenciaDePrecos`).
    # Um valor em reais aqui entraria na lista do que ela pode escrever como preço.
    it 'nenhum valor em reais no resumo' do
      texto = resumo(renovacao.merge('coverage' => { 'deductibleType' => 2, 'propertyDamage' => 100_000,
                                                     'bodilyInjury' => 100_000 }))

      expect(Autonomia::Agents::ConferenciaDePrecos.valores(texto)).to be_empty
      expect(texto).not_to include('R$')
      expect(texto).not_to include('100000')
    end

    # NOME DE CAMPO CRU NUNCA: o cliente já leu `insured.document` no WhatsApp uma vez (ver `Recusas`).
    it 'não escreve nome de campo do formulário' do
      texto = resumo(renovacao.merge('vehicle' => { 'youngDriver' => true },
                                     'coverage' => { 'deductibleType' => 2, 'glassCoverage' => 2 }))

      expect(texto).not_to match(/[a-z]+\.[a-zA-Z]+/)
      expect(texto).to include('Franquia: 100%.')
      expect(texto).to include('Vidros: Completo.')
      expect(texto).to include('Condutor jovem: sim.')
    end
  end

  describe 'o nome da opção vem do schema do adapter' do
    # O código nunca sai cru: sem o nome, a linha diz que a opção foi enviada e manda não descrevê-la.
    it 'sem schema, a opção enviada não vira código' do
      texto = resumo({ 'produto' => 'auto', 'coverage' => { 'deductibleType' => 2 } }, com_schema: nil)

      expect(texto).to include("Franquia: #{described_class::SEM_NOME}")
      expect(texto).not_to include('Franquia: 2')
    end

    it 'valor fora da lista do schema também não vira código' do
      texto = resumo({ 'produto' => 'auto', 'coverage' => { 'glassCoverage' => 99 } })

      expect(texto).to include("Vidros: #{described_class::SEM_NOME}")
      expect(texto).not_to include('99')
    end
  end

  describe 'quando não há resumo' do
    it 'ramo que não é auto não tem resumo' do
      expect(resumo({ 'produto' => 'bike', 'dados' => '{"configuracoes":{"marca":"Caloi"}}' })).to be_nil
    end

    it 'sem argumentos não tem resumo' do
      expect(resumo({})).to be_nil
      expect(resumo(nil)).to be_nil
    end
  end
end
