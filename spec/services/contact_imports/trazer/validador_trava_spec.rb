require 'rails_helper'

# #2896 — a leitura da planilha de "Trazer minha lista" não aguenta duas execuções sem trava: a leitura velha que
# termina depois apagaria as linhas e voltaria o estado da nova, até no meio da gravação. Só a importação com a marca
# options['trazer'] tem a trava; sem a marca a leitura segue como sempre (validator_import_spec.rb).
RSpec.describe ContactImports::Trazer::Validador, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:planilha) { "Nome,Celular\nAna Albuquerino,11987650001\nBruno Brandolim,11987650002\n" }

  def importacao
    campaign_import = create_contact_import(account: account, user: user, content: planilha)
    campaign_import.update!(options: campaign_import.options.merge('trazer' => {}))
    campaign_import
  end

  def ler(campaign_import)
    ContactImports::Validator.new(campaign_import).perform
  end

  # Faz uma leitura mais nova começar e terminar no meio da leitura velha: quando a velha vai abrir a planilha.
  def com_outra_leitura_no_meio(campaign_import, a_velha_quebra: false)
    vezes = 0
    allow(CampaignImports::Parser).to receive(:new).and_wrap_original do |original, *argumentos, **opcoes|
      vezes += 1
      if vezes == 1
        ler(CampaignImport.find(campaign_import.id))
        yield
        raise IOError if a_velha_quebra
      end
      original.call(*argumentos, **opcoes)
    end
  end

  it 'a leitura velha que termina depois da nova não toca em nada' do
    campaign_import = importacao
    linhas_da_nova = nil
    com_outra_leitura_no_meio(campaign_import) { linhas_da_nova = campaign_import.campaign_import_rows.order(:id).pluck(:id, :updated_at) }

    ler(campaign_import)

    expect(linhas_da_nova.size).to eq(2)
    expect(campaign_import.campaign_import_rows.order(:id).pluck(:id, :updated_at)).to eq(linhas_da_nova)
    expect(campaign_import.reload).to have_attributes(status: 'ready_to_confirm', valid_rows: 2)
    expect(campaign_import.options['trazer']).to eq({})
  end

  it 'a leitura velha que quebra depois da nova também não toca em nada' do
    campaign_import = importacao
    linhas_da_nova = nil
    com_outra_leitura_no_meio(campaign_import, a_velha_quebra: true) { linhas_da_nova = campaign_import.campaign_import_rows.order(:id).pluck(:id) }

    ler(campaign_import)

    expect(campaign_import.campaign_import_rows.order(:id).pluck(:id)).to eq(linhas_da_nova)
    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import.normalized_csv).to be_attached
  end

  it 'não começa a partir de uma lista que já foi mandada trazer, está gravando, gravou ou falhou na gravação' do
    campaign_import = importacao
    ler(campaign_import)
    linhas = campaign_import.campaign_import_rows.order(:id).pluck(:id)
    allow(CampaignImports::Parser).to receive(:new).and_call_original

    %i[confirmed queued importing completed completed_with_failures failed].each do |estado|
      campaign_import.reload.update!(status: estado)

      ler(campaign_import)

      expect(campaign_import.reload.status).to eq(estado.to_s)
    end
    expect(CampaignImports::Parser).not_to have_received(:new)
    expect(campaign_import.campaign_import_rows.order(:id).pluck(:id)).to eq(linhas)
    expect(campaign_import.options['trazer']).to eq({})
  end

  it 'lê a partir de todo estado de leitura, e o número da leitura não fica guardado depois que ela termina' do
    %i[uploaded validating needs_column_choice ready_to_confirm validation_failed].each do |estado|
      campaign_import = importacao
      campaign_import.update!(status: estado)

      ler(campaign_import)

      expect(campaign_import.reload).to be_ready_to_confirm
      expect(campaign_import.options['trazer']).to eq({})
    end
  end

  # F5: a varredura precisa saber há quanto tempo a leitura roda, para não tirar a vez de uma leitura viva.
  it 'guarda o instante em que a leitura começou, só enquanto ela roda' do
    campaign_import = importacao
    no_meio = nil
    allow(CampaignImports::Parser).to receive(:new).and_wrap_original do |original, *argumentos, **opcoes|
      no_meio = CampaignImport.find(campaign_import.id).options['trazer']
      original.call(*argumentos, **opcoes)
    end

    freeze_time do
      ler(campaign_import)

      expect(no_meio.keys).to contain_exactly('leitura', 'leitura_em')
      expect(Time.zone.iso8601(no_meio['leitura_em'])).to be_within(1.second).of(Time.current)
    end
    expect(campaign_import.reload.options['trazer']).to eq({})
  end

  # F3: a trava da importação não espera a chamada externa que diz o tipo de cada coluna.
  it 'pergunta o tipo das colunas antes de abrir a transação que grava o resultado' do
    campaign_import = importacao
    com_transacao = []
    allow(CampaignImports::ColumnTypes).to receive(:new).and_wrap_original do |original, *argumentos, **opcoes|
      tipos = original.call(*argumentos, **opcoes)
      allow(tipos).to receive(:perform) do
        com_transacao << ActiveRecord::Base.connection.current_transaction.joinable?
        { 'Plano' => 'texto' }
      end
      tipos
    end

    ler(campaign_import)

    expect(com_transacao).to eq([false])
    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import.schema_resolution['column_types']).to eq('Plano' => 'texto')
  end

  it 'a leitura que falha também não deixa o número guardado' do
    campaign_import = create_contact_import(account: account, user: user, content: "Nome,Obs\nAna Albuquerino,x\n")
    campaign_import.update!(options: campaign_import.options.merge('trazer' => {}))

    ler(campaign_import)

    expect(campaign_import.reload).to be_validation_failed
    expect(campaign_import.options['trazer']).to eq({})
  end

  it 'a importação sem a marca é lida a partir de qualquer estado, como sempre' do
    campaign_import = create_contact_import(account: account, user: user, content: planilha)
    campaign_import.update!(status: :confirmed)

    ler(campaign_import)

    expect(campaign_import.reload).not_to be_confirmed
    expect(campaign_import.options).not_to have_key('trazer')
  end
end
