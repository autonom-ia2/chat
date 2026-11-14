require 'rails_helper'

# #2896 — o arquivo das linhas com problema de "Trazer minha lista": um anexo pequeno, gravado na leitura da planilha, só
# com as linhas que precisam da pessoa (o número da linha e as células de nome, telefone, e-mail e empresa, como vieram).
# A tela lê dele e não abre mais a planilha original. Só existe na importação com a marca options['trazer'], é trocado a
# cada leitura e some no prazo da planilha original, contado da criação da importação
# (CampaignImports::Config.original_file_retention).
RSpec.describe ContactImports::Trazer::LinhasComProblema, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:planilha) do
    <<~CSV
      Nome;Celular;E-mail
      Ana Albuquerino;11987650001;ana.albuquerino@exemplo.com.br
      Bruno Brandolim;123;
      Carla Carvalhedo;;carla.exemplo.com.br
      Ana Repetida;11987650001;
    CSV
  end

  def importacao(texto = planilha, trazer: {})
    campaign_import = create_contact_import(account: account, user: user, content: texto)
    campaign_import.update!(options: campaign_import.options.merge('trazer' => trazer)) if trazer
    campaign_import
  end

  def ler_planilha(campaign_import)
    ContactImports::Validator.new(campaign_import).perform
    campaign_import.reload
  end

  def gravadas(campaign_import)
    campaign_import.linhas_com_problema.download.force_encoding(Encoding::UTF_8).lines.map { |linha| JSON.parse(linha) }
  end

  def celulas(nome, telefone, email, empresa = '')
    { 'name' => nome, 'phone' => telefone, 'email' => email, 'company' => empresa }
  end

  it 'guarda só as linhas com problema, com o número e as células dos alvos como vieram, e a outra linha da repetida' do
    campaign_import = ler_planilha(importacao)

    expect(campaign_import.linhas_com_problema).to be_attached
    expect(gravadas(campaign_import)).to eq(
      [
        { 'linha' => 3, 'celulas' => celulas('Bruno Brandolim', '123', '') },
        { 'linha' => 4, 'celulas' => celulas('Carla Carvalhedo', '', 'carla.exemplo.com.br') },
        { 'linha' => 5, 'celulas' => celulas('Ana Repetida', '11987650001', ''),
          'outra' => { 'linha' => 2, 'celulas' => celulas('Ana Albuquerino', '11987650001', 'ana.albuquerino@exemplo.com.br') } }
      ]
    )
  end

  it 'não guarda a célula de nenhuma outra coluna: nem a que vira informação, nem a marcada "não guardar"' do
    planilha = "Nome;Celular;Plano;Segredo;Empresa\nBruno Brandolim;123;Ouro;senha-do-bruno;Padaria\nAna Albuquerino;11987650001;;;\n"
    campaign_import = ler_planilha(importacao(planilha, trazer: { 'destinos' => { '3' => 'nao_guardar' } }))

    expect(gravadas(campaign_import)).to eq([{ 'linha' => 2, 'celulas' => celulas('Bruno Brandolim', '123', '', 'Padaria') }])
    expect(campaign_import.linhas_com_problema.download.force_encoding(Encoding::UTF_8)).not_to include('senha-do-bruno', 'Ouro')
  end

  it 'não guarda nada na importação sem a marca (a tela antiga e a automação)' do
    campaign_import = importacao(trazer: nil)
    validate_contact_import(campaign_import, { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => nil })

    expect(campaign_import).to be_ready_to_confirm
    expect(campaign_import.invalid_rows).to eq(3)
    expect(campaign_import.linhas_com_problema).not_to be_attached
  end

  it 'troca o arquivo a cada leitura: nada de linha de uma escolha de colunas antiga' do
    campaign_import = ler_planilha(importacao)
    antigo = campaign_import.linhas_com_problema.blob

    # O e-mail deixa de ser lido: a linha 4 fica sem contato nenhum e as outras seguem como estavam.
    campaign_import.update!(schema_resolution: campaign_import.schema_resolution.merge(
      'manual_mapping' => { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil }
    ))
    ler_planilha(campaign_import)

    expect(campaign_import.linhas_com_problema.blob).not_to eq(antigo)
    expect(gravadas(campaign_import).pluck('linha')).to eq([3, 4, 5])
    expect(campaign_import.campaign_import_rows.find_by!(row_number: 4).error_messages).to eq(['missing_contact'])
  end

  it 'fica sem arquivo quando a leitura nova não tem linha com problema' do
    campaign_import = ler_planilha(importacao)
    expect(campaign_import.linhas_com_problema).to be_attached

    campaign_import.original_file.attach(io: StringIO.new("Nome;Celular\nAna Albuquerino;11987650001\n"), filename: 'contatos.csv',
                                         content_type: 'text/csv')
    campaign_import.update!(schema_resolution: {})
    ler_planilha(campaign_import)

    expect(campaign_import).to have_attributes(status: 'ready_to_confirm', invalid_rows: 0)
    expect(campaign_import.linhas_com_problema).not_to be_attached
  end

  it 'some com o prazo da planilha original, apagado pelo mesmo job' do
    campaign_import = ler_planilha(importacao)
    prazo = CampaignImports::Config.original_file_retention

    travel_to((prazo - 1.hour).from_now) { perform_enqueued_jobs { CampaignImports::PurgeExpiredFilesJob.perform_now } }
    expect(campaign_import.reload.linhas_com_problema).to be_attached

    travel_to((prazo + 1.hour).from_now) { perform_enqueued_jobs { CampaignImports::PurgeExpiredFilesJob.perform_now } }
    expect(campaign_import.reload.linhas_com_problema).not_to be_attached
    expect(campaign_import.original_file).not_to be_attached
    expect(campaign_import.normalized_csv).to be_attached
  end

  it 'o prazo conta da criação da importação: ler de novo e consertar não o recomeçam' do
    campaign_import = ler_planilha(importacao)
    prazo = CampaignImports::Config.original_file_retention

    # No sexto dia a planilha é lida de novo e uma linha é consertada: os dois anexos nascem de novo.
    travel_to((prazo - 1.day).from_now) do
      ler_planilha(campaign_import)
      Relacionamentos::Trazer::MudarLinha.new(campaign_import, 3).consertar(valor: '11987650003')
    end
    expect(campaign_import.reload.linhas_com_problema.attachment.created_at).to be > 5.days.from_now
    expect(campaign_import.consertos).to be_attached

    travel_to((prazo + 1.hour).from_now) { perform_enqueued_jobs { CampaignImports::PurgeExpiredFilesJob.perform_now } }
    expect(campaign_import.reload.linhas_com_problema).not_to be_attached
    expect(campaign_import.consertos).not_to be_attached
    expect(campaign_import.normalized_csv).to be_attached
  end

  it 'não apaga os anexos de uma importação mais nova que o prazo' do
    campaign_import = ler_planilha(importacao)
    Relacionamentos::Trazer::MudarLinha.new(campaign_import, 3).consertar(valor: '11987650003')

    travel_to(1.day.from_now) { perform_enqueued_jobs { CampaignImports::PurgeExpiredFilesJob.perform_now } }

    expect(campaign_import.reload.linhas_com_problema).to be_attached
    expect(campaign_import.consertos).to be_attached
  end

  it 'some junto com a importação' do
    campaign_import = ler_planilha(importacao)
    anexo = campaign_import.linhas_com_problema.attachment

    campaign_import.destroy!

    expect(ActiveStorage::Attachment.where(id: anexo.id)).to be_empty
  end

  describe '#ler' do
    it 'devolve só as linhas pedidas e para de ler quando achou todas' do
      campaign_import = ler_planilha(importacao)
      terceira = { 'linha' => 3, 'celulas' => celulas('Bruno Brandolim', '123', '') }

      expect(described_class.new(campaign_import).ler([3, 99])).to eq(3 => terceira)

      # Depois da linha pedida o arquivo tem um trecho que não dá para ler: quem lesse o arquivo inteiro quebraria.
      campaign_import.linhas_com_problema.attach(io: StringIO.new("#{JSON.generate(terceira)}\n{isto não é JSON\n"),
                                                 filename: 'linhas_com_problema.jsonl', content_type: 'application/x-ndjson')
      expect(described_class.new(campaign_import).ler([3])).to eq(3 => terceira)
      # B4: o erro não leva nada do conteúdo do arquivo, nem na mensagem nem na causa.
      expect { described_class.new(campaign_import).ler([3, 4]) }.to raise_error(ContactImports::Trazer::ArquivoIlegivel) do |erro|
        expect(erro.message).not_to include('isto')
        expect(erro.cause).to be_nil
      end
    end

    it 'guarda o que já leu: pedir de novo a mesma linha não abre o arquivo outra vez' do
      campaign_import = ler_planilha(importacao)
      arquivo = described_class.new(campaign_import)
      allow(ActiveStorage::Blob.service).to receive(:download).and_call_original

      2.times { expect(arquivo.ler([3]).keys).to eq([3]) }
      expect(arquivo.ler([99])).to eq({})
      expect(arquivo.ler([99])).to eq({})

      expect(ActiveStorage::Blob.service).to have_received(:download).twice
    end

    it 'não abre arquivo nenhum quando nada é pedido ou o arquivo já foi apagado' do
      campaign_import = ler_planilha(importacao)
      arquivo = described_class.new(campaign_import)
      allow(campaign_import.linhas_com_problema.blob).to receive(:open).and_call_original

      expect(arquivo.ler([])).to eq({})
      expect(campaign_import.linhas_com_problema.blob).not_to have_received(:open)

      campaign_import.linhas_com_problema.purge
      expect(described_class.new(campaign_import.reload)).not_to be_existe
      expect(described_class.new(campaign_import).ler([3])).to eq({})
    end
  end
end
