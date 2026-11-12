require 'rails_helper'

# #2896 (fatia 3) — o "Desfazer" de uma lista trazida e a prévia dele: sai quem a lista criou e em quem ninguém tocou,
# volta a vazio o que ela preencheu em quem já existia (se o valor ainda é o que ela pôs) e sai a empresa que ela criou e
# ficou sem ninguém. As regras de quem fica estão em quem_fica_spec.rb; a rota, em relacionamentos_trazer_desfazer_spec.rb.
RSpec.describe Relacionamentos::Trazer::Desfazer, :aggregate_failures do
  include_context 'with lista trazida'

  let(:campos) { Relacionamentos::CampoPreenchido }

  it 'tira quem a lista criou, devolve o que ela preencheu em quem já existia e apaga as empresas que ela criou' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    expect(ana.reload).to have_attributes(email: 'ana.albuquerino@exemplo.com.br', contact_type: 'customer', custom_attributes: { 'plano' => 'Ouro' })
    expect(account.companies.pluck(:name)).to contain_exactly('Padaria Bom Dia', 'Mercado Sol')
    expect(previa(importacao)).to eq(tira: 1, ficam: 0, devolve: 2)

    desfeita = desfazer(importacao)

    expect(desfeita).to have_attributes(status: 'completed', undo_status: 'completed')
    expect([desfeita.undo_started_at, desfeita.undo_finished_at, desfeita.undo_completed_at]).to all(be_present)
    expect(Relacionamentos::Trazer::Situacao.de(desfeita)).to eq('desfeito')
    expect(account.contacts.exists?(carla.id)).to be(false)
    expect(ana.reload).to have_attributes(name: 'Ana A.', phone_number: '+5511987650001', email: nil, contact_type: 'lead', customer_since: nil,
                                          company_id: nil, custom_attributes: {})
    expect(ana.additional_attributes).not_to include('city')
    expect(bruno.reload).to have_attributes(name: '', phone_number: nil, email: 'bruno.brandolim@exemplo.com.br', contact_type: 'lead',
                                            customer_since: nil, custom_attributes: {})
    expect(bruno.additional_attributes).not_to include('city')
    expect(account.companies.count).to eq(0)
    expect(campos.pendentes.count).to eq(0)
    # As linhas da importação ficam como estavam: o desfazer só grava o estado dele.
    expect(importacao.campaign_import_rows.pluck(:status).uniq).to eq(['imported'])
    expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 0)
  end

  it 'não devolve o campo que alguém mudou depois da lista' do
    importacao = trazer_lista
    ana.reload.update!(email: 'ana.nova@exemplo.com.br', custom_attributes: { 'plano' => 'Diamante' })
    bruno.reload.update!(additional_attributes: bruno.additional_attributes.merge('city' => 'Recife'))
    expect(previa(importacao)).to eq(tira: 1, ficam: 0, devolve: 2)

    desfazer(importacao)

    expect(ana.reload).to have_attributes(email: 'ana.nova@exemplo.com.br', custom_attributes: { 'plano' => 'Diamante' }, customer_since: nil)
    expect(ana.additional_attributes).not_to include('city')
    expect(bruno.reload).to have_attributes(name: '', phone_number: nil, custom_attributes: {})
    expect(bruno.additional_attributes).to include('city' => 'Recife')
    expect(campos.pendentes.where(contact_id: [ana.id, bruno.id]).pluck(:campo)).to match_array(%w[email informacao:plano cidade])
  end

  it 'não conta na prévia a pessoa em que nenhum campo volta' do
    importacao = trazer_lista("Nome,Celular,Plano\nAna Albuquerino,11987650001,Ouro\n", trazer: {})
    expect(anotados(ana)).to eq(['informacao:plano'])
    expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 1)

    ana.reload.update!(custom_attributes: { 'plano' => 'Diamante' })

    expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 0)
  end

  describe 'quem a lista marcou como cliente' do
    # Quatro pessoas que a conta já tinha, todas lead. A lista só as marca como clientes.
    let(:clientes) do
      <<~CSV
        Nome,Celular
        Pessoa Volta,11987650011
        Pessoa Desmarcada,11987650012
        Pessoa Remarcada,11987650013
        Pessoa Ganhou,11987650014
      CSV
    end
    let!(:volta) { create(:contact, account: account, name: 'Pessoa Volta', phone_number: '+5511987650011') }
    let!(:desmarcada) { create(:contact, account: account, name: 'Pessoa Desmarcada', phone_number: '+5511987650012') }
    let!(:remarcada) { create(:contact, account: account, name: 'Pessoa Remarcada', phone_number: '+5511987650013') }
    let!(:ganhou) { create(:contact, account: account, name: 'Pessoa Ganhou', phone_number: '+5511987650014') }

    def ganhar_card(de_quem, quando)
      funil, etapa = create_crm_pipeline(account: account, user: user)
      card = account.crm_cards.create!(pipeline: funil, stage: etapa, contact: de_quem, title: 'Venda')
      card.update_columns(status: Crm::Card.statuses[:won], closed_at: quando) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'devolve ao tipo de antes só quem continua cliente, com a mesma data, e não ganhou card desde a lista' do
      importacao = trazer_lista(clientes, trazer: { 'respostas' => { 'clientes' => 'sim_todas' } })
      expect([volta, desmarcada, remarcada, ganhou].map { |quem| quem.reload.contact_type }.uniq).to eq(['customer'])
      expect(campos.where(campo: 'cliente').count).to eq(4)

      # (b) alguém desmarcou à mão; (c) desmarcou e marcou de novo, com outra data; (d) fechou uma venda depois da lista.
      desmarcada.release_customer!
      remarcada.release_customer!
      travel_to(1.hour.from_now) { remarcada.become_customer! }
      ganhar_card(ganhou, 1.minute.from_now)
      expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 1)

      desfazer(importacao)

      expect(volta.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
      expect(desmarcada.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
      expect(remarcada.reload.contact_type).to eq('customer')
      expect(remarcada.customer_since).to be_present
      expect(ganhou.reload.contact_type).to eq('customer')
      expect(campos.pendentes.where(campo: 'cliente').pluck(:contact_id)).to contain_exactly(desmarcada.id, remarcada.id, ganhou.id)
    end

    it 'o card ganho antes de a lista existir não segura a marca que a lista pôs' do
      ganhar_card(ganhou, 1.day.ago)
      importacao = trazer_lista(clientes, trazer: { 'respostas' => { 'clientes' => 'sim_todas' } })

      desfazer(importacao)

      expect(ganhou.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
    end
  end

  describe 'as empresas' do
    it 'tira o telefone que a lista pôs na empresa que já existia e mantém a empresa criada em que entrou mais gente' do
      mercado = account.companies.create!(name: 'Mercado Sol')
      importacao = trazer_lista
      padaria = account.companies.find_by!(name: 'Padaria Bom Dia')
      expect(mercado.reload.additional_attributes).to include('phone_number' => '1133330003')
      expect(ana.reload.company_id).to eq(padaria.id)
      vizinho = create(:contact, account: account, name: 'Vizinho da Padaria', company: padaria)

      desfazer(importacao)

      # O Mercado Sol já era da conta: fica, sem o telefone que a lista pôs. A Padaria nasceu com a lista, mas tem gente.
      expect(mercado.reload.additional_attributes).not_to include('phone_number')
      expect(padaria.reload.additional_attributes).not_to include('phone_number')
      expect(vizinho.reload.company_id).to eq(padaria.id)
      expect(ana.reload.company_id).to be_nil
      expect(account.companies.pluck(:name)).to contain_exactly('Mercado Sol', 'Padaria Bom Dia')
    end

    it 'não desliga a pessoa da empresa para onde alguém a mudou depois, nem troca o telefone que alguém corrigiu' do
      oficina = account.companies.create!(name: 'Oficina Central')
      mercado = account.companies.create!(name: 'Mercado Sol')
      importacao = trazer_lista
      ana.reload.update!(company: oficina)
      mercado.reload.update!(additional_attributes: { 'phone_number' => '1133339999' })

      desfazer(importacao)

      expect(ana.reload.company_id).to eq(oficina.id)
      expect(mercado.reload.additional_attributes).to include('phone_number' => '1133339999')
      # A Padaria nasceu com a lista e ficou sem ninguém: sai.
      expect(account.companies.pluck(:name)).to contain_exactly('Oficina Central', 'Mercado Sol')
    end
  end

  it 'pula a pessoa que não existe mais, apagada ou mesclada em outra' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    carla.destroy!
    bruno.destroy!
    expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 1)

    desfeita = desfazer(importacao)

    expect(desfeita.undo_status).to eq('completed')
    expect(ana.reload).to have_attributes(email: nil, contact_type: 'lead')
    expect(campos.pendentes.where(contact_id: bruno.id).count).to eq(5)
  end

  describe 'a lista trazida antes de existir a anotação dos campos' do
    it 'só tira quem ela criou: não há o que devolver' do
      importacao = trazer_lista
      campos.delete_all # a lista é de antes da fatia 3: nada dela foi anotado
      carla = pessoa('Carla Carvalhedo')
      expect(previa(importacao)).to eq(tira: 1, ficam: 0, devolve: 0)

      desfazer(importacao)

      expect(account.contacts.exists?(carla.id)).to be(false)
      expect(ana.reload).to have_attributes(email: 'ana.albuquerino@exemplo.com.br', contact_type: 'customer')
      expect(bruno.reload).to have_attributes(name: 'Bruno Brandolim', phone_number: '+5511987650002')
      # A Padaria continua com a Ana; o Mercado Sol nasceu com a lista e ficou sem ninguém.
      expect(account.companies.pluck(:name)).to eq(['Padaria Bom Dia'])
    end

    it 'vale também para a importação da tela antiga, que nunca anota' do
      linhas = ['Nome,Celular,E-mail', 'Ana Albuquerino,11987650001,ana.albuquerino@exemplo.com.br', 'Davi Dornelino,11987650004,']
      importacao = importar_pela_tela_antiga("#{linhas.join("\n")}\n")
      davi = pessoa('Davi Dornelino')
      expect(previa(importacao)).to eq(tira: 1, ficam: 0, devolve: 0)

      desfazer(importacao)

      expect(account.contacts.exists?(davi.id)).to be(false)
      expect(ana.reload.email).to eq('ana.albuquerino@exemplo.com.br')
    end
  end

  it 'não toca a lista nem as pessoas de outra conta' do
    outra = create(:account)
    dono = create(:user, account: outra, role: :administrator)
    outra.enable_features!('companies')
    ana_de_fora = create(:contact, account: outra, name: 'Ana A.', phone_number: '+5511987650001')
    de_fora = trazer_lista(conta: outra, quem: dono)
    importacao = trazer_lista

    desfazer(importacao)

    expect(de_fora.reload.undo_status).to eq('pending')
    expect(ana_de_fora.reload).to have_attributes(email: 'ana.albuquerino@exemplo.com.br', contact_type: 'customer')
    expect(outra.contacts.count).to eq(3)
    expect(outra.companies.count).to eq(2)
    expect(campos.where(account_id: outra.id).pendentes.count).to eq(campos.where(account_id: outra.id).count)
    expect(ana.reload.email).to be_nil
  end

  describe 'o clique e o job' do
    it 'recusa a lista que ainda não foi gravada' do
      importacao = trazer_lista
      %i[confirmed queued importing failed].each do |status|
        importacao.update!(status: status)

        expect(described_class.new(importacao).pedir).to have_attributes(erro: 'nao_pode_desfazer', enfileirar: nil)
      end
      expect(importacao.reload.undo_status).to eq('pending')
      expect(account.contacts.count).to eq(3)
    end

    it 'marca "desfazendo" no primeiro clique e não enfileira de novo no segundo' do
      importacao = trazer_lista

      expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: true)
      expect(importacao.reload).to have_attributes(undo_status: 'processing', undo_finished_at: nil)
      expect(Relacionamentos::Trazer::Situacao.de(importacao)).to eq('desfazendo')
      expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: false)
    end

    it 'põe de volta na fila o desfazer parado há mais tempo que o limite, uma vez' do
      importacao = trazer_lista
      described_class.new(importacao).pedir

      travel_to(CampaignImports::Config.stalled_import_after.from_now + 1.minute) do
        expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: true)
        expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: false)
      end
    end

    it 'não enfileira nada para a lista já desfeita, e o job repetido não faz nada' do
      importacao = trazer_lista
      desfeita = desfazer(importacao)
      quando = desfeita.undo_completed_at

      expect(described_class.new(desfeita).pedir).to have_attributes(erro: nil, enfileirar: false)
      described_class.new(desfeita).call

      expect(desfeita.reload).to have_attributes(undo_status: 'completed', undo_completed_at: quando)
    end

    it 'sem o clique o job não faz nada' do
      importacao = trazer_lista

      described_class.new(importacao).call

      expect(importacao.reload.undo_status).to eq('pending')
      expect(account.contacts.count).to eq(3)
    end

    it 'quando quebra, marca o desfazer como falho, deixa o erro subir e aceita um novo clique' do
      importacao = trazer_lista
      described_class.new(importacao).pedir
      apagador = instance_double(Contacts::BulkDeleteService)
      allow(apagador).to receive(:perform).and_raise(ActiveRecord::QueryCanceled, 'canceling statement due to statement timeout')
      allow(Contacts::BulkDeleteService).to receive(:new).and_return(apagador)

      expect { described_class.new(importacao.reload, quem: user).call }.to raise_error(ActiveRecord::QueryCanceled)

      expect(importacao.reload).to have_attributes(undo_status: 'failed', undo_completed_at: nil)
      expect(importacao.undo_finished_at).to be_present
      expect(Relacionamentos::Trazer::Situacao.de(importacao)).to eq('pronto')
      expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: true)
    end

    it 'apaga pelo serviço de apagar em lote, em nome de quem pediu' do
      importacao = trazer_lista
      carla = pessoa('Carla Carvalhedo')
      allow(Contacts::BulkDeleteService).to receive(:new).and_call_original

      desfazer(importacao)

      expect(Contacts::BulkDeleteService).to have_received(:new).with(account: account, contact_ids: [carla.id], user: user)
    end
  end
end
