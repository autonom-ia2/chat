require 'rails_helper'

# E6 (#2899): o que o banco e o model garantem de um lote de leitura da carteira. Dados fictícios.
RSpec.describe Carteira::Leitura do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:agora) { Time.zone.local(2026, 11, 13, 12) }

  def leitura(**campos)
    create(:carteira_leitura, account: account, **campos)
  end

  it 'nasce lendo, sem totais, e aceita cada origem e estado da lista' do
    expect(leitura).to have_attributes(estado: 'lendo', totais: {}, confirmada_em: nil, desfeita_em: nil)
    described_class::ORIGENS.each { |origem| expect(leitura(origem: origem)).to be_persisted }
    described_class::ESTADOS.each { |estado| expect(leitura(estado: estado)).to be_persisted }
  end

  it 'o model recusa origem e estado fora da lista, e o banco recusa a origem mesmo sem o model' do
    invalidas = [{ origem: 'planilha' }, { estado: 'inventado' }]
    linha = described_class.where(id: leitura.id)
    gravar = -> { described_class.transaction(requires_new: true) { linha.update_all(origem: 'planilha') } } # rubocop:disable Rails/SkipsModelValidations
    pelo_check = lambda do |erro|
      expect([erro.cause.class.name, erro.cause.message.include?('carteira_leituras_origem')]).to eq(['PG::CheckViolation', true])
    end

    expect(invalidas.map { |campos| build(:carteira_leitura, account: account, **campos).valid? }).to all(be(false))
    expect { gravar.call }.to raise_error(ActiveRecord::StatementInvalid, &pelo_check)
  end

  it 'os totais só guardam contagens: texto, lista ou objeto dentro deles não passam' do
    com_texto = { 'lidos' => 2, 'segurado' => 'Pessoa Exemplo' }
    validas = [{ 'lidos' => 3, 'recusados' => 1 }, com_texto, { 'itens' => [1, 2] }, { 'por_tipo' => { 'auto' => 1 } }, ['lidos']]

    expect(validas.map { |totais| build(:carteira_leitura, account: account, totais: totais).valid? }).to eq([true, false, false, false, false])
  end

  it 'a guarda dos itens vence dias depois de confirmar; sem confirmar, dias depois da última vez em que foi mexida' do
    prazo = described_class::DIAS_DE_GUARDA_DOS_ITENS.days
    confirmada_velha = leitura(estado: 'trazida', confirmada_em: agora - prazo - 1.hour)
    confirmada_nova = leitura(estado: 'trazida', confirmada_em: agora - prazo + 1.hour)
    abandonada = leitura
    recente = leitura
    # A confirmada há muito tempo vence mesmo mexida ontem; a abandonada conta da última mexida.
    described_class.where(id: [confirmada_velha.id, confirmada_nova.id, recente.id]).update_all(updated_at: agora - 1.day) # rubocop:disable Rails/SkipsModelValidations
    described_class.where(id: abandonada.id).update_all(updated_at: agora - prazo - 1.hour) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.com_a_guarda_vencida(agora)).to contain_exactly(confirmada_velha, abandonada)
  end

  it 'apagar a leitura leva os itens com o PDF e deixa a apólice, sem o lote' do
    lote = leitura
    item = create(:carteira_leitura_item, leitura: lote)
    item.pdf.attach(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'exemplo.pdf', content_type: 'application/pdf')
    seguro = create(:carteira_apolice, account: account, contact: contact, leitura: lote, origem: 'pdf')

    expect { lote.destroy! }.to have_enqueued_job(ActiveStorage::PurgeJob)

    expect(Carteira::LeituraItem.where(id: item.id)).to be_empty
    expect(ActiveStorage::Attachment.where(record_type: 'Carteira::LeituraItem', record_id: item.id)).to be_empty
    expect(seguro.reload).to have_attributes(leitura_id: nil, contact_id: contact.id)
  end

  it 'recusa quem enviou quando a pessoa não é da conta: o banco só confere que ela existe' do
    de_fora = build(:carteira_leitura, account: account, user: create(:user, account: create(:account)))

    expect([de_fora.valid?, de_fora.errors.attribute_names]).to eq([false, [:user]])
    expect(leitura(user: create(:user, account: account))).to be_persisted
  end

  it 'apagar a pessoa que enviou deixa o lote, sem ela' do
    pessoa = create(:user, account: account)
    lote = leitura(user: pessoa)

    User.where(id: pessoa.id).delete_all

    expect(lote.reload.user_id).to be_nil
  end

  describe 'o que a apólice ganha' do
    it 'nasce sem lote, sem dúvidas e não é de fora' do
      seguro = create(:carteira_apolice, account: account, contact: contact)

      expect(seguro).to have_attributes(leitura_id: nil, duvidas: [], de_fora: false, corretora_de_fora: nil, lembrete_aceito_em: nil,
                                        palavras_texto: nil, palavras_enviadas_em: nil)
    end

    it 'recusa a leitura de outra conta: o banco só confere que ela existe' do
      de_fora = build(:carteira_apolice, account: account, contact: contact, leitura: create(:carteira_leitura))

      expect([de_fora.valid?, de_fora.errors.attribute_names]).to eq([false, [:leitura]])
      expect(build(:carteira_apolice, account: account, contact: contact, leitura: leitura)).to be_valid
    end
  end
end
