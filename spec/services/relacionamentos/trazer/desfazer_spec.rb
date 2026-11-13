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
    expect(described_class.ficaram(desfeita)).to eq(0)
    expect(desfeita.validation_summary).not_to include('desfazer_ficaram')
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

  it 'deixa na base a pessoa que a lista criou e alguém editou depois, e a prévia a conta entre as que ficam' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    expect(previa(importacao)).to eq(tira: 1, ficam: 0, devolve: 2)

    carla.update!(email: 'carla.carvalhedo@exemplo.com.br')
    expect(previa(importacao)).to eq(tira: 0, ficam: 1, devolve: 2)

    desfazer(importacao)

    expect(account.contacts.exists?(carla.id)).to be(true)
    expect(carla.reload).to have_attributes(email: 'carla.carvalhedo@exemplo.com.br', phone_number: '+5511987650003')
    # O Mercado Sol nasceu com a lista, mas a Carla continua nele.
    expect(account.companies.pluck(:name)).to eq(['Mercado Sol'])
  end

  it 'não tira quem tem seguro na carteira: a apólice sairia junto com a pessoa' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    apolice = create(:carteira_apolice, account: account, contact: carla)
    expect(previa(importacao)).to eq(tira: 0, ficam: 1, devolve: 2)

    desfazer(importacao)

    expect(account.contacts.exists?(carla.id)).to be(true)
    expect(Carteira::Apolice.exists?(apolice.id)).to be(true)
  end

  it 'quando o apagar em lote mantém alguém, a lista fica desfeita e guarda quantas pessoas ficaram, só o número' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    # O apagar em lote não levanta erro quando mantém a pessoa (a reunião que não cancela, o card que mudou): só segue.
    allow(Contacts::BulkDeleteService).to receive(:new).and_return(instance_double(Contacts::BulkDeleteService, perform: nil))

    desfeita = desfazer(importacao)

    expect(desfeita.undo_status).to eq('completed')
    expect(account.contacts.exists?(carla.id)).to be(true)
    expect(described_class.ficaram(desfeita)).to eq(1)
    expect(desfeita.validation_summary).to include('desfazer_ficaram' => 1)
    historico = Relacionamentos::Trazer::Historico.new(account.campaign_imports.contact_imports).call
    expect(historico.sole).to include(situacao: 'desfeito', ficaram: 1)
  end

  it 'a lista desfeita sem ninguém ficar não leva o número no histórico; a que ainda não foi desfeita também não' do
    importacao = trazer_lista
    historico = -> { Relacionamentos::Trazer::Historico.new(account.campaign_imports.contact_imports).call.sole }
    expect(historico.call).not_to include(:ficaram)

    desfazer(importacao)

    expect(historico.call).to include(situacao: 'desfeito')
    expect(historico.call).not_to include(:ficaram)
  end

  it 'devolver os campos não avisa "contato mudou"; o aviso de quem saiu continua' do
    importacao = trazer_lista
    avisador = Rails.configuration.dispatcher
    allow(avisador).to receive(:dispatch).and_call_original

    desfazer(importacao)

    expect(ana.reload).to have_attributes(email: nil, contact_type: 'lead')
    expect(avisador).not_to have_received(:dispatch).with(Events::Types::CONTACT_UPDATED, any_args)
    expect(avisador).to have_received(:dispatch).with(Events::Types::CONTACT_DELETED, any_args)
    expect(Current.suppress_contact_events).to be_nil
  end

  it 'apaga as anotações de quem saiu e as dos campos que voltaram; fica só a do campo que não voltou' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    expect(anotados(carla)).to match_array(%w[pessoa_criada telefone_da_empresa])
    ana.reload.update!(custom_attributes: { 'plano' => 'Diamante' })

    desfazer(importacao)

    expect(campos.where(contact_id: carla.id)).to be_empty
    expect(campos.where.not(devolvido_em: nil)).to be_empty
    expect(campos.pluck(:contact_id, :campo)).to eq([[ana.id, 'informacao:plano']])
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

  it 'não tira o telefone nem o e-mail de quem a conta já procurou desde a lista; o resto volta' do
    importacao = trazer_lista
    create(:conversation, account: account, contact: bruno)
    create(:conversation, account: account, contact: ana)

    desfazer(importacao)

    # O telefone do Bruno e o e-mail da Ana vieram da lista e já serviram para falar com eles: ficam.
    expect(bruno.reload).to have_attributes(name: '', phone_number: '+5511987650002', contact_type: 'lead', custom_attributes: {})
    expect(ana.reload).to have_attributes(email: 'ana.albuquerino@exemplo.com.br', company_id: nil, custom_attributes: {})
    expect(campos.pendentes.where(contact_id: [ana.id, bruno.id]).pluck(:campo)).to match_array(%w[telefone email])
  end

  it 'a conversa de antes da lista não segura o telefone que a lista pôs' do
    create(:conversation, account: account, contact: bruno, created_at: 2.days.ago)
    importacao = trazer_lista

    desfazer(importacao)

    expect(bruno.reload.phone_number).to be_nil
  end

  it 'confere a pessoa de novo logo antes de apagar: quem ganhou conversa enquanto o bloco andava fica' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    quem_fica = Relacionamentos::Trazer::QuemFica.new(importacao)
    allow(Relacionamentos::Trazer::QuemFica).to receive(:new).and_return(quem_fica)
    allow(quem_fica).to receive(:em_blocos) do |&bloco|
      # A mensagem chega depois de o bloco já ter decidido que a Carla sai.
      create(:conversation, account: account, contact: carla)
      bloco.call([carla.id], [])
    end

    desfazer(importacao)

    expect(account.contacts.exists?(carla.id)).to be(true)
  end

  it 'desfaz também a lista que quebrou no meio da gravação' do
    importacao = trazer_lista
    carla = pessoa('Carla Carvalhedo')
    importacao.update!(status: :failed, import_started_at: 1.hour.ago)
    expect(Relacionamentos::Trazer::Situacao.de(importacao)).to eq('falhou')

    desfeita = desfazer(importacao)

    expect(Relacionamentos::Trazer::Situacao.de(desfeita)).to eq('desfeito')
    expect(account.contacts.exists?(carla.id)).to be(false)
    expect(ana.reload.email).to be_nil
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
      card
    end

    # Arquivar o card ganho muda o status e guarda o desfecho; a data do fechamento fica (Crm::Card::DESFECHO_ARQUIVADO).
    def arquivar(card)
      card.update_columns(status: Crm::Card.statuses[:archived], # rubocop:disable Rails/SkipsModelValidations
                          metadata: card.metadata.to_h.merge(Crm::Card::DESFECHO_ARQUIVADO => 'won'))
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

    it 'sem o tipo de antes anotado, a marca não volta, a prévia não a conta e a anotação não fica pendente para sempre' do
      importacao = trazer_lista(clientes, trazer: { 'respostas' => { 'clientes' => 'sim_todas' } })
      campos.where(campo: 'cliente', contact_id: volta.id).update_all(tipo_anterior: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 3)

      desfazer(importacao)

      expect(volta.reload.contact_type).to eq('customer')
      expect(volta.customer_since).to be_present
      expect(desmarcada.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
      expect(campos.where(contact_id: volta.id)).to be_empty
    end

    it 'o card ganho e arquivado depois da lista segura a pessoa como cliente' do
      importacao = trazer_lista(clientes, trazer: { 'respostas' => { 'clientes' => 'sim_todas' } })
      arquivar(ganhar_card(ganhou, 1.minute.from_now))
      expect(previa(importacao)).to eq(tira: 0, ficam: 0, devolve: 3)

      desfazer(importacao)

      expect(ganhou.reload.contact_type).to eq('customer')
      expect(ganhou.customer_since).to be_present
      expect(volta.reload).to have_attributes(contact_type: 'lead', customer_since: nil)
      expect(campos.pendentes.where(campo: 'cliente').pluck(:contact_id)).to eq([ganhou.id])
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

    it 'mantém a empresa criada pela lista que tem seguro em nome dela' do
      importacao = trazer_lista
      mercado = account.companies.find_by!(name: 'Mercado Sol')
      segurado = create(:contact, account: account, name: 'Pessoa Segurada')
      apolice = create(:carteira_apolice, account: account, contact: segurado, company: mercado)

      desfazer(importacao)

      # A Carla saiu e o Mercado Sol ficou sem ninguém, mas a apólice é dele: sem a empresa, ela ficaria sem dono.
      expect(account.companies.pluck(:name)).to eq(['Mercado Sol'])
      expect(apolice.reload.company_id).to eq(mercado.id)
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
    # Os campos de quem não existe mais nunca vão voltar: saem da fila, e as anotações dele não ficam guardadas.
    expect(campos.where(contact_id: [bruno.id, carla.id])).to be_empty
    expect(campos.pendentes.count).to eq(0)
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
      # A que quebrou antes de a gravação começar não pôs ninguém na base.
      [{ status: :confirmed }, { status: :queued }, { status: :importing }, { status: :failed, import_started_at: nil }].each do |estado|
        importacao.update!(estado)

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

    it 'diz que há um desfazer em curso na conta só enquanto ele está vivo' do
      importacao = trazer_lista
      expect(described_class.em_curso?(account)).to be(false)

      described_class.new(importacao).pedir

      expect(described_class.em_curso?(account)).to be(true)
      expect(described_class.em_curso?(create(:account))).to be(false)
      # O desfazer que parou no meio não apaga ninguém: não segura quem quer trazer outra lista.
      travel_to(CampaignImports::Config.stalled_import_after.from_now + 1.minute) do
        expect(described_class.em_curso?(account)).to be(false)
      end
    end

    it 'desistir devolve a marca de "desfazendo" quando o job não chegou à fila, e só ela' do
      importacao = trazer_lista
      described_class.new(importacao).desistir
      expect(importacao.reload.undo_status).to eq('pending')

      described_class.new(importacao).pedir
      described_class.new(importacao).desistir

      expect(importacao.reload).to have_attributes(undo_status: 'failed', undo_completed_at: nil)
      expect(Relacionamentos::Trazer::Situacao.de(importacao)).to eq('pronto')
      expect(described_class.new(importacao).pedir).to have_attributes(erro: nil, enfileirar: true)
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
