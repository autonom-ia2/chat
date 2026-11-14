require 'rails_helper'

# E5 (#2898): onde ficam as renovações de uma conta. Uma linha por conta; o funil e a etapa são da própria conta. A
# escolha só vale com o funil ativo, e o funil arquivado ou apagado não se confunde com "ninguém escolheu".
RSpec.describe Carteira::RenovacaoConfig do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: user, name: 'Renovação') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }

  it 'nasce com 60 dias, mandando as mensagens e sem funil: a conta ainda não escolheu' do
    ajustes = described_class.create!(account: account)

    expect(ajustes.reload).to have_attributes(dias_antes: 60, mensagens: 'mandar', pipeline_id: nil, stage_id: nil, user_id: nil)
    expect([ajustes.escolhida?, ajustes.escolha]).to eq([false, 'nunca_feita'])
  end

  it 'guarda o funil, a etapa e quem escolheu' do
    ajustes = described_class.create!(account: account, pipeline: funil, stage: etapa, user: user, dias_antes: 45, mensagens: 'nao_mandar')

    expect(ajustes.reload).to have_attributes(pipeline_id: funil.id, stage_id: etapa.id, user_id: user.id, dias_antes: 45,
                                              mensagens: 'nao_mandar')
    expect([ajustes.escolhida?, ajustes.escolha]).to eq([true, 'feita'])
  end

  # Arquivar o funil só muda o status dele: a linha continua apontando para ele, mas a escolha deixa de valer.
  it 'o funil arquivado continua guardado e deixa de valer; restaurado, volta a valer sozinho' do
    ajustes = described_class.create!(account: account, pipeline: funil, stage: etapa, user: user)

    como_esta = -> { described_class.find(ajustes.id).then { |lida| [lida.pipeline_id, lida.escolhida?, lida.escolha] } }

    funil.update!(status: :archived)
    arquivado = como_esta.call
    funil.update!(status: :active)

    expect(arquivado).to eq([funil.id, false, 'funil_arquivado'])
    expect(como_esta.call).to eq([funil.id, true, 'feita'])
  end

  it 'é uma por conta: o model recusa a segunda e o índice único do banco também' do
    described_class.create!(account: account)
    segunda = described_class.new(account: account)

    expect(segunda).not_to be_valid
    expect { segunda.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.create!(account: create(:account))).to be_persisted
  end

  it 'recusa dias que não são inteiro de 1 a 3650 e mensagens fora da lista' do
    invalidos = [{ dias_antes: 0 }, { dias_antes: -5 }, { dias_antes: 1.5 }, { dias_antes: nil }, { dias_antes: 3651 },
                 { mensagens: 'talvez' }, { mensagens: nil }]

    expect(invalidos.map { |campos| described_class.new(account: account, **campos).valid? }).to all(be(false))
    expect([1, 60, 3650].map { |dias| described_class.new(account: account, dias_antes: dias).valid? }).to all(be(true))
  end

  it 'o banco recusa menos de um dia, mesmo sem passar pelo model' do
    linha = described_class.where(id: described_class.create!(account: account).id)
    pelo_check = lambda do |erro|
      expect([erro.cause.class.name, erro.cause.message.include?('carteira_renovacao_configs_dias')]).to eq(['PG::CheckViolation', true])
    end

    expect do
      described_class.transaction(requires_new: true) { linha.update_all(dias_antes: 0) } # rubocop:disable Rails/SkipsModelValidations
    end.to raise_error(ActiveRecord::StatementInvalid, &pelo_check)
  end

  it 'recusa o funil de outra conta, a etapa de outro funil e a etapa sem funil' do
    outra = create(:account)
    funil_de_fora, etapa_de_fora = create_crm_pipeline(account: outra, user: create(:user, account: outra), name: 'De fora')
    _outro_funil, etapa_de_outro_funil = create_crm_pipeline(account: account, user: user, name: 'Vendas')
    tentativas = [{ pipeline: funil_de_fora, stage: etapa_de_fora }, { pipeline: funil, stage: etapa_de_outro_funil }, { stage: etapa }]

    expect(tentativas.map { |campos| described_class.new(account: account, **campos).valid? }).to all(be(false))
    expect(described_class.new(account: account, pipeline: funil, stage: etapa)).to be_valid
  end

  it 'recusa quem escolheu quando a pessoa não é da conta' do
    de_fora = create(:user, account: create(:account))

    expect(described_class.new(account: account, user: de_fora)).not_to be_valid
    expect(described_class.new(account: account, user: user)).to be_valid
  end

  # A chave do banco anula a coluna sem passar pelo app. O que sobra diz que a escolha sumiu: o funil sem a etapa, ou
  # quem escolheu sem o funil.
  it 'apagar a etapa ou o funil deixa a conta sem escolha, a linha fica e dá para saber que a escolha sumiu' do
    ajustes = described_class.create!(account: account, pipeline: funil, stage: etapa, user: user)

    Crm::PipelineStage.where(id: etapa.id).delete_all
    expect(ajustes.reload).to have_attributes(stage_id: nil, pipeline_id: funil.id, escolhida?: false, escolha: 'sumiu')

    Crm::Pipeline.where(id: funil.id).delete_all
    expect(ajustes.reload).to have_attributes(pipeline_id: nil, stage_id: nil, user_id: user.id, escolhida?: false, escolha: 'sumiu')
  end

  it 'apagar também quem escolheu deixa a linha como a de quem nunca escolheu' do
    ajustes = described_class.create!(account: account, pipeline: funil, stage: etapa, user: user)

    Crm::PipelineStage.where(id: etapa.id).delete_all
    Crm::Pipeline.where(id: funil.id).delete_all
    User.where(id: user.id).delete_all

    expect(ajustes.reload).to have_attributes(pipeline_id: nil, stage_id: nil, user_id: nil, escolha: 'nunca_feita')
  end
end
