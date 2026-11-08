require 'rails_helper'
require Rails.root.join('db/migrate/20261108310000_add_convite_uid_index_to_messages.rb')
require Rails.root.join('db/migrate/20261108320000_backfill_convite_uid_on_messages.rb')

# #2042 — os convites já recebidos ganham a chave do UID que a busca da versão anterior usa pelo índice.
RSpec.describe BackfillConviteUidOnMessages do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:chave) { Digest::SHA256.hexdigest('uid-1@google.com') }

  def recebida(content_attributes, created_at: Time.utc(2026, 10, 21))
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    # Como em produção: gravada antes do #2042, sem a chave; o content_attributes é JSON guardado como texto.
    Message.where(id: message.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['content_attributes = to_json(?::text), additional_attributes = ?::jsonb, created_at = ?', content_attributes.to_json, '{}', created_at]
    )
    message
  end

  def preencher
    BackfillConviteUidOnMessages.new.up
  end

  it 'grava a chave do UID no convite já recebido, lendo o JSON guardado em texto' do
    convite = recebida({ email: { convite: { uid: 'uid-1@google.com', metodo: 'REQUEST' } } })

    preencher

    expect(convite.reload.additional_attributes['convite_uid_sha256']).to eq(chave)
  end

  it 'não toca e-mail sem convite, nem o de antes do cartão; rodar de novo não muda nada', :aggregate_failures do
    sem_convite = recebida({ email: { subject: 'Oi' } })
    sem_uid = recebida({ email: { convite: { uid: '', metodo: 'REQUEST' } } })
    antigo = recebida({ email: { convite: { uid: 'uid-1@google.com' } } }, created_at: Time.utc(2026, 10, 1))
    convite = recebida({ email: { convite: { uid: 'uid-1@google.com' } } })

    2.times { preencher }

    expect(sem_convite.reload.additional_attributes).not_to have_key('convite_uid_sha256')
    expect(sem_uid.reload.additional_attributes).not_to have_key('convite_uid_sha256')
    expect(antigo.reload.additional_attributes).not_to have_key('convite_uid_sha256')
    expect(convite.reload.additional_attributes).to eq('convite_uid_sha256' => chave)
  end

  it 'mantém o que já havia em additional_attributes' do
    convite = recebida({ email: { convite: { uid: 'uid-1@google.com' } } })
    Message.where(id: convite.id).update_all(additional_attributes: { 'origem' => 'imap' }) # rubocop:disable Rails/SkipsModelValidations

    preencher

    expect(convite.reload.additional_attributes).to eq('origem' => 'imap', 'convite_uid_sha256' => chave)
  end

  it 'o índice parcial existe, é válido, e o statement_timeout volta ao de antes', :aggregate_failures do
    migration = AddConviteUidIndexToMessages.new
    antes = ActiveRecord::Base.connection.select_value('SHOW statement_timeout')
    durante = migration.send(:sem_limite_de_tempo) { ActiveRecord::Base.connection.select_value('SHOW statement_timeout') }

    expect(durante).to eq('0')

    expect(ActiveRecord::Base.connection.index_exists?(:messages, nil, name: AddConviteUidIndexToMessages::INDICE)).to be(true)
    expect(migration.send(:indice_invalido?)).to be(false)
    expect(ActiveRecord::Base.connection.select_value('SHOW statement_timeout')).to eq(antes)
  end
end
