require 'rails_helper'

# E8.1 (#3043): na cotação da renovação, o PDF que já está no seguro é lido UMA vez por vigência para achar os dados do
# segurado que faltam. O modelo é um dublê: nenhuma chamada paga sai daqui. O PDF é o fictício de spec/fixtures/carteira.
RSpec.describe Carteira::Cotacao::DadosDoPdf do
  let(:account) { conta_com_carteira }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo de Souza') }
  let(:seguro) { criar_apolice(marina, tipo: 'auto', seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:faltam) { %w[quotation.bonusClass insured.document insured.birthDate insured.gender address.zipCode vehicle.plate] }
  let(:sem_resposta) { Carteira::Leitor::Campos.schema[:schema][:required].index_with { nil } }
  let(:do_pdf) do
    { 'e_apolice' => true, 'tipo' => 'auto', 'seguradora' => 'SEGURADORA EXEMPLO S.A.', 'numero' => 'EX-2026.001234',
      'segurado_nascimento' => '1985-03-15', 'segurado_sexo' => 'F', 'segurado_sexo_escrito' => 'Feminino', 'cep' => '12345-678',
      'placa' => 'EXM0A00', 'bonus_classe' => 5, 'bonus_trecho' => 'Classe de bônus: 5' }
  end
  let(:do_segurado) { Carteira::DadosDoSegurado::COLUNAS.map(&:to_s) }

  before do
    allow(cliente).to receive(:create).and_return({ text: sem_resposta.merge(do_pdf).to_json, usage: {} })
    Carteira::Leitor::Liberado.ligar!(account)
    seguro.pdf.attach(io: File.open(Rails.root.join('spec/fixtures/carteira/apolice_auto.pdf')), filename: 'apolice-exemplo.pdf',
                      content_type: 'application/pdf')
  end

  def ler(faltando = faltam)
    described_class.new(seguro.reload, cliente: cliente).call(faltando)
  end

  it 'lê o PDF uma vez e preenche só o que está vazio, sem tocar nas outras colunas do seguro' do
    seguro.update!(placa: 'ABC1D23')
    antes = seguro.reload.attributes.except(*do_segurado, 'updated_at')

    expect(ler).to be(true)

    expect(cliente).to have_received(:create).once
    expect(seguro.reload).to have_attributes(segurado_nascimento: '1985-03-15', segurado_sexo: 'F', cep: '12345678', placa: 'ABC1D23',
                                             bonus_classe: 5)
    expect(seguro.attributes.except(*do_segurado, 'updated_at')).to eq(antes)
    passo = seguro.eventos.sole
    expect(passo).to have_attributes(tipo: 'dados_lidos_pdf', valores: { 'vigencia' => seguro.fim_vigencia.iso8601 })
    expect(passo.attributes.to_json).not_to include('1985-03-15', '12345678', 'EXM0A00')
  end

  it 'com a leitura de PDF desligada na conta: nada lido, nada cobrado, nada marcado' do
    Carteira::Leitor::Liberado.desligar!(account)

    expect(ler).to be(false)

    expect(cliente).not_to have_received(:create)
    expect(seguro.eventos).to be_empty
  end

  it 'na mesma vigência não lê de novo, nem quando o que o PDF trouxe foi apagado depois' do
    ler
    seguro.update!(cep: nil)

    expect(ler).to be(false)
    expect(cliente).to have_received(:create).once
    expect(seguro.eventos.where(tipo: 'dados_lidos_pdf').count).to eq(1)
  end

  it 'a leitura que falha não é tentada de novo: a marca entra antes de ler' do
    allow(cliente).to receive(:create).and_raise(Net::ReadTimeout)

    expect([ler, ler]).to eq([true, false])
    expect(cliente).to have_received(:create).once
    expect(seguro.reload.attributes.slice(*do_segurado).values).to all(be_nil)
  end

  it 'nunca sobrescreve: o que alguém escreveu enquanto o PDF era lido fica' do
    allow(cliente).to receive(:create) do
      Carteira::Apolice.where(id: seguro.id).update_all(cep: '01001000', bonus_classe: 2) # rubocop:disable Rails/SkipsModelValidations
      { text: sem_resposta.merge(do_pdf).to_json, usage: {} }
    end

    ler

    expect(seguro.reload).to have_attributes(cep: '01001000', bonus_classe: 2, segurado_nascimento: '1985-03-15', placa: 'EXM0A00')
  end

  it 'não lê quando nada do que falta vem do PDF, quando a coluna já tem valor ou quando o seguro não tem PDF' do
    expect(ler(%w[insured.document quotation.previousInsurerCode])).to be(false)

    seguro.update!(segurado_nascimento: '1990-01-01', segurado_sexo: 'M', cep: '01001000', placa: 'ABC1D23', bonus_classe: 2)
    expect(ler).to be(false)

    seguro.update!(cep: nil)
    seguro.pdf.purge
    expect(ler).to be(false)

    expect(cliente).not_to have_received(:create)
    expect(seguro.eventos).to be_empty
  end

  it 'na empresa segurada, o nascimento e o sexo não contam e não são gravados' do
    seguro.update!(company: create(:company, account: account, name: 'Padaria Amostra Ltda.'))

    expect(ler(%w[insured.birthDate insured.gender])).to be(false)
    expect(ler).to be(true)

    expect(seguro.reload).to have_attributes(segurado_nascimento: nil, segurado_sexo: nil, cep: '12345678', bonus_classe: 5)
  end
end
