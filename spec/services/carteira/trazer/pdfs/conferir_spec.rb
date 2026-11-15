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

    it 'com CPF lido que ninguém tem, o telefone igual ao de um cliente não casa: nasce outra pessoa, e o telefone fica com o dono' do
      numero = Crm::BookingV2::PhoneLookup.normalize('11900000077')
      dono = create(:contact, account: account, name: 'Dono Do Telefone', phone_number: numero)
      item(completo)

      expect { trazer! }.to change(Contact, :count).by(1)
      pessoa = Carteira::Apolice.find_by!(account_id: account.id, numero: 'EX-000777').contact
      expect([pessoa == dono, pessoa.phone_number, dono.reload.phone_number]).to eq([false, nil, numero])
    end

    it 'sem CPF lido, o telefone que a pessoa confirmou casa com o cliente da conta' do
      dono = create(:contact, account: account, name: 'Dono Do Telefone', phone_number: Crm::BookingV2::PhoneLookup.normalize('11900000077'))
      item(completo.except('segurado_documento'))

      expect { trazer! }.not_to change(Contact, :count)
      expect(Carteira::Apolice.find_by!(account_id: account.id, numero: 'EX-000777').contact).to eq(dono)
    end

    it 'dois PDFs sem documento e com o mesmo nome são duas pessoas' do
      sem_documento = completo.except('segurado_documento', 'segurado_telefone')
      item(sem_documento)
      item(sem_documento.merge('numero' => 'EX-000779'), posicao: 1)

      expect(conferir).to include(seguros: 2, pessoas: 2, pessoasNovas: 2)
      expect { trazer! }.to change(Contact, :count).by(2)
    end

    it 'falha inesperada de um PDF: só ele não entra, o lote termina e o registro leva só a classe e o id' do
      item(completo)
      item(completo.merge('numero' => 'EX-000779', 'segurado_documento' => '11144477735', 'segurado_telefone' => '11900000078'), posicao: 1)
      chamadas = 0
      allow(Carteira::Guardar).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        gravador = original.call(*args, **kwargs)
        chamadas += 1
        allow(gravador).to receive(:call).and_raise(IOError, 'texto do cliente') if chamadas == 1
        gravador
      end
      allow(Rails.logger).to receive(:warn)

      expect(trazer!.estado).to eq('trazida')
      expect(leitura.itens.order(:posicao).pluck(:estado)).to eq(%w[nao_entrou trazido])
      expect(leitura.totais).to include('seguros' => 1, 'nao_entraram' => 1, 'motivo_falha' => 1)
      expect(Rails.logger).to have_received(:warn).with(a_string_including('IOError'))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('texto do cliente'))
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
      item(completo.merge('numero' => 'EX-000781', 'segurado_documento' => '11144477735', 'segurado_nome' => 'Outra Pessoa',
                          'segurado_telefone' => '11900000078'), posicao: 1)
      trazer!
      cuidado = Carteira::Apolice.find_by!(numero: 'EX-000781')
      cuidado.update!(corrigido_a_mao: ['bem'], bem: 'Carro')

      expect(described_class.new(leitura).previa).to include(saem: 1, ficam: 1, pessoasSaem: 1, pessoasFicam: 1)
      described_class.new(leitura, quem: user).pedir
      expect { described_class.new(leitura.reload).call }.to have_enqueued_job(ActiveStorage::PurgeJob)

      expect(Carteira::Apolice.exists?(numero: 'EX-000777')).to be(false)
      expect(Contact.exists?(name: 'Pessoa Nova Exemplo')).to be(false)
      expect(cuidado.reload).to be_persisted
      expect(Contact.exists?(cuidado.contact_id)).to be(true)
      expect(leitura.reload.estado).to eq('desfeita')
    end

    it 'deixa o seguro que o lote criou e que uma lista de planilha trouxe de novo depois, e a pessoa dele' do
      item(completo)
      trazer!
      apolice = Carteira::Apolice.find_by!(numero: 'EX-000777')
      apolice.eventos.create!(tipo: 'chegou_de_novo', quando: Time.current, user: user, valores: { arquivo: 'carteira-exemplo.csv' },
                              mudancas: [{ 'campo' => 'bem', 'antes' => nil, 'depois' => 'Carro Exemplo 2024' }])

      expect(described_class.new(leitura).previa).to include(saem: 0, ficam: 1, pessoasSaem: 0, pessoasFicam: 1)
    end

    it 'não volta o seguro que o lote completou e que uma lista de planilha mudou depois' do
      pessoa = create(:contact, account: account, name: 'Pessoa Exemplo')
      Relacionamentos::Documentos.new(account).guardar(pessoa, '52998224725')
      antiga = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000777', fim_vigencia: Date.new(2027, 5, 1), bem: nil)
      item(completo.merge('bem' => 'Carro Exemplo'))
      trazer!
      antiga.reload.eventos.create!(tipo: 'chegou_de_novo', quando: Time.current, user: user, valores: { arquivo: 'carteira-exemplo.csv' },
                                    mudancas: [{ 'campo' => 'valor', 'antes' => nil, 'depois' => 100 }])

      expect(described_class.new(leitura).previa).to include(saem: 0, voltam: 0)
    end

    it 'devolve ao que era o seguro que o lote só completou, e tira o PDF que ele pôs' do
      pessoa = create(:contact, account: account, name: 'Pessoa Exemplo')
      Relacionamentos::Documentos.new(account).guardar(pessoa, '52998224725')
      antiga = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000777', fim_vigencia: Date.new(2027, 5, 1), bem: nil)
      item(completo.merge('bem' => 'Carro Exemplo'))
      trazer!
      expect(antiga.reload.bem).to eq('Carro Exemplo')

      described_class.new(leitura, quem: user).pedir
      expect { described_class.new(leitura.reload).call }.to have_enqueued_job(ActiveStorage::PurgeJob)

      antiga.reload
      expect([antiga.bem, antiga.origem, antiga.pdf.attached?]).to eq([nil, 'planilha', false])
      expect(Contact.exists?(pessoa.id)).to be(true)
    end
  end
end
