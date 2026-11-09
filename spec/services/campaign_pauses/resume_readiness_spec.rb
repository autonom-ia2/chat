require 'rails_helper'

# #2686: a campanha da automação com etiqueta excluída apagada não fica pronta para retomar (pararia de novo no
# disparo, CampanhaSemEtiquetas). Sem modelo, a conferência do modelo não pesa: só a exclusão decide.
RSpec.describe CampaignPauses::ResumeReadiness do
  let(:account) { create(:account) }
  let(:ja_comprou) { create(:label, account: account, title: 'ja_comprou') }

  def campanha(audiencia)
    build(:campaign, account: account, template_params: nil,
                     audience: [*Autonomia::Automacao::CampanhaSemEtiquetas.todos, *audiencia])
  end

  it 'não fica pronta enquanto uma etiqueta excluída continuar apagada' do
    audiencia = Autonomia::Automacao::CampanhaSemEtiquetas.audiencia([ja_comprou.id, 0])

    expect(described_class.new(account).ready?(campanha(audiencia))).to be(false)
  end

  it 'com as etiquetas excluídas existindo, segue a conferência de antes' do
    audiencia = Autonomia::Automacao::CampanhaSemEtiquetas.audiencia([ja_comprou.id])

    expect(described_class.new(account).ready?(campanha(audiencia))).to be(true)
  end
end
