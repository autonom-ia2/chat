require 'rails_helper'

# #2896 (fatia 3) — a prévia do "Desfazer" lê a lista em blocos, e cada bloco custa um número fixo de consultas: as
# pessoas que a lista criou em blocos de Relacionamentos::Trazer::QuemFica::BLOCO, e os campos que ela preencheu em quem
# a conta já tinha em blocos de Relacionamentos::Trazer::CamposDaLista::BLOCO_DA_PREVIA. A prévia roda dentro de um
# pedido da tela, que tem prazo, então o que não pode acontecer é uma consulta por pessoa (ou por campo) entrar no laço.
#
# O custo por bloco sai da diferença entre duas listas, uma com um bloco e outra com mais: o que a prévia consulta uma vez
# só (a conta, o bloco vazio que acha o fim) some na conta. Quem acrescentar um lugar onde a pessoa pode aparecer
# (QuemFica#onde_aparece) sobe o número aqui, de propósito.
RSpec.describe Relacionamentos::Trazer::PreviaDoDesfazer, :aggregate_failures do
  let(:bloco_de_pessoas) { Relacionamentos::Trazer::QuemFica::BLOCO }
  let(:bloco_de_campos) { Relacionamentos::Trazer::CamposDaLista::BLOCO_DA_PREVIA }
  # Pegar o bloco, ver quem ainda existe, as listas já desfeitas e os 19 lugares onde a pessoa pode aparecer.
  let(:por_bloco_de_pessoas_criadas) { 22 }
  # Carregar os campos do bloco, as pessoas, quem ganhou card desde a lista e os 4 lugares de quem foi procurado.
  let(:por_bloco_de_campos) { 7 }
  # Cada pessoa completada tem três campos anotados (ListaTrazidaGrandeHelpers#por_pessoas_completadas).
  let(:campos_por_pessoa) { 3 }

  # Uma lista numa conta só dela: quem está em outra lista da mesma conta fica, e mudaria a conta.
  def medida_da_previa
    conta = create(:account)
    importacao = lista_trazida_vazia(conta, create(:user, account: conta, role: :administrator))
    esperado = yield(importacao)
    atualizar_estatisticas
    medida = medir_consultas { described_class.new(importacao.reload).call }
    expect(medida.resultado).to eq(esperado)
    medida
  end

  it 'faz 22 consultas por bloco de pessoas que a lista criou' do
    de_um_bloco = medida_da_previa do |importacao|
      recusaram = por_pessoas_criadas(importacao, bloco_de_pessoas)
      { tira: bloco_de_pessoas - recusaram, ficam: recusaram, devolve: 0 }
    end
    de_tres_blocos = medida_da_previa do |importacao|
      recusaram = por_pessoas_criadas(importacao, 3 * bloco_de_pessoas)
      { tira: (3 * bloco_de_pessoas) - recusaram, ficam: recusaram, devolve: 0 }
    end

    expect(de_tres_blocos.consultas - de_um_bloco.consultas).to eq(2 * por_bloco_de_pessoas_criadas)
  end

  # A lista grande é a de 5 mil pessoas que a conta já tinha, com três campos cada: 15 mil campos, em 8 blocos. O tempo
  # do pior caso é medido em spec/services/relacionamentos/trazer/previa_do_desfazer_medicao_spec.rb.
  it 'faz 7 consultas por bloco de campos que a lista preencheu em quem a conta já tinha' do
    pessoas_de_um_bloco = bloco_de_campos / campos_por_pessoa
    pessoas_da_lista_grande = 5_000
    blocos_da_lista_grande = (pessoas_da_lista_grande * campos_por_pessoa).fdiv(bloco_de_campos).ceil
    de_um_bloco = medida_da_previa do |importacao|
      por_pessoas_completadas(importacao, pessoas_de_um_bloco)
      { tira: 0, ficam: 0, devolve: pessoas_de_um_bloco }
    end
    da_lista_grande = medida_da_previa do |importacao|
      por_pessoas_completadas(importacao, pessoas_da_lista_grande)
      { tira: 0, ficam: 0, devolve: pessoas_da_lista_grande }
    end

    expect(da_lista_grande.consultas - de_um_bloco.consultas).to eq((blocos_da_lista_grande - 1) * por_bloco_de_campos)
  end
end
