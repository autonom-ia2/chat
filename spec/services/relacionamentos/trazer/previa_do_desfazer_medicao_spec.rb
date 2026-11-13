require 'rails_helper'

# #2896 (fatia 3) — MEDIÇÃO, TEMPORÁRIA: quanto custa a prévia do "Desfazer" numa lista grande. Este arquivo sai do PR
# assim que o número for lido no log da CI; o que fica é o spec pequeno que trava as consultas por bloco.
#
# Dois formatos de lista, que são os dois extremos:
# - "novas": toda linha criou uma pessoa (a prévia confere, bloco a bloco, quem sai e quem fica);
# - "completadas": toda linha completou uma pessoa que a conta já tinha, com três campos (a prévia confere campo a campo).
RSpec.describe Relacionamentos::Trazer::PreviaDoDesfazer, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:importacao) { lista_trazida_vazia(account, user) }

  def previa_medida(cenario, linhas)
    atualizar_estatisticas
    medida = medir_consultas { described_class.new(importacao.reload).call }
    puts "[medicao-desfazer] cenario=#{cenario} linhas=#{linhas} consultas=#{medida.consultas} segundos=#{medida.segundos.round(3)}"
    medida.por_tabela.sort_by { |_tabela, total| -total[:segundos] }.each do |tabela, total|
      puts "[medicao-desfazer]   tabela=#{tabela} consultas=#{total[:consultas]} segundos=#{total[:segundos].round(3)}"
    end
    medida
  end

  [1_500, 5_000, 50_000].each do |linhas|
    it "mede a prévia de uma lista com #{linhas} pessoas novas" do
      recusaram = por_pessoas_criadas(importacao, linhas)

      medida = previa_medida('novas', linhas)

      expect(medida.resultado).to eq(tira: linhas - recusaram, ficam: recusaram, devolve: 0)
    end

    it "mede a prévia de uma lista com #{linhas} pessoas completadas, três campos cada" do
      por_pessoas_completadas(importacao, linhas)

      medida = previa_medida('completadas', linhas)

      expect(medida.resultado).to eq(tira: 0, ficam: 0, devolve: linhas)
    end
  end

  it 'mede a lista do spec permanente: 1.000 novas e 500 completadas' do
    recusaram = por_pessoas_criadas(importacao, 1_000)
    por_pessoas_completadas(importacao, 500)

    medida = previa_medida('mista', 1_500)

    expect(medida.resultado).to eq(tira: 1_000 - recusaram, ficam: recusaram, devolve: 500)
  end
end
