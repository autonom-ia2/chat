require 'rails_helper'
require Rails.root.join('script/ferramentas_prontas/dados_reais').to_s

# #2858 — o script que grava o `dados` real das fontes para o spec de cobertura da vitrine. O repositório é público:
# toda fonte gravada precisa dizer como sai a pessoa física, e a fonte sem essa decisão não é gravada.
RSpec.describe DadosReaisDasProntas do
  it 'toda fonte dos pedidos tem a decisao de anonimizacao' do
    fontes = described_class::CASOS.map(&:first).uniq

    expect(fontes - described_class::ANONIMIZACAO.keys).to eq([])
  end

  it 'fonte sem a decisao: aborta, com o que fazer' do
    expect { described_class.anonimizar('fonte_nova', { 'nome' => 'Fulano' }) }
      .to raise_error(described_class::SemDecisao) { |erro| expect(erro.message).to include('fonte_nova', 'ANONIMIZACAO') }
  end

  it 'fonte sem pessoa fisica: o dado sai como veio' do
    dados = { 'cep' => '01001-000', 'logradouro' => 'Praça da Sé' }

    expect(described_class.anonimizar('cep', dados)).to eq(dados)
  end

  it 'CNPJ: numero, razao social e nome fantasia de exemplo (a do MEI traz o nome da pessoa); o resto fica' do
    dados = { 'cnpj' => '12.345.678/0001-90', 'razao_social' => '12.345.678 FULANA DE TAL', 'nome_fantasia' => 'FULANA DOCES',
              'situacao' => 'ATIVA', 'natureza_juridica' => 'Empresário (Individual)', 'cidade' => 'CAMPINAS' }

    expect(described_class.anonimizar('cnpj', dados)).to eq(
      'cnpj' => '11.222.333/0001-81', 'razao_social' => 'EMPRESA EXEMPLO LTDA', 'nome_fantasia' => 'EXEMPLO',
      'situacao' => 'ATIVA', 'natureza_juridica' => 'Empresário (Individual)', 'cidade' => 'CAMPINAS'
    )
  end

  it 'corretor: nome e registro de exemplo; situacao e ramos ficam' do
    dados = { 'total' => 2, 'corretores' => [{ 'nome' => 'FULANO CORRETOR', 'situacao' => 'Ativo', 'registro_susep' => '9', 'ramos' => ['Danos'] }] }

    expect(described_class.anonimizar('corretor_susep', dados)['corretores']).to eq(
      [{ 'nome' => 'CORRETORA EXEMPLO 1 LTDA', 'situacao' => 'Ativo', 'registro_susep' => '100000001', 'ramos' => ['Danos'] }]
    )
  end
end
