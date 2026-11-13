require 'rails_helper'

# #2896 (fatia 3) — o "Desfazer" lê a lista em blocos, como a prévia (previa_do_desfazer_consultas_spec.rb). O que não
# pode acontecer é uma rodada de consultas por pessoa: conferir de novo, uma a uma, todos os lugares onde a pessoa pode
# aparecer (umas 20 consultas por pessoa, 100 mil numa lista de 5 mil), ou perguntar de novo pela procura a cada campo
# que volta. Pessoa a pessoa ficam só as perguntas que o Desfazer faz de propósito: a conversa, o card e a nota de quem
# vai sair, e o card ganho de quem vai deixar de ser cliente.
#
# A medida sai da diferença entre duas listas, uma com um bloco e outra com mais, dividida pelas pessoas a mais: o que
# o Desfazer consulta uma vez só some na conta. O teto é folgado de propósito (uma consulta por fatia ou por bloco dá
# centésimos por pessoa; uma por pessoa dá 1): o que ele pega é a consulta que voltou para dentro do laço.
#
# O primeiro exemplo mede só as conferências: o apagar é trocado por um dublê. O Desfazer de verdade, com o apagar, é
# medido em desfazer_medicao_spec.rb.
RSpec.describe Relacionamentos::Trazer::Desfazer, :aggregate_failures do
  include ListaTrazidaGrandeHelpers

  let(:bloco) { Relacionamentos::Trazer::QuemFica::BLOCO }
  # Cada pessoa completada tem três campos anotados (ListaTrazidaGrandeHelpers#por_pessoas_completadas).
  let(:campos_por_pessoa) { 3 }
  let(:quase_nada) { 0.1 }

  # O clique e o job numa lista de uma conta só dela. Devolve a medida do job.
  def medida_do_desfazer
    conta = create(:account)
    quem = create(:user, account: conta, role: :administrator)
    importacao = lista_trazida_vazia(conta, quem)
    yield(importacao)
    atualizar_estatisticas
    described_class.new(importacao).pedir
    medir_consultas { described_class.new(importacao.reload, quem: quem).call }
  end

  def consultas_por_pessoa(maior, menor, tabela, pessoas_a_mais)
    (maior.por_tabela[tabela][:consultas] - menor.por_tabela[tabela][:consultas]).fdiv(pessoas_a_mais)
  end

  it 'só as conferências, sem o apagar: as regras de fatia em fatia; pessoa a pessoa, só a conversa, o card e a nota' do
    # O apagar em lote é um dublê: o que se mede é o que o Desfazer consulta para decidir, não o que apagar custa.
    allow(Contacts::BulkDeleteService).to receive(:new).and_return(instance_double(Contacts::BulkDeleteService, perform: nil))
    de_um_bloco = medida_do_desfazer { |importacao| por_pessoas_criadas(importacao, bloco) }
    de_tres_blocos = medida_do_desfazer { |importacao| por_pessoas_criadas(importacao, 3 * bloco) }
    a_mais = 2 * bloco

    %w[taggings campaign_recipients carteira_apolices crm_follow_ups].each do |tabela|
      expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, tabela, a_mais)).to be < quase_nada
    end
    # Uma pergunta por pessoa que vai sair: a conversa, a nota e o card (duas: o da pessoa e o pedido por ela).
    expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, 'conversations', a_mais)).to be <= 1.1
    expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, 'notes', a_mais)).to be <= 1.1
    expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, 'crm_cards', a_mais)).to be <= 2.1
    expect((de_tres_blocos.consultas - de_um_bloco.consultas).fdiv(a_mais)).to be < 6
  end

  it 'ao devolver, lê a procura uma vez por bloco de campos; o card ganho, de novo só em quem deixa de ser cliente' do
    pessoas = bloco / campos_por_pessoa
    de_um_bloco = medida_do_desfazer { |importacao| por_pessoas_completadas(importacao, pessoas) }
    de_quatro_blocos = medida_do_desfazer { |importacao| por_pessoas_completadas(importacao, 4 * pessoas) }
    a_mais = 3 * pessoas

    %w[conversations campaign_recipients email_campaign_recipients whatsapp_api_campaign_recipients].each do |tabela|
      expect(consultas_por_pessoa(de_quatro_blocos, de_um_bloco, tabela, a_mais)).to be < quase_nada
    end
    # Toda pessoa desta lista deixa de ser cliente: uma consulta do card ganho para cada, sob a trava dela
    # (Relacionamentos::Trazer::CampoQueVolta#desmarcar_cliente), além da do bloco.
    expect(consultas_por_pessoa(de_quatro_blocos, de_um_bloco, 'crm_cards', a_mais)).to be_within(0.1).of(1)
    # Todos os campos voltaram: a medida é de um Desfazer que fez o trabalho inteiro.
    expect(Relacionamentos::CampoPreenchido.pendentes.count).to eq(0)
  end
end
