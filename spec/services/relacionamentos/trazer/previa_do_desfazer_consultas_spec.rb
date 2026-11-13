require 'rails_helper'

# #2896 (fatia 3) — a prévia do "Desfazer" lê a lista em blocos de Relacionamentos::Trazer::QuemFica::BLOCO, e cada bloco
# custa um número fixo de consultas. A prévia roda dentro de um pedido da tela, então o que não pode acontecer é uma
# consulta por pessoa (ou por campo) entrar no laço: uma lista de 50 mil linhas tem 100 blocos de pessoas.
#
# O custo por bloco sai da diferença entre duas listas, uma com um bloco e outra com mais: o que a prévia consulta uma vez
# só (a conta, o bloco vazio que acha o fim) some na conta. Quem acrescentar um lugar onde a pessoa pode aparecer
# (QuemFica#onde_aparece) sobe o número aqui, de propósito.
RSpec.describe Relacionamentos::Trazer::PreviaDoDesfazer, :aggregate_failures do
  let(:bloco) { Relacionamentos::Trazer::QuemFica::BLOCO }
  # Pegar o bloco, ver quem ainda existe, as listas já desfeitas e os 19 lugares onde a pessoa pode aparecer.
  let(:por_bloco_de_pessoas_criadas) { 22 }
  # Pegar o bloco, carregar os campos, as pessoas, quem ganhou card desde a lista e os 4 lugares de quem foi procurado.
  let(:por_bloco_de_campos) { 8 }
  # Cada pessoa completada tem três campos anotados (ListaTrazidaGrandeHelpers#por_pessoas_completadas).
  let(:campos_por_pessoa) { 3 }

  # Uma lista numa conta só dela: quem está em outra lista da mesma conta fica, e mudaria a conta.
  def consultas_da_previa
    conta = create(:account)
    importacao = lista_trazida_vazia(conta, create(:user, account: conta, role: :administrator))
    esperado = yield(importacao)
    atualizar_estatisticas
    medida = medir_consultas { described_class.new(importacao.reload).call }
    expect(medida.resultado).to eq(esperado)
    medida.consultas
  end

  it 'faz 22 consultas por bloco de pessoas que a lista criou' do
    de_um_bloco = consultas_da_previa do |importacao|
      recusaram = por_pessoas_criadas(importacao, bloco)
      { tira: bloco - recusaram, ficam: recusaram, devolve: 0 }
    end
    de_tres_blocos = consultas_da_previa do |importacao|
      recusaram = por_pessoas_criadas(importacao, 3 * bloco)
      { tira: (3 * bloco) - recusaram, ficam: recusaram, devolve: 0 }
    end

    expect(de_tres_blocos - de_um_bloco).to eq(2 * por_bloco_de_pessoas_criadas)
  end

  it 'faz 8 consultas por bloco de campos que a lista preencheu em quem a conta já tinha' do
    de_um_bloco = consultas_da_previa do |importacao|
      por_pessoas_completadas(importacao, bloco / campos_por_pessoa)
      { tira: 0, ficam: 0, devolve: bloco / campos_por_pessoa }
    end
    de_quatro_blocos = consultas_da_previa do |importacao|
      por_pessoas_completadas(importacao, 4 * bloco / campos_por_pessoa)
      { tira: 0, ficam: 0, devolve: 4 * bloco / campos_por_pessoa }
    end

    expect(de_quatro_blocos - de_um_bloco).to eq(3 * por_bloco_de_campos)
  end
end
