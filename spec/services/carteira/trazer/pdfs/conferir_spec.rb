require 'rails_helper'

# E6.3 (#2899) — o lote de "Trazer por PDFs" depois de lido: o Conferir, o que a pessoa muda nele, a gravação pelo
# gravador único e o Desfazer pela regra da planilha. Os itens já vêm lidos, como o Carteira::LerItem os deixa: nada
# aqui chama a IA. Tudo fictício.
RSpec.describe Carteira::Trazer::Pdfs::Conferir do
  let(:account) { conta_com_carteira }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:leitura) do
    create(:carteira_leitura, account: account, user: user, estado: 'lida', totais: { Carteira::Leitura::DO_TRAZER => 2 })
  end
  let(:completo) do
    { 'tipo' => 'auto', 'seguradora' => 'Seguradora Exemplo', 'numero' => 'EX-000777', 'fim_vigencia' => '2027-05-01',
      'segurado_nome' => 'Pessoa Nova Exemplo', 'segurado_documento' => '52998224725', 'segurado_telefone' => '11900000077' }
  end

  def item(campos, duvidas = [], posicao: 0, estado: 'lido')
    item = create(:carteira_leitura_item, leitura: leitura, posicao: posicao, estado: estado, campos: campos, duvidas: duvidas)
    item.pdf.attach(io: StringIO.new('%PDF-1.4 exemplo'), filename: "pdf-#{posicao + 1}.pdf", content_type: 'application/pdf', identify: false)
    item
  end

  def conferir
    described_class.new(leitura.reload).call
  end

  def trazer!
    Carteira::Trazer::Pdfs::Trazer.new(leitura).call
    Carteira::Trazer::Pdfs::Gravar.new(leitura.reload).call
    leitura.reload
  end

  describe 'o Conferir' do
    it 'diz o que falta, o que conferir e quantos entram, sem dar o telefone por certo' do
      item(completo, %w[segurado_telefone])
      item(completo.except('fim_vigencia').merge('numero' => 'EX-000778'), %w[fim_vigencia segurado_telefone], posicao: 1)

      resposta = conferir
      expect(resposta).to include(estado: 'lida', total: 2, seguros: 1, pessoas: 1, pessoasNovas: 1, precisam: 2, porTipo: { 'auto' => 1 })
      faltando = resposta[:itens].find { |vista| vista[:posicao] == 2 }
      expect(faltando[:faltam]).to eq(['termina'])
      expect(faltando[:confira]).to eq([{ campo: 'telefone', valor: '11900000077' }])
    end

    it 'mostra o PDF que não é apólice e o que não deu para ler' do
      item({}, [], estado: 'recusado')
      item({}, [], posicao: 1, estado: 'falhou')

      expect(conferir).to include(recusados: 1, naoDeuParaLer: 1, seguros: 0)
    end
  end

  describe Carteira::Trazer::Pdfs::MudarItem do
    it 'escreve o que faltou, confirma ou recusa o contato e deixa de fora' do
      faltando = item(completo.except('fim_vigencia'), %w[fim_vigencia segurado_telefone])

      described_class.new(faltando).call('campos' => { 'termina' => '2027-06-01' }, 'recusar' => ['telefone'])

      lido = Carteira::ItemLido.new(faltando.reload)
      expect(lido.certo('fim_vigencia')).to eq('2027-06-01')
      expect(lido.nao_achei?('segurado_telefone')).to be(true)

      described_class.new(faltando).call('fora' => true)
      expect(faltando.reload.estado).to eq('fora')
    end

    it 'recusa data antes do começo, tipo desconhecido e lote já trazido' do
      lido = item(completo.merge('inicio_vigencia' => '2026-05-01'))

      [[{ 'campos' => { 'termina' => '2026-01-01' } }, 'termina_antes'], [{ 'campos' => { 'tipo' => 'barco' } }, 'campo_invalido']]
        .each do |pedido, codigo|
          expect { described_class.new(lido).call(pedido) }
            .to raise_error(CustomExceptions::CarteiraRecusa) { |erro| expect(erro.codigo).to eq(codigo) }
        end
      leitura.update!(estado: 'trazida')
      expect { described_class.new(lido.reload).call('fora' => true) }
        .to raise_error(CustomExceptions::CarteiraRecusa) { |erro| expect(erro.codigo).to eq('leitura_fechada') }
    end
  end

  describe 'trazer' do
    it 'cria a pessoa e o seguro pelo gravador único, sem o telefone que ninguém confirmou' do
      item(completo, %w[segurado_telefone])

      expect(trazer!.estado).to eq('trazida')
      apolice = Carteira::Apolice.find_by!(account_id: account.id, numero: 'EX-000777')
      expect([apolice.origem, apolice.leitura_id, apolice.pdf.attached?]).to eq(['pdf', leitura.id, true])
      expect(apolice.contact.name).to eq('Pessoa Nova Exemplo')
      expect(apolice.contact.phone_number).to be_nil
      expect(Relacionamentos::Documentos.new(account).donos('52998224725')).to eq([apolice.contact])
      expect(leitura.totais).to include('seguros' => 1, 'pessoas' => 1, 'pessoas_novas' => 1)
    end

    it 'acha a pessoa da conta pelo documento e não cria outra; o mesmo segurado em dois PDFs vira uma pessoa' do
      existente = create(:contact, account: account, name: 'Pessoa Que Já Existe')
      Relacionamentos::Documentos.new(account).guardar(existente, '52998224725')
      item(completo)
      item(completo.merge('numero' => 'EX-000779', 'segurado_documento' => '11144477735'), posicao: 1)
      item(completo.merge('numero' => 'EX-000780', 'segurado_documento' => '11144477735'), posicao: 2)

      expect { trazer! }.to change(Contact, :count).by(1)
      expect(Carteira::Apolice.find_by!(numero: 'EX-000777').contact).to eq(existente)
      expect(Carteira::Apolice.where(numero: %w[EX-000779 EX-000780]).distinct.count(:contact_id)).to eq(1)
    end

    it 'recusa trazer enquanto lê e quando nada está pronto' do
      item(completo.except('tipo'), %w[tipo])

      expect { Carteira::Trazer::Pdfs::Trazer.new(leitura).call }
        .to raise_error(CustomExceptions::CarteiraRecusa) { |erro| expect(erro.codigo).to eq('nada_para_trazer') }
    end
  end

  describe Carteira::Trazer::Pdfs::Desfazer do
    it 'tira o seguro e a pessoa em que ninguém mexeu, e deixa o que alguém cuidou' do
      item(completo)
      item(completo.merge('numero' => 'EX-000781', 'segurado_documento' => '11144477735', 'segurado_nome' => 'Outra Pessoa'), posicao: 1)
      trazer!
      cuidado = Carteira::Apolice.find_by!(numero: 'EX-000781')
      cuidado.update!(corrigido_a_mao: ['bem'], bem: 'Carro')

      expect(described_class.new(leitura).previa).to include(saem: 1, ficam: 1, pessoasSaem: 1, pessoasFicam: 1)
      described_class.new(leitura, quem: user).pedir
      described_class.new(leitura.reload).call

      expect(Carteira::Apolice.exists?(numero: 'EX-000777')).to be(false)
      expect(Contact.exists?(name: 'Pessoa Nova Exemplo')).to be(false)
      expect(cuidado.reload).to be_persisted
      expect(Contact.exists?(cuidado.contact_id)).to be(true)
      expect(leitura.reload.estado).to eq('desfeita')
    end

    it 'devolve ao que era o seguro que o lote só completou, e tira o PDF que ele pôs' do
      pessoa = create(:contact, account: account, name: 'Pessoa Exemplo')
      Relacionamentos::Documentos.new(account).guardar(pessoa, '52998224725')
      antiga = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000777', fim_vigencia: Date.new(2027, 5, 1), bem: nil)
      item(completo.merge('bem' => 'Carro Exemplo'))
      trazer!
      expect(antiga.reload.bem).to eq('Carro Exemplo')

      described_class.new(leitura, quem: user).pedir
      described_class.new(leitura.reload).call

      antiga.reload
      expect([antiga.bem, antiga.origem, antiga.pdf.attached?]).to eq([nil, 'planilha', false])
      expect(Contact.exists?(pessoa.id)).to be(true)
    end
  end
end
