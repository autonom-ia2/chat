require 'rails_helper'

# #2896 — "Trazer minha lista" (Fatia 2): nenhum arquivo da conferência fica no armazenamento sem dono. As linhas com
# problema e os consertos guardam telefone, e-mail e nome inteiros: o arquivo que perde o anexo tem de ser apagado.
#
# Em produção o job que apaga o arquivo roda noutra conexão do banco. Se ele entra na fila com a transação ainda
# aberta e roda antes do commit, ainda vê o anexo, desiste em silêncio, e depois do commit o arquivo fica sem dono para
# sempre. O teste roda numa conexão só e não vê isso sozinho: aqui o pedido de apagar feito com transação aberta se
# perde, como se perderia em produção.
RSpec.describe 'Trazer minha lista: arquivos sem dono (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with trazer conferencia'

  before do
    allow(ActiveStorage::PurgeJob).to receive(:perform_later).and_wrap_original do |original, blob|
      original.call(blob) unless ActiveRecord::Base.connection.current_transaction.joinable?
    end
  end

  def sem_dono
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
    ActiveStorage::Blob.where.missing(:attachments).count
  end

  it 'depois de ler a planilha de novo não sobra arquivo sem anexo' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    das_linhas = importacao.reload.linhas_com_problema.blob

    ContactImports::Validator.new(importacao).perform

    expect(sem_dono).to eq(0)
    expect(ActiveStorage::Blob.where(id: das_linhas.id)).to be_empty
    expect(das_linhas.service.exist?(das_linhas.key)).to be(false)
    expect(importacao.reload.linhas_com_problema).to be_attached
    expect(consertos(importacao).keys).to eq([4])
  end

  it 'depois de consertar e voltar atrás (o arquivo dos consertos deixa de existir) não sobra arquivo sem anexo' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    dos_consertos = importacao.reload.consertos.blob

    reabrir(importacao, 4)

    expect(response).to have_http_status(:ok)
    expect(sem_dono).to eq(0)
    expect(dos_consertos.service.exist?(dos_consertos.key)).to be(false)
    expect(importacao.reload.consertos).not_to be_attached
  end

  it 'um conserto em cima do outro troca o arquivo e apaga o antigo' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    primeiro = importacao.reload.consertos.blob

    consertar(importacao, 5, valor: 'davi@exemplo.com.br')

    expect(sem_dono).to eq(0)
    expect(primeiro.service.exist?(primeiro.key)).to be(false)
    expect(consertos(importacao).keys).to eq([4, 5])
  end

  # A contagem dos valores da coluna que diz quem é cliente guarda o texto das células: também não pode ficar sem dono.
  it 'marcar outra coluna como "cliente", ler de novo e desmarcar não deixa a contagem dos valores sem anexo' do
    importacao = ler_planilha
    trocar(importacao, 5, destino: 'cliente')
    da_primeira = importacao.reload.valores_cliente.blob

    trocar(importacao, 4, destino: 'cliente')
    expect(sem_dono).to eq(0)
    expect(da_primeira.service.exist?(da_primeira.key)).to be(false)
    da_segunda = importacao.reload.valores_cliente.blob

    ContactImports::Validator.new(importacao).perform
    expect(sem_dono).to eq(0)
    expect(da_segunda.service.exist?(da_segunda.key)).to be(false)
    da_leitura = importacao.reload.valores_cliente.blob

    trocar(importacao, 4, destino: 'informacao')
    expect(response).to have_http_status(:ok)
    expect(sem_dono).to eq(0)
    expect(da_leitura.service.exist?(da_leitura.key)).to be(false)
    expect(importacao.reload.valores_cliente).not_to be_attached
  end

  it 'a leitura que quebra no meio também não deixa arquivo sem anexo, e os consertos ficam' do
    importacao = ler_planilha(com_problemas)
    consertar(importacao, 4, valor: '11987650004')
    allow(ContactImports::AttributeColumns).to receive(:new).and_raise(IOError)

    ContactImports::Validator.new(importacao.reload).perform

    expect(sem_dono).to eq(0)
    expect(consertos(importacao).keys).to eq([4])
  end
end
