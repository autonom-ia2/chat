require 'rails_helper'

# E6.2 (#2899) — "o que mudou" do PDF anexado, e o gravador do anexar. Decisões D1, D2 e D3. Nada aqui chama a IA: o
# item já vem lido, como o Carteira::LerItem o deixa. Tudo fictício.
RSpec.describe Carteira::Pdf::OQueMudou do
  let(:account) { conta_com_carteira }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pessoa) { create(:contact, account: account, name: 'Pessoa Exemplo') }
  let(:apolice) do
    criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000111', tipo: 'auto', inicio_vigencia: Date.new(2026, 1, 1),
                          fim_vigencia: Date.new(2027, 1, 1), valor_centavos: 100_000, bem: 'Carro Exemplo')
  end
  let(:leitura) do
    create(:carteira_leitura, account: account, estado: 'lida', totais: { Carteira::Leitura::DO_ANEXAR => 1 })
  end

  def item_lido(campos, duvidas = [])
    item = create(:carteira_leitura_item, leitura: leitura, posicao: 0, estado: 'lido', apolice: apolice, contact: pessoa,
                                          campos: campos, duvidas: duvidas)
    item.pdf.attach(io: StringIO.new('%PDF-1.4 exemplo'), filename: 'pdf-1.pdf', content_type: 'application/pdf', identify: false)
    item
  end

  def mudancas(item)
    described_class.new(apolice, item).call
  end

  def linha(resposta, campo)
    resposta[:mudancas].find { |mudanca| mudanca[:campo] == campo }
  end

  it 'nunca faz do "não achei" uma mudança (D1)' do
    item = item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111' }, %w[fim_vigencia bem valor_centavos])

    expect(mudancas(item)).to eq(outraApolice: false, mudancas: [])
    expect(described_class.new(apolice, item).valores).to eq({})
  end

  it 'marca o campo a confirmar e nunca o traz escolhido (D1)' do
    item = item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111', 'valor_centavos' => 250_000 }, %w[valor_centavos])

    expect(linha(mudancas(item), 'valor')).to include(antes: 1000.0, noPdf: 2500.0, confira: true, usar: false)
  end

  it 'traz escolhida a mudança certa e deixa de fora o campo corrigido à mão (D3)' do
    apolice.update!(corrigido_a_mao: ['bem'])
    item = item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111', 'fim_vigencia' => '2027-02-01', 'bem' => 'Moto' })

    resposta = mudancas(item)
    expect(linha(resposta, 'termina')).to include(antes: '2027-01-01', noPdf: '2027-02-01', usar: true, corrigidoAMao: false)
    expect(linha(resposta, 'bem')).to include(usar: false, corrigidoAMao: true)
  end

  it 'avisa que pode ser outra apólice e não escolhe nada quando o número é outro (D2)' do
    item = item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-999999', 'fim_vigencia' => '2027-02-01' })

    resposta = mudancas(item)
    expect(resposta[:outraApolice]).to be(true)
    expect(resposta[:mudancas].pluck(:usar)).to all(be(false))
    expect(resposta[:mudancas].pluck(:campo)).to include('numero', 'termina')
  end

  describe Carteira::Pdf::Aceitar do
    it 'grava só os campos escolhidos, passa o PDF e mantém o corrigido à mão protegido (D3)' do
      apolice.update!(corrigido_a_mao: ['bem'])
      item = item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111', 'fim_vigencia' => '2027-02-01', 'bem' => 'Moto',
                         'valor_centavos' => 250_000 }, %w[valor_centavos])

      described_class.new(apolice, user: user).call(leitura.id, %w[bem])

      apolice.reload
      expect([apolice.bem, apolice.fim_vigencia, apolice.valor_centavos]).to eq(['Moto', Date.new(2027, 1, 1), 100_000])
      expect(apolice.corrigido_a_mao).to eq(['bem'])
      expect(apolice.pdf).to be_attached
      expect(apolice.eventos.order(:id).pluck(:tipo)).to eq(%w[chegou_de_novo_pdf pdf_anexado])
      expect(Carteira::Leitura.exists?(leitura.id)).to be(false)
      expect(item.class.exists?(item.id)).to be(false)
    end

    it '"Manter como está" guarda só o PDF' do
      item_lido({ 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000111', 'fim_vigencia' => '2027-02-01' })

      described_class.new(apolice, user: user).call(leitura.id, [])

      expect(apolice.reload.fim_vigencia).to eq(Date.new(2027, 1, 1))
      expect(apolice.eventos.order(:id).pluck(:tipo)).to eq(%w[pdf_anexado])
    end

    it 'recusa campo que não é da gaveta e leitura de outro seguro' do
      item_lido({ 'seguradora' => 'Seguradora Exemplo' })
      outro = criar_apolice(pessoa, numero: 'EX-000222')

      expect { described_class.new(apolice, user: user).call(leitura.id, %w[origem]) }
        .to raise_error(CustomExceptions::CarteiraRecusa) { |erro| expect(erro.codigo).to eq('pedido_invalido') }
      expect { described_class.new(outro, user: user).call(leitura.id, []) }
        .to raise_error(CustomExceptions::CarteiraRecusa) { |erro| expect(erro.codigo).to eq('leitura_expirou') }
    end
  end
end
