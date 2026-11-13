require 'rails_helper'

# #2896 (fatia 3) — os dois piores casos da prévia do "Desfazer", medidos a cada rodada da CI, numa lista de 50 mil
# linhas (o teto de linhas de uma planilha CSV): a de 50 mil pessoas que a conta já tinha, com três campos preenchidos em
# cada uma (150 mil campos), e a de 50 mil pessoas que a lista criou.
#
# A prévia roda dentro de um pedido da tela, que tem prazo. O tempo sai impresso numa linha que começa com
# MEDICAO_PREVIA_50K (ou MEDICAO_PREVIA_50K_CRIADAS), para ser lido no log da rodada; ele não é cobrado aqui, porque
# varia com a máquina. O que é cobrado é o número de consultas, que não varia: um número fixo por bloco
# (spec/services/relacionamentos/trazer/previa_do_desfazer_consultas_spec.rb diz de onde ele vem).
RSpec.describe Relacionamentos::Trazer::PreviaDoDesfazer, :aggregate_failures do
  include ListaTrazidaGrandeHelpers

  let(:pessoas) { 50_000 }
  let(:campos_por_pessoa) { 3 }
  let(:por_bloco_de_campos) { 7 }
  let(:por_bloco_de_pessoas_criadas) { 25 }
  # O que a prévia consulta uma vez só, fora dos blocos (a conta, as pessoas que a lista criou, o bloco que acha o fim).
  let(:folga) { 10 }

  it 'mede a prévia de uma lista com 50 mil pessoas completadas, três campos cada' do
    conta = create(:account)
    importacao = lista_trazida_vazia(conta, create(:user, account: conta, role: :administrator))
    por_pessoas_completadas(importacao, pessoas)
    atualizar_estatisticas
    campos = pessoas * campos_por_pessoa
    blocos = campos.fdiv(Relacionamentos::Trazer::CamposDaLista::BLOCO_DA_PREVIA).ceil

    medida = medir_consultas { described_class.new(importacao.reload).call }

    puts "MEDICAO_PREVIA_50K completadas=#{pessoas} campos=#{campos} blocos=#{blocos} consultas=#{medida.consultas} " \
         "segundos=#{medida.segundos.round(3)}"
    expect(medida.resultado).to eq(tira: 0, ficam: 0, devolve: pessoas)
    expect(medida.consultas).to be_between(blocos * por_bloco_de_campos, (blocos * por_bloco_de_campos) + folga)
  end

  it 'mede a prévia de uma lista com 50 mil pessoas criadas' do
    conta = create(:account)
    importacao = lista_trazida_vazia(conta, create(:user, account: conta, role: :administrator))
    recusaram = por_pessoas_criadas(importacao, pessoas)
    atualizar_estatisticas
    blocos = pessoas.fdiv(Relacionamentos::Trazer::QuemFica::BLOCO).ceil

    medida = medir_consultas { described_class.new(importacao.reload).call }

    puts "MEDICAO_PREVIA_50K_CRIADAS criadas=#{pessoas} blocos=#{blocos} consultas=#{medida.consultas} segundos=#{medida.segundos.round(3)}"
    expect(medida.resultado).to eq(tira: pessoas - recusaram, ficam: recusaram, devolve: 0)
    expect(medida.consultas).to be_between(blocos * por_bloco_de_pessoas_criadas, (blocos * por_bloco_de_pessoas_criadas) + folga)
  end
end
