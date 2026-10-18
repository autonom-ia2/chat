require 'rails_helper'

# Concorrência real (#1601, invariante 10): duas threads, cada uma com a sua conexão, sem a transação do teste. Duas
# avaliações do mesmo contato ao mesmo tempo: nenhuma perda, nenhuma duplicação de vigente.
RSpec.describe Crm::Memoria::Gravador do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account, role: :administrator)).first }
  let!(:card) { account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, contact: contact, title: 'C') }

  after { limpar_conta!(account) }

  def ao_mesmo_tempo(valores, **base)
    largada = Queue.new
    threads = valores.map do |valor|
      Thread.new do
        largada.pop
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.gravar!(base.merge(account_id: account.id, contact_id: contact.id, tipo: 'fato', valor: valor, fonte: 'cliente',
                                             prova_message_ids: [1], gerado_por: 't'))
        end
      end
    end
    valores.size.times { largada << true }
    threads.each(&:join)
  end

  it 'escopo contato (trava consultiva): um vigente só, a outra vira versão expirada, nada some' do
    ao_mesmo_tempo(%w[111 222], escopo: 'contato', chave: 'cpf')

    fatos = Crm::MemoriaFato.where(account_id: account.id, chave: 'cpf')
    expect(fatos.count).to eq(2)
    expect(fatos.vigentes.count).to eq(1)
  end

  it 'escopo card (índice único de vigente com nova tentativa): um vigente só, sem erro' do
    ao_mesmo_tempo(%w[AAA BBB CCC], escopo: 'card', card_id: card.id, chave: 'placa')

    fatos = Crm::MemoriaFato.where(account_id: account.id, chave: 'placa')
    expect(fatos.vigentes.count).to eq(1)
    expect(fatos.count).to eq(3)
  end
end
