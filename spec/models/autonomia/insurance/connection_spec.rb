require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connection do
  let(:account) { create(:account) }

  it 'refuses to store credentials when the encryption vault is not configured' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    connection = described_class.new(account: account, username: 'a@b.com', password: 'x')

    expect(connection).not_to be_valid
    expect(connection.errors[:base].join).to include('ACTIVE_RECORD_ENCRYPTION')
  end

  it 'stores credentials, masks the login and keeps one connection per account/provider' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'corretora@exemplo.com.br', password: 'x')

    expect(connection.username_hint).to eq('co*******@exemplo.com.br')
    expect(connection.public_payload.keys).not_to include(:password, :username)
    expect(connection.public_payload.to_json).not_to include('corretora@exemplo.com.br')
    expect { described_class.create!(account: account, username: 'o@b.com', password: 'y') }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  # TERMO 5 DA ENTREGA 16 — o aviso de "conta em uso" não sai daqui para a tela, com nome nenhum.
  #
  # O portal manda "já existe uma sessão ativa" em TODO login (6 de 6 nos logins simultâneos de
  # 10/09/2026): é aviso de reuso da sessão compartilhada, não prova de que outra pessoa esteja na
  # conta. Publicá-lo fazia a tela de Conexões afirmar ao corretor algo que o dado não sustenta.
  # A chave pode continuar no `metadata` de uma linha antiga; o que não pode é voltar ao payload.
  #
  # A GUARDA OLHA O EFEITO, NÃO O NOME. A primeira versão deste exemplo só conferia a ausência da
  # palavra `account_already_active` — republicar o MESMO retrato com outro nome (`conta_em_uso`,
  # digamos) passava batido, e o aviso falso voltava à tela sem derrubar teste nenhum. Aqui a linha
  # COM a chave em `metadata` tem de produzir o MESMO `public_payload` da linha SEM ela: se o retrato
  # voltar a influenciar o que sai para o frontend, por qualquer caminho e com qualquer nome, os dois
  # deixam de bater.
  #
  # `updated_at` fica de fora da comparação porque gravar `metadata` é uma escrita — e é exatamente a
  # escrita que acontece entre um retrato e o outro.
  it 'publica o mesmo payload com e sem o aviso de conta em uso no metadata' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'a@b.com', password: 'x')
    sem_aviso = connection.public_payload

    connection.merge_metadata!('account_already_active' => { 'observed_at' => '2026-09-06T14:05:00Z',
                                                             'session_started_at' => '2026-09-06T14:02:00Z' })
    com_aviso = connection.reload.public_payload

    expect(com_aviso.except(:updated_at)).to eq(sem_aviso.except(:updated_at))
    expect(com_aviso.to_json).not_to include('account_already_active')
    expect(com_aviso.to_json).not_to include('2026-09-06T14:02:00Z')
  end

  # `forget_metadata!` NÃO PODE COBRAR UM LOCK DE LINHA DE QUEM NÃO TEM O QUE APAGAR.
  #
  # Ele roda em TODO login (`Connections::Session#open!`), e o caso comum é a chave não existir — a
  # conexão nunca passou pela versão que gravava o aviso, ou já foi limpa no primeiro login depois do
  # deploy. Sem a leitura antes do lock, cada login pagaria um `SELECT … FOR UPDATE` para descobrir
  # que não havia nada a fazer: o healthcheck varre todas as conexões de 30 em 30 minutos e o polling
  # de cotação passa por aqui de poucos em poucos segundos.
  #
  # Quando HÁ o que apagar, o lock é obrigatório: `metadata` é jsonb compartilhado (comissão da
  # corretora, diagnóstico da conexão, seguradoras pendentes) com dois escritores concorrentes de
  # verdade, e ler-alterar-gravar sem lock apaga em silêncio o que o outro acabou de registrar. Por
  # isso os dois exemplos — um trava a economia, o outro trava a segurança.
  it 'não pega lock de linha quando não existe a chave para apagar' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'a@b.com', password: 'x')

    expect(connection).not_to receive(:with_lock)

    connection.forget_metadata!('account_already_active')
  end

  it 'apaga sob lock de linha quando a chave existe, sem levar o resto do metadata junto' do
    enable_test_encryption!
    connection = described_class.create!(account: account, username: 'a@b.com', password: 'x')
    connection.merge_metadata!('account_already_active' => { 'observed_at' => '2026-09-06T14:05:00Z' },
                               'comissao' => { 'auto' => 12 })

    expect(connection).to receive(:with_lock).once.and_call_original

    connection.forget_metadata!('account_already_active')

    expect(connection.reload.metadata.to_h).to eq('comissao' => { 'auto' => 12 })
  end

  it 'allows an empty (not_configured) record without the vault' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    expect(described_class.new(account: account)).to be_valid
  end
end
