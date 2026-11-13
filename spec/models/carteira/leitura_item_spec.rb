require 'rails_helper'

# E6 (#2899): o que o banco e o model garantem de um arquivo de um lote de leitura. Dados fictícios.
RSpec.describe Carteira::LeituraItem do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:leitura) { create(:carteira_leitura, account: account) }
  let(:agora) { Time.zone.local(2026, 11, 13, 12) }

  def item(**campos)
    create(:carteira_leitura_item, leitura: leitura, **campos)
  end

  it 'nasce lendo, sem campos nem dúvidas, e aceita cada estado da lista' do
    expect(item).to have_attributes(estado: 'lendo', campos: {}, duvidas: [], contact_id: nil, apolice_id: nil)
    described_class::ESTADOS.each { |estado| expect(item(estado: estado)).to be_persisted }
  end

  it 'recusa estado fora da lista, posição negativa, campos que não são objeto e dúvidas que não são lista de nomes' do
    invalidos = [{ estado: 'inventado' }, { posicao: -1 }, { posicao: nil }, { campos: ['numero'] }, { duvidas: { 'numero' => true } },
                 { duvidas: [1] }]

    expect(invalidos.map { |campos| build(:carteira_leitura_item, leitura: leitura, **campos).valid? }).to all(be(false))
    expect(item(campos: { 'numero' => 'EX-001234' }, duvidas: %w[valor bem])).to be_persisted
  end

  it 'a posição não se repete no mesmo lote, pelo índice único do banco, e se repete em outro' do
    item(posicao: 0)

    expect { item(posicao: 0) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create(:carteira_leitura_item, leitura: create(:carteira_leitura, account: account), posicao: 0)).to be_persisted
  end

  it 'recusa a pessoa e a apólice de outra conta: o banco só confere que elas existem' do
    outra = create(:account)
    pessoa_de_fora = create(:contact, account: outra)
    da_pessoa_de_fora = build(:carteira_leitura_item, leitura: leitura, contact: pessoa_de_fora)
    da_apolice_de_fora = build(:carteira_leitura_item, leitura: leitura,
                                                       apolice: create(:carteira_apolice, account: outra, contact: pessoa_de_fora))

    expect([da_pessoa_de_fora, da_apolice_de_fora].map(&:valid?)).to eq([false, false])
    expect(da_pessoa_de_fora.errors.attribute_names + da_apolice_de_fora.errors.attribute_names).to eq(%i[contact apolice])
    expect(item(contact: contact, apolice: create(:carteira_apolice, account: account, contact: contact))).to be_persisted
  end

  it 'apagar a apólice deixa o item, sem ela' do
    seguro = create(:carteira_apolice, account: account, contact: contact)
    lido = item(contact: contact, apolice: seguro)

    seguro.delete

    expect(lido.reload).to have_attributes(apolice_id: nil, contact_id: contact.id)
  end

  it 'guarda o PDF, e apagar o item manda apagar o arquivo' do
    lido = item
    lido.pdf.attach(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'exemplo.pdf', content_type: 'application/pdf')

    expect(lido.reload.pdf).to be_attached
    expect { lido.destroy! }.to have_enqueued_job(ActiveStorage::PurgeJob)
  end

  it 'vencidos são os itens das leituras com a guarda vencida, e só eles' do
    prazo = Carteira::Leitura::DIAS_DE_GUARDA_DOS_ITENS.days
    velha = create(:carteira_leitura, account: account, estado: 'trazida', confirmada_em: agora - prazo - 1.hour)
    do_lote_velho = create(:carteira_leitura_item, leitura: velha)
    item

    expect(described_class.vencidos(agora)).to contain_exactly(do_lote_velho)
  end
end
