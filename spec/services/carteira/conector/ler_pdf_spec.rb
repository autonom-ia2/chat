require 'rails_helper'

# #3175 — o PDF que a busca no conector guardou é lido UMA vez e completa só o que está vazio no seguro que já existe,
# sem criar outro, seguindo a chave da leitura de PDF da conta. O modelo é um dublê: nenhuma chamada paga sai daqui. O PDF
# é o fictício de spec/fixtures/carteira.
RSpec.describe Carteira::Conector::LerPdf, :aggregate_failures do
  let(:account) { conta_com_carteira }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo de Souza') }
  let(:leitura) { create(:carteira_leitura, account: account, origem: 'conector', estado: 'trazida', totais: { 'diaria' => 1 }) }
  let(:seguro) do
    criar_apolice(marina, tipo: 'outro', ramo_original: nil, seguradora: 'Seguradora Exemplo', numero: 'EX-2026.001234',
                          origem: 'conector', origem_ref: 'mock-ref-9', fim_vigencia: 1.year.from_now.to_date, leitura: leitura)
  end
  let(:sem_resposta) { Carteira::Leitor::Campos.schema[:schema][:required].index_with { nil } }
  let(:do_pdf) do
    { 'e_apolice' => true, 'tipo' => 'auto', 'ramo' => '0531 - Automóvel - Casco', 'seguradora' => 'SEGURADORA EXEMPLO S.A.',
      'numero' => 'EX-2026.001234', 'valor_centavos' => 225_498, 'bem' => 'Veículo Modelo Exemplo 1.0 Ano: 2024 Placa: EXM0A00',
      'segurado_telefone' => '(11) 99999-0001', 'segurado_telefone_pagina' => 1,
      'segurado_email' => 'marina.exemplo@exemplo.invalid', 'segurado_email_pagina' => 1,
      'segurado_nascimento' => '1985-03-15', 'segurado_sexo' => 'F', 'segurado_sexo_escrito' => 'Feminino', 'cep' => '12345-678',
      'placa' => 'EXM0A00', 'bonus_classe' => 5, 'bonus_trecho' => 'Classe de bônus: 5' }
  end
  let(:resposta) { do_pdf }

  before do
    allow(cliente).to receive(:create) { { text: sem_resposta.merge(resposta).to_json, usage: {} } }
    Carteira::Leitor::Liberado.ligar!(account)
    seguro.pdf.attach(io: File.open(Rails.root.join('spec/fixtures/carteira/apolice_auto.pdf')), filename: 'apolice-exemplo.pdf',
                      content_type: 'application/pdf')
    seguro.eventos.create!(tipo: 'pdf_anexado', quando: 1.minute.ago, valores: { leitura: leitura.id })
  end

  def ler(apolice = seguro)
    described_class.new(apolice.reload, leitura: leitura, cliente: cliente).call
  end

  def passo
    seguro.eventos.find_by!(tipo: 'pdf_lido')
  end

  it 'lê uma vez e completa só o que está vazio, no mesmo seguro, sem nome de pessoa no passo' do
    seguro.update!(bonus_classe: 2)

    expect { expect(ler).to be(true) }.not_to change(Carteira::Apolice, :count)

    expect(cliente).to have_received(:create).once
    expect(seguro.reload).to have_attributes(tipo: 'auto', ramo_original: '0531 - Automóvel - Casco', valor_centavos: 225_498,
                                             segurado_nascimento: '1985-03-15', segurado_sexo: 'F', cep: '12345678',
                                             placa: 'EXM0A00', bonus_classe: 2)
    expect(seguro.bem).to include('EXM0A00')
    expect(seguro).to have_attributes(seguradora: 'Seguradora Exemplo', numero: 'EX-2026.001234', origem: 'conector')
    expect(passo).to have_attributes(user_id: nil, valores: { 'leitura' => leitura.id, 'lido' => true })
    expect(passo.mudancas).to include({ 'campo' => 'valor', 'antes' => nil, 'depois' => 225_498 },
                                      { 'campo' => 'tipo', 'antes' => 'outro', 'depois' => 'auto' },
                                      { 'campo' => 'cep', 'antes_vazio' => true })
    expect(passo.mudancas.pluck('campo')).not_to include('bonus')
  end

  it 'nunca grava o telefone nem o e-mail do segurado, que só valem depois de alguém confirmar' do
    ler

    expect(marina.reload).to have_attributes(phone_number: nil, email: nil)
    expect(passo.attributes.to_json).not_to include('99999', 'marina.exemplo', '1985-03-15', '12345678')
  end

  it 'com a leitura de PDF desligada na conta: nada lido, nada cobrado, nada marcado, sem falhar' do
    Carteira::Leitor::Liberado.desligar!(account)

    expect(ler).to be(false)

    expect(cliente).not_to have_received(:create)
    expect(seguro.eventos.where(tipo: 'pdf_lido')).to be_empty
    expect(seguro.reload).to have_attributes(tipo: 'outro', valor_centavos: nil)
  end

  it 'o mesmo PDF não é lido duas vezes, nem quando o que ele trouxe foi apagado; o PDF novo é lido' do
    ler
    seguro.update!(valor_centavos: nil)

    expect(ler).to be(false)
    expect(cliente).to have_received(:create).once

    seguro.eventos.create!(tipo: 'pdf_anexado', quando: Time.current, valores: {})
    expect(ler).to be(true)
    expect(cliente).to have_received(:create).twice
  end

  it 'a leitura que falha não é tentada de novo: a marca entra antes de ler' do
    allow(cliente).to receive(:create).and_raise(Net::ReadTimeout)

    expect([ler, ler]).to eq([true, false])

    expect(cliente).to have_received(:create).once
    expect(passo).to have_attributes(mudancas: nil, valores: { 'leitura' => leitura.id, 'recusa' => 'nao_deu_para_ler' })
    expect(seguro.reload.valor_centavos).to be_nil
  end

  it 'um erro depois da marca diz que não deu para ler, nunca que não havia nada em branco' do
    allow_any_instance_of(Carteira::Pdf::Completar).to receive(:call).and_raise(ActiveRecord::RecordNotSaved) # rubocop:disable RSpec/AnyInstance

    expect(ler).to be(true)

    expect(passo).to have_attributes(mudancas: nil, valores: { 'leitura' => leitura.id, 'recusa' => 'nao_deu_para_ler' })
    expect(ler).to be(false)
  end

  it 'a cotação não relê o PDF que já foi lido na chegada' do
    ler
    seguro.update!(cep: nil)

    expect(Carteira::Conector::LerPdf.lido?(seguro)).to be(true)
    expect(Carteira::Cotacao::DadosDoPdf.new(seguro.reload, cliente: cliente).call(['address.zipCode'])).to be(false)
    expect(cliente).to have_received(:create).once
  end

  context 'quando o arquivo não é uma apólice' do
    let(:resposta) { { 'e_apolice' => false } }

    it 'o passo diz por quê, e nada muda' do
      ler

      expect(passo.valores).to include('recusa' => 'nao_e_apolice')
      expect(seguro.reload).to have_attributes(tipo: 'outro', valor_centavos: nil, bem: nil)
    end
  end

  it 'o que foi corrigido à mão e o que alguém escreveu enquanto o PDF era lido ficam' do
    seguro.update!(corrigido_a_mao: %w[valor])
    allow(cliente).to receive(:create) do
      Carteira::Apolice.where(id: seguro.id).update_all(bem: 'Escrito por alguém', cep: '01001000') # rubocop:disable Rails/SkipsModelValidations
      { text: sem_resposta.merge(do_pdf).to_json, usage: {} }
    end

    ler

    expect(seguro.reload).to have_attributes(valor_centavos: nil, bem: 'Escrito por alguém', cep: '01001000', tipo: 'auto')
  end

  it 'não lê quando nada está vazio, quando o seguro não tem PDF ou está cancelado' do
    seguro.update!(tipo: 'auto', ramo_original: 'Automóvel', valor_centavos: 100_000, bem: 'Carro', segurado_nascimento: '1990-01-01',
                   segurado_sexo: 'M', cep: '01001000', placa: 'ABC1D23', bonus_classe: 2)
    expect(ler).to be(false)

    seguro.update!(valor_centavos: nil, cancelado_em: Time.current)
    expect(ler).to be(false)

    seguro.update!(cancelado_em: nil)
    seguro.pdf.purge
    expect(ler).to be(false)

    expect(cliente).not_to have_received(:create)
    expect(seguro.eventos.where(tipo: 'pdf_lido')).to be_empty
  end

  it 'na empresa segurada, o nascimento e o sexo não são gravados' do
    seguro.update!(company: create(:company, account: account, name: 'Padaria Amostra Ltda.'))

    ler

    expect(seguro.reload).to have_attributes(segurado_nascimento: nil, segurado_sexo: nil, valor_centavos: 225_498)
  end
end
