require 'rails_helper'

# #2896 (fatia 3) — o "Desfazer" lê a lista em blocos, como a prévia (previa_do_desfazer_consultas_spec.rb). O que não
# pode acontecer é uma rodada de consultas por pessoa: conferir de novo, uma a uma, todos os lugares onde a pessoa pode
# aparecer (umas 20 consultas por pessoa, 100 mil numa lista de 5 mil), ou perguntar de novo pelo card ganho e pela
# procura a cada campo que volta.
#
# A medida sai da diferença entre duas listas, uma com um bloco e outra com mais, dividida pelas pessoas a mais: o que
# o Desfazer consulta uma vez só some na conta. O teto é folgado de propósito (uma consulta por fatia ou por bloco dá
# centésimos por pessoa; uma por pessoa dá 1): o que ele pega é a consulta que voltou para dentro do laço.
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

  it 'confere quem fica de fatia em fatia, e não pessoa a pessoa, antes de apagar; só a conversa é pessoa a pessoa' do
    # O apagar em lote sai de cena: o que se mede é o que o Desfazer consulta para decidir, não o que apagar custa.
    allow(Contacts::BulkDeleteService).to receive(:new).and_return(instance_double(Contacts::BulkDeleteService, perform: nil))
    de_um_bloco = medida_do_desfazer { |importacao| por_pessoas_criadas(importacao, bloco) }
    de_tres_blocos = medida_do_desfazer { |importacao| por_pessoas_criadas(importacao, 3 * bloco) }
    a_mais = 2 * bloco

    %w[notes crm_cards taggings campaign_recipients carteira_apolices].each do |tabela|
      expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, tabela, a_mais)).to be < quase_nada
    end
    expect(consultas_por_pessoa(de_tres_blocos, de_um_bloco, 'conversations', a_mais)).to be <= 1.1
    expect((de_tres_blocos.consultas - de_um_bloco.consultas).fdiv(a_mais)).to be < 3
  end

  it 'lê o card ganho e a procura uma vez por bloco de campos, e não de novo por pessoa, ao devolver' do
    pessoas = bloco / campos_por_pessoa
    de_um_bloco = medida_do_desfazer { |importacao| por_pessoas_completadas(importacao, pessoas) }
    de_quatro_blocos = medida_do_desfazer { |importacao| por_pessoas_completadas(importacao, 4 * pessoas) }
    a_mais = 3 * pessoas

    %w[crm_cards conversations campaign_recipients email_campaign_recipients whatsapp_api_campaign_recipients].each do |tabela|
      expect(consultas_por_pessoa(de_quatro_blocos, de_um_bloco, tabela, a_mais)).to be < quase_nada
    end
    # Todos os campos voltaram: a medida é de um Desfazer que fez o trabalho inteiro.
    expect(Relacionamentos::CampoPreenchido.pendentes.count).to eq(0)
  end
end
