require 'rails_helper'

# Revisão do #2917 (testador, N22): a observação que vai dentro de `dados` passa pelo teto de `Resposta::MAX_TEXTO` (160)
# e, maior que ele, chega cortada ao modelo: o `NAO_E_O_DA_NOTA` da NCM (209 letras) perdia "e use a consulta buscar".
# Toda observação fixa das prontas que vai em `dados` cabe inteira, com os maiores valores de exemplo nos campos.
RSpec.describe 'As observações das prontas cabem no teto' do # rubocop:disable RSpec/DescribeClass
  let(:fontes) { Autonomia::FerramentasProntas::Fontes }

  def da_ncm
    ncm = fontes::Ncm
    { 'ncm.BUSQUE_O_GRUPO' => format(ncm::BUSQUE_O_GRUPO, grupo: '8517.62.6'), 'ncm.CONFIRA' => ncm::CONFIRA,
      'ncm.NAO_E_O_DA_NOTA (2)' => format(ncm::NAO_E_O_DA_NOTA, digitos: 2),
      'ncm.NAO_E_O_DA_NOTA (4)' => format(ncm::NAO_E_O_DA_NOTA, digitos: 4) }
  end

  def da_fipe
    fipe = fontes::Fipe
    { 'fipe.SEM_O_ANO' => format(fipe::SEM_O_ANO, ano: '32000'), 'fipe.FAIXA' => fipe::FAIXA,
      'fipe.UMA_DAS_VERSOES' => fipe::UMA_DAS_VERSOES, 'fipe.VERSOES' => fipe::VERSOES,
      'fipe.VERSOES_E_OUTRAS' => fipe::VERSOES_E_OUTRAS }
  end

  def das_compras
    compras = fontes::ComprasGoverno
    { 'compras.PARCIAL' => compras::PARCIAL, 'compras.PARCIAL_SEM_COMPRAS' => compras::PARCIAL_SEM_COMPRAS,
      'compras.SO_A_PRIMEIRA_PAGINA' => format(compras::SO_A_PRIMEIRA_PAGINA, total: 99_999, pagina: compras::POR_PAGINA) }
  end

  def das_outras
    { 'feriados.OBSERVACAO' => fontes::Feriados::OBSERVACAO,
      'localizacao.OBSERVACAO' => fontes::Localizacao::Sedes::OBSERVACAO,
      'hospitais.AMOSTRA' => format(fontes::Hospitais::AMOSTRA, lidos: 99_999),
      'produtos_seguradoras.SEM_O_RAMO' => fontes::ProdutosSeguradoras::OpenInsurance::SEM_O_RAMO,
      'chuva.ESTIMATIVA + HOJE_ABERTO' => [fontes::Chuva::ESTIMATIVA, fontes::Chuva::HOJE_ABERTO].join(' ') }
  end

  it 'cada observacao fixa que vai em dados cabe em Resposta::MAX_TEXTO' do
    textos = da_ncm.merge(da_fipe, das_compras, das_outras)
    grandes = textos.select { |_nome, texto| texto.length > Autonomia::FerramentasProntas::Resposta::MAX_TEXTO }

    expect(textos.size).to eq(17)
    expect(grandes.transform_values(&:length)).to eq({})
  end
end
