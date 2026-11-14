require 'rails_helper'

# #2896 — a lista que a pessoa mandou trazer e ficou parada antes de fechar a conferência, porque o job se perdeu. A
# varredura de Campanhas (CampaignImports::StalledImportsJob) a põe de volta na fila. Só a importação com a marca
# options['trazer'] é tocada: o que a varredura já fazia com as outras não muda.
RSpec.describe ContactImports::Trazer::ConferenciasParadas, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:prazo) { CampaignImports::Config.stalled_import_after }
  let(:fechar) { ContactImports::Trazer::FecharConferenciaJob }
  let(:ligada) { 'true' }

  around { |example| with_modified_env('CAMPAIGN_IMPORT_ENABLED' => ligada) { example.run } }

  # Cinco pessoas lidas, e a importação como "Trazer" a deixa: `confirmed`, sem mexer mais desde então.
  def confirmada(parada_desde:, marca: true, estado: :confirmed)
    importacao = queued_import(:contacts, account: account, user: user)
    opcoes = marca ? importacao.options.merge('trazer' => {}) : importacao.options
    importacao.update!(status: estado, confirmed_at: parada_desde, queued_at: nil, options: opcoes)
    importacao.update_columns(updated_at: parada_desde) # rubocop:disable Rails/SkipsModelValidations
    importacao
  end

  def varrer
    CampaignImports::StalledImportsJob.perform_now
  end

  it 'põe de volta na fila o fechamento da lista parada há mais que o prazo, uma vez só por prazo' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago)

    expect { varrer }.to have_enqueued_job(fechar).with(importacao).once
    expect(importacao.reload).to be_confirmed

    # A varredura seguinte não enfileira de novo: a importação acabou de ser mexida.
    expect { varrer }.not_to have_enqueued_job(fechar)
    # Se o job se perder outra vez, o prazo seguinte a pega de novo.
    travel_to((prazo + 1.minute).from_now) { expect { varrer }.to have_enqueued_job(fechar).with(importacao).once }
  end

  it 'a lista parada entra sozinha' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago)

    perform_enqueued_jobs { varrer }

    expect(importacao.reload).to be_completed
    expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
  end

  it 'não mexe na lista que a pessoa acabou de mandar trazer' do
    importacao = confirmada(parada_desde: (prazo - 1.minute).ago)

    expect { varrer }.not_to have_enqueued_job(fechar)
    expect(importacao.reload).to be_confirmed
  end

  it 'não mexe na importação parada em `confirmed` que não é de "Trazer minha lista"' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago, marca: false)
    antes = importacao.reload.updated_at

    expect { varrer }.not_to have_enqueued_job
    expect(importacao.reload).to have_attributes(status: 'confirmed', updated_at: antes)
  end

  it 'não mexe na lista que ainda não foi mandada trazer nem na que já saiu de `confirmed`' do
    %i[ready_to_confirm completed failed].each { |estado| confirmada(parada_desde: (prazo + 1.minute).ago, estado: estado) }

    expect { varrer }.not_to have_enqueued_job(fechar)
  end

  describe 'com a importação por planilha desligada na instalação' do
    let(:ligada) { 'false' }

    it 'não põe nada na fila' do
      confirmada(parada_desde: (prazo + 1.minute).ago)

      expect { varrer }.not_to have_enqueued_job
    end
  end

  # B3: a leitura da planilha que perdeu o job também volta para a fila.
  it 'põe de volta na fila a leitura parada em `uploaded` ou `validating` há mais que o prazo, só a da importação marcada' do
    paradas = %i[uploaded validating].map { |estado| confirmada(parada_desde: (prazo + 1.minute).ago, estado: estado) }
    confirmada(parada_desde: (prazo - 1.minute).ago, estado: :validating)
    confirmada(parada_desde: (prazo + 1.minute).ago, estado: :validating, marca: false)

    expect { varrer }.to have_enqueued_job(CampaignImports::ValidateJob).exactly(:twice)
    leituras = enqueued_jobs.select { |job| job[:job] == CampaignImports::ValidateJob }
    expect(leituras.map { |job| job[:args].first['_aj_globalid'] }).to match_array(paradas.map { |importacao| importacao.to_global_id.to_s })
    expect { varrer }.not_to have_enqueued_job(CampaignImports::ValidateJob)
  end

  # F5: `validating` com o instante do começo guardado é leitura que começou. Ela tem três prazos para terminar.
  def lendo(comecou_ha:)
    importacao = confirmada(parada_desde: comecou_ha.ago, estado: :validating)
    viva = { 'leitura' => SecureRandom.uuid, 'leitura_em' => comecou_ha.ago.iso8601 }
    importacao.update_columns(options: importacao.options.merge('trazer' => viva), updated_at: comecou_ha.ago) # rubocop:disable Rails/SkipsModelValidations
    importacao
  end

  it 'não tira a vez da leitura viva: `validating` com leitura começada há 20 minutos não é tocada' do
    importacao = lendo(comecou_ha: 20.minutes)
    antes = importacao.reload.attributes.slice('updated_at', 'options', 'status')

    expect { varrer }.not_to have_enqueued_job

    expect(importacao.reload.attributes.slice('updated_at', 'options', 'status')).to eq(antes)
  end

  it 'a leitura que começou e não terminou em três prazos volta para a fila, e a volta é contada' do
    ainda_no_prazo = lendo(comecou_ha: (3 * prazo) - 1.minute)
    importacao = lendo(comecou_ha: (3 * prazo) + 1.minute)

    expect { varrer }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao).once

    expect(importacao.reload.options['trazer']).to include('releituras' => 1)
    expect(ainda_no_prazo.reload.options['trazer']).not_to include('releituras')
    # A que voltou para a fila não volta de novo na varredura seguinte: acabou de ser mexida.
    expect { varrer }.not_to have_enqueued_job
    # A leitura nova tira a vez da velha e termina.
    perform_enqueued_jobs(only: CampaignImports::ValidateJob)
    expect(importacao.reload).to be_ready_to_confirm
    expect(importacao.options['trazer']).to eq({})
  end

  # Rodada 5: a leitura que nunca termina não volta para a fila para sempre.
  it 'na terceira volta da leitura parada, desiste: a leitura vira "falhou" e nada mais vai para a fila' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago, estado: :validating)
    parar_de_novo = -> { importacao.update_columns(updated_at: (prazo + 1.minute).ago) } # rubocop:disable Rails/SkipsModelValidations

    expect { varrer }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao).once
    expect(importacao.reload.options['trazer']).to eq('releituras' => 1)
    parar_de_novo.call
    expect { varrer }.to have_enqueued_job(CampaignImports::ValidateJob).with(importacao).once
    expect(importacao.reload.options['trazer']).to eq('releituras' => 2)
    parar_de_novo.call

    expect { varrer }.not_to have_enqueued_job(CampaignImports::ValidateJob)

    expect(importacao.reload).to be_validation_failed
    expect(importacao.options['trazer']).to eq({})
    expect(Relacionamentos::Trazer::Leitura.new(importacao).call).to eq(id: importacao.id, situacao: 'falhou', erro: 'leitura')
    parar_de_novo.call
    expect { varrer }.not_to have_enqueued_job
  end

  # Rodada 6: a tela já mostra a importação vencida como vencida; ler a planilha de novo não muda isso.
  it 'não põe de volta na fila a leitura da importação vencida, nem conta a volta' do
    vencidas = %i[uploaded validating].map { |estado| confirmada(parada_desde: (prazo + 1.minute).ago, estado: estado) }
    vencidas.each { |importacao| importacao.update_columns(created_at: (CampaignImports::Config.original_file_retention + 1.minute).ago) } # rubocop:disable Rails/SkipsModelValidations
    antes = vencidas.map { |importacao| importacao.reload.updated_at }

    expect { varrer }.not_to have_enqueued_job

    vencidas.each(&:reload)
    expect(vencidas.map(&:status)).to eq(%w[uploaded validating])
    expect(vencidas.map(&:updated_at)).to eq(antes)
    expect(vencidas.map { |importacao| importacao.options['trazer'] }).to eq([{}, {}])
    expect(Relacionamentos::Trazer::Leitura.new(vencidas.last).call).to eq(id: vencidas.last.id, situacao: 'vencida')
  end

  it 'a lista já mandada trazer não vence: o fechamento parado volta para a fila mesmo passado o prazo da planilha' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago)
    importacao.update_columns(created_at: (CampaignImports::Config.original_file_retention + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations

    expect { varrer }.to have_enqueued_job(fechar).with(importacao).once
  end

  it 'a leitura que termina zera a contagem das voltas' do
    importacao = confirmada(parada_desde: (prazo + 1.minute).ago, estado: :validating)

    perform_enqueued_jobs(only: CampaignImports::ValidateJob) { varrer }

    expect(importacao.reload).to be_ready_to_confirm
    expect(importacao.options['trazer']).to eq({})
  end

  it 'uma importação que levanta erro não impede as seguintes, e o log só leva o id e a classe do erro' do
    primeira = confirmada(parada_desde: (prazo + 2.minutes).ago)
    segunda = confirmada(parada_desde: (prazo + 1.minute).ago)
    allow(fechar).to receive(:perform_later).and_wrap_original do |original, importacao|
      raise IOError, 'Ana Albuquerino 11987650001' if importacao.id == primeira.id

      original.call(importacao)
    end
    allow(Rails.logger).to receive(:error)

    expect { varrer }.to have_enqueued_job(fechar).with(segunda).once

    expect(Rails.logger).to have_received(:error).with("[ContactImports::Trazer::ConferenciasParadas] import_id=#{primeira.id} IOError")
  end
end
