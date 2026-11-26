# OS PLANOS ANUAIS no comparativo de Seguro Viagem (#3223): depois dos cartões de viagem única, uma seção com título e
# uma linha de leigo ("Planos anuais: valem para todas as viagens do ano, cada uma com até 30 dias."), e os cartões dos
# anuais, sem rótulo, no mesmo tamanho dos outros (`Comparacao#fileiras`). O título e a 1ª fileira que não cabem no
# resto da folha vão juntos para a seguinte.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Anuais
  include Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Desenho

  Comparacao = Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Comparacao
  TITULO_DOS_ANUAIS = 'Se você viaja mais vezes no ano'.freeze
  LINHA_DOS_ANUAIS = { size: 10.5, leading: 2 }.freeze
  # O respiro antes do título, do título à linha de leigo e da linha aos cartões.
  ANTES_DOS_ANUAIS = 12
  ATE_A_LINHA = 30
  ATE_OS_CARTOES = 16
  TOPO_DA_FOLHA = 44

  private

  # `ultima`: onde ficou a última fileira de viagem única. Devolve onde ficou a última fileira dos anuais.
  def secao_dos_anuais(ultima)
    topo = ultima[:fim] + Comparacao::ENTRE_FILEIRAS + ANTES_DOS_ANUAIS
    if topo + altura_do_titulo_dos_anuais + altura_do_cartao > Comparacao::FIM_DA_AREA
      @doc.start_new_page
      topo = TOPO_DA_FOLHA
    end
    escrever(TITULO_DOS_ANUAIS, at: [MARGEM, topo], largura: largura_util, size: 20, style: :bold, cor: :marinho)
    escrever(linha_dos_anuais, at: [MARGEM, topo + ATE_A_LINHA], largura: largura_util, cor: :suave, **LINHA_DOS_ANUAIS)
    fileiras(anuais.map { |plano| [plano, nil] }, topo + altura_do_titulo_dos_anuais)
  end

  def altura_do_titulo_dos_anuais
    ATE_A_LINHA + altura_de(linha_dos_anuais, largura: largura_util, **LINHA_DOS_ANUAIS) + ATE_OS_CARTOES
  end

  # Dias diferentes entre os planos: "até 30 ou 60 dias"; sem os dias, só a primeira parte.
  def linha_dos_anuais
    dias = anuais.filter_map { |plano| plano['dias_por_viagem'] }.uniq.sort
    return 'Planos anuais: valem para todas as viagens do ano.' if dias.empty?

    lista = dias.to_sentence(words_connector: ', ', two_words_connector: ' ou ', last_word_connector: ' ou ')
    "Planos anuais: valem para todas as viagens do ano, cada uma com até #{lista} dias."
  end
end
