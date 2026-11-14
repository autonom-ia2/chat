require 'rails_helper'

# #2896 (fatia 3) — o "Desfazer" de verdade, com o apagar, medido a cada rodada da CI: uma lista de 500 pessoas que a
# lista criou (um bloco). O job não tem o prazo de um pedido da tela, e o custo por pessoa é aceito: cada uma que sai
# é perguntada de novo (conversa, card e nota) e apagada pelo serviço de apagar em lote, com tudo o que apagar um
# contato faz.
#
# O número de consultas e o tempo saem impressos numa linha que começa com MEDICAO_DESFAZER_JOB, para serem lidos no log
# da rodada. Nenhum dos dois é cobrado aqui: o tempo varia com a máquina, e o apagar de um contato é de outra frente. O
# que o Desfazer consulta para decidir é cobrado em desfazer_consultas_spec.rb.
RSpec.describe Relacionamentos::Trazer::Desfazer, :aggregate_failures do
  include ListaTrazidaGrandeHelpers

  let(:pessoas) { 500 }

  it 'mede o Desfazer de uma lista com 500 pessoas criadas, apagando de verdade' do
    conta = create(:account)
    quem = create(:user, account: conta, role: :administrator)
    importacao = lista_trazida_vazia(conta, quem)
    recusaram = por_pessoas_criadas(importacao, pessoas)
    atualizar_estatisticas
    described_class.new(importacao).pedir

    medida = medir_consultas { described_class.new(importacao.reload, quem: quem).call }

    puts "MEDICAO_DESFAZER_JOB pessoas=#{pessoas} consultas=#{medida.consultas} segundos=#{medida.segundos.round(3)}"
    expect(importacao.reload.undo_status).to eq('completed')
    expect(described_class.ficaram(importacao)).to eq(0)
    expect(conta.contacts.count).to eq(recusaram)
  end
end
