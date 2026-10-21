# Estilos das planilhas dos relatórios (#1960), no visual da plataforma: título grande, contexto em cinza, cabeçalho
# azul-escuro com texto branco, linhas zebradas com borda fina, dinheiro com milhar e datas legíveis. Cada combinação
# vira um estilo do Excel uma vez só (cache), e a planilha fica leve com milhares de linhas.
class Relatorios::PlanilhaEstilos
  FONT = 'Calibri'.freeze
  INK = 'FF0F172A'.freeze
  MUTED = 'FF64748B'.freeze
  HEADER_FILL = 'FF0D2344'.freeze
  ZEBRA_FILL = 'FFF8FAFC'.freeze
  BORDER = 'FFE2E8F0'.freeze
  FORMATS = { inteiro: '#,##0', dinheiro: '#,##0.00', data: 'dd/mm/yyyy hh:mm', dia: 'dd/mm/yyyy' }.freeze

  def initialize(workbook)
    @styles = workbook.styles
    @styles.fonts.first.name = FONT
    @cache = {}
  end

  def titulo
    @titulo ||= @styles.add_style(font_name: FONT, sz: 16, b: true, fg_color: INK)
  end

  def contexto
    @contexto ||= @styles.add_style(font_name: FONT, sz: 10, fg_color: MUTED)
  end

  def cabecalho
    @cabecalho ||= @styles.add_style(font_name: FONT, sz: 10, b: true, fg_color: 'FFFFFFFF', bg_color: HEADER_FILL,
                                     alignment: { vertical: :center, wrap_text: true }, border: borda)
  end

  def rotulo
    @rotulo ||= @styles.add_style(font_name: FONT, sz: 11, fg_color: MUTED, alignment: { vertical: :center })
  end

  def valor_de_resumo(tipo)
    @cache[[:resumo, tipo]] ||= @styles.add_style(
      { font_name: FONT, sz: 13, b: true, fg_color: INK, alignment: { horizontal: :left, vertical: :center } }.merge(formato(tipo))
    )
  end

  def celula(tipo, zebra:)
    @cache[[tipo, zebra]] ||= @styles.add_style(
      { font_name: FONT, sz: 10, fg_color: INK, border: borda, alignment: { vertical: :center, horizontal: alinhamento(tipo) } }
        .merge(zebra ? { bg_color: ZEBRA_FILL } : {}).merge(formato(tipo))
    )
  end

  private

  def borda
    { style: :thin, color: BORDER, edges: [:bottom] }
  end

  def formato(tipo)
    FORMATS.key?(tipo) ? { format_code: FORMATS[tipo] } : {}
  end

  def alinhamento(tipo)
    %i[inteiro dinheiro].include?(tipo) ? :right : :left
  end
end
