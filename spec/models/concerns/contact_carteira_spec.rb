require 'rails_helper'

# E4 (#2897): a apólice aponta para o contato SEM cascata no banco, de propósito: ela guarda um PDF, e a cascata apagaria
# a linha e deixaria o arquivo. Quem cuida das apólices quando o contato sai é o app. Este spec cobra cada caminho: o
# contato apagado, a exclusão em lote, a mescla de contatos, a limpeza de contato parado e a exclusão da conta. O
# primeiro exemplo lê as chaves do próprio Postgres: tabela nova que apontar para contacts sem dizer o que fazer com a
# linha quebra aqui, e não na exclusão de um contato em produção.
RSpec.describe ContactCarteira, type: :request do
  let(:account) { create(:account) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { guardar_pdf_na(criar_apolice(marina, numero: 'EX-001234')) }

  before { seguro.eventos.create!(tipo: 'chegou_planilha', quando: Time.current) }

  def sobrou
    { apolice: Carteira::Apolice.exists?(seguro.id), historia: Carteira::ApoliceEvento.exists?(apolice_id: seguro.id),
      anexo: ActiveStorage::Attachment.exists?(record_type: 'Carteira::Apolice', record_id: seguro.id) }
  end

  it 'toda chave para contacts sem ON DELETE tem dono: o contato apaga, a mescla move e a exclusão da conta apaga antes' do
    barram = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT c.conrelid::regclass::text, a.attname::text
      FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f' AND c.confrelid = 'contacts'::regclass AND c.confdeltype IN ('a', 'r')
    SQL
    # `destroy_async` não serve: o job dele roda depois do DELETE do contato, que a chave já teria barrado.
    apagam = %i[destroy delete_all]
    com_dono = Contact.reflect_on_all_associations(:has_many).select { |associacao| apagam.include?(associacao.options[:dependent]) }
    apagadas_com_o_contato = com_dono.map { |associacao| [associacao.klass.table_name, associacao.foreign_key.to_s] }
    movidas_na_mescla = Contacts::NinthDigitDuplicateMerger::REPOINT_MODELS.map { |modelo| modelo.constantize.table_name }
    tabelas = barram.map(&:first).uniq

    expect(barram).to include(%w[carteira_apolices contact_id])
    expect(barram - apagadas_com_o_contato).to eq([])
    expect(tabelas - movidas_na_mescla).to eq([])
    expect(tabelas - Autonomia::ExclusaoDaConta.tabelas_antes_do_pre_apagar).to eq([])
  end

  it 'apagar o contato apaga as apólices dele, com a história, e manda o PDF para a limpeza' do
    expect { marina.destroy! }.to have_enqueued_job(ActiveStorage::PurgeJob)

    expect(sobrou).to eq(apolice: false, historia: false, anexo: false)
  end

  it 'a exclusão em lote e o DELETE do contato também apagam, sem esbarrar na chave' do
    outra = create(:contact, account: account, name: 'Caio Exemplo')
    do_caio = criar_apolice(outra, numero: 'EX-555000')
    admin = create(:user, account: account, role: :administrator)

    Contacts::BulkDeleteService.new(account: account, contact_ids: [marina.id], user: admin).perform
    delete "/api/v1/accounts/#{account.id}/contacts/#{outra.id}", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(sobrou).to eq(apolice: false, historia: false, anexo: false)
    expect([Contact.exists?(marina.id), Contact.exists?(outra.id), Carteira::Apolice.exists?(do_caio.id)]).to eq([false, false, false])
  end

  it 'a mescla passa as apólices do contato absorvido para o que fica, com a história e o PDF' do
    fica = create(:contact, account: account, name: 'Marina E.', email: 'marina@exemplo.invalid')

    expect { ContactMergeAction.new(account: account, base_contact: fica, mergee_contact: marina).perform }
      .not_to have_enqueued_job(ActiveStorage::PurgeJob)

    expect(Contact.exists?(marina.id)).to be(false)
    expect(seguro.reload.contact_id).to eq(fica.id)
    expect(sobrou).to eq(apolice: true, historia: true, anexo: true)
    expect(fica.apolices.pluck(:numero)).to eq(['EX-001234'])
  end

  it 'contato com apólice não é contato parado: a limpeza de contatos sem conversa não o apaga' do
    antigo = create(:contact, account: account, name: 'Sem Telefone Exemplo', created_at: 2.months.ago)
    sem_nada = create(:contact, account: account, name: 'Visitante Exemplo', created_at: 2.months.ago)
    criar_apolice(antigo, numero: 'EX-ANTIGO')

    Internal::RemoveStaleContactsService.new(account: account).perform

    expect([Contact.exists?(antigo.id), Contact.exists?(sem_nada.id)]).to eq([true, false])
  end

  it 'a exclusão da conta apaga as apólices antes dos contatos, com a história, e manda o PDF para a limpeza; só as da conta' do
    de_outra_conta = guardar_pdf_na(criar_apolice(create(:contact, account: create(:account)), numero: 'EX-001234'))

    expect { Autonomia::ExclusaoDaConta.new(account).antes_do_pre_apagar }.to have_enqueued_job(ActiveStorage::PurgeJob).exactly(:once)

    expect(sobrou).to eq(apolice: false, historia: false, anexo: false)
    expect([Carteira::Apolice.exists?(de_outra_conta.id), de_outra_conta.reload.pdf.attached?]).to eq([true, true])
    expect { marina.destroy! }.not_to raise_error
  end

  it 'o Guia não guarda nem tira o PDF, nem recebe o link dele: os três só na tela, com a frase nos dois idiomas' do
    trava = Carteira::Pdf::SO_NA_TELA_DO_GUIA
    rotas = Rails.application.routes.routes.map do |rota|
      "#{rota.verb} #{Autonomia::Guide::Rotas.recurso(rota.path.spec.to_s.sub('(.:format)', ''))}"
    end

    expect(trava.keys.map { |acao| acao.split.first }).to match_array(%w[POST DELETE GET])
    expect(rotas).to include(*trava.keys)
    expect(Autonomia::Guide::Acoes::SO_NA_TELA).to include(trava)
    expect(trava.keys.map { |acao| Autonomia::Guide::Acoes.fora_do_catalogo?(acao) }).to all(be(true))
    expect(%i[en pt_BR].map { |idioma| I18n.exists?('autonomia.guide.only_on_screen.seguro_pdf', idioma) }).to eq([true, true])
  end
end
