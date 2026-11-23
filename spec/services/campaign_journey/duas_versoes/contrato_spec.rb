require 'rails_helper'

# #3099: a tela promete o que o servidor faz. As regras das duas versões existem nos dois lados (duasVersoes.js e
# vencedora.js na tela; CampaignJourney::DuasVersoes no servidor) e precisam ser as mesmas.
RSpec.describe 'Duas versões: regras da tela e do servidor (#3099)', :aggregate_failures do
  let(:regras) { Rails.root.join('app/javascript/dashboard/components-next/CampaignJourney/duasVersoes.js').read }
  let(:vencedora) { Rails.root.join('app/javascript/dashboard/components-next/CampaignResult/vencedora.js').read }
  let(:regua) { Rails.root.join('app/javascript/dashboard/components-next/CampaignResult/comparacaoComControle.js').read }

  it 'usa as mesmas constantes do plano do teste' do
    servidor = CampaignJourney::DuasVersoes
    criterios = servidor::CRITERIOS.map { |criterio| "'#{criterio}'" }.join(', ')
    expect(regras).to include("export const CRITERIOS = [#{criterios}];")
    expect(regras).to include("export const DIVISOES = [#{servidor::DIVISOES.join(', ')}];")
    expect(regras).to include("export const ESPERAS = [#{servidor::ESPERAS.join(', ')}];")
    expect(regras).to include("export const MINIMO_POR_VERSAO = #{servidor::MINIMO_POR_VERSAO};")
    expect(regras).to include("export const PARTE_DO_TESTE = #{servidor::PARTE_DO_TESTE};")
    expect(regras).to include("export const MINIMO_NO_RESTO = #{servidor::MINIMO_NO_RESTO};")
    padroes = servidor::ESPERA_POR_CRITERIO.map { |criterio, horas| "#{criterio}: #{horas}" }.join(', ')
    expect(regras).to include("const ESPERA_POR_CRITERIO = { #{padroes} };")
  end

  it 'usa a mesma régua para dizer qual versão foi melhor' do
    servidor = CampaignJourney::DuasVersoes::Vencedora
    expect(vencedora).to include("export const MINIMO_DE_RESULTADOS = #{servidor::MINIMO_DE_RESULTADOS};")
    expect(regua).to include("const QUASE_IGUAL = #{servidor::QUASE_IGUAL};")
  end
end
