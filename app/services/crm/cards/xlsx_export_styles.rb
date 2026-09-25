# Estilos da planilha da Lista do CRM (#722). Cabeçalho escuro com texto branco, linhas
# zebradas com borda fina, valor com milhar, datas legíveis e status/prioridade com cor,
# como selos. Cada combinação (coluna x linha par/ímpar) vira um estilo do Excel uma vez
# só e é reaproveitada: a planilha fica leve mesmo com milhares de linhas.
class Crm::Cards::XlsxExportStyles
  FONT = 'Calibri'.freeze
  INK = 'FF0F172A'.freeze
  MUTED = 'FF64748B'.freeze
  HEADER_FILL = 'FF1E293B'.freeze
  ZEBRA_FILL = 'FFF8FAFC'.freeze
  BORDER = 'FFE2E8F0'.freeze
  VALUE_FORMAT = '#,##0.00'.freeze
  DATE_FORMAT = 'dd/mm/yyyy hh:mm'.freeze

  # [texto, fundo] de cada valor, no espírito dos selos da tela.
  STATUS_COLORS = {
    'open' => %w[FF1D4ED8 FFDBEAFE], 'won' => %w[FF15803D FFDCFCE7],
    'lost' => %w[FFB91C1C FFFEE2E2], 'archived' => %w[FF475569 FFF1F5F9]
  }.freeze
  PRIORITY_COLORS = {
    'urgent' => %w[FFB91C1C FFFEE2E2], 'high' => %w[FFC2410C FFFFEDD5],
    'medium' => ['FF334155', nil], 'low' => ['FF64748B', nil]
  }.freeze

  def initialize(workbook)
    @styles = workbook.styles
    # Fonte padrão da pasta (célula vazia ou digitada depois): Calibri, não o Arial do caxlsx.
    @styles.fonts.first.name = FONT
    @cache = {}
  end

  def title
    @title ||= @styles.add_style(font_name: FONT, sz: 16, b: true, fg_color: INK)
  end

  def subtitle
    @subtitle ||= @styles.add_style(font_name: FONT, sz: 10, fg_color: MUTED)
  end

  def header
    @header ||= @styles.add_style(
      font_name: FONT, sz: 11, b: true, fg_color: 'FFFFFFFF', bg_color: HEADER_FILL,
      alignment: { vertical: :center, horizontal: :left, indent: 1 }
    )
  end

  # kind: :text, :value, :date, :status ou :priority. `raw` é o valor do enum, para a cor.
  def cell(kind, zebra:, raw: nil)
    colors = palette(kind, raw)
    @cache[[kind, zebra, colors]] ||= @styles.add_style(cell_options(kind, zebra, colors))
  end

  private

  def palette(kind, raw)
    return STATUS_COLORS[raw] if kind == :status
    return PRIORITY_COLORS[raw] if kind == :priority

    nil
  end

  def cell_options(kind, zebra, colors)
    {
      font_name: FONT, sz: 11, fg_color: colors&.first || INK,
      border: { style: :thin, color: BORDER, edges: [:bottom] },
      alignment: { vertical: :center, horizontal: horizontal(kind), indent: kind == :value ? 0 : 1 }
    }.merge(fill_options(zebra, colors), number_format(kind))
  end

  # O selo (status, prioridade) leva a própria cor de fundo e fica em negrito; sem cor
  # própria, vale o zebrado da linha.
  def fill_options(zebra, colors)
    options = colors ? { b: true } : {}
    fill = colors&.last || (ZEBRA_FILL if zebra)
    fill ? options.merge(bg_color: fill) : options
  end

  def horizontal(kind)
    { value: :right, date: :center, status: :center, priority: :center }.fetch(kind, :left)
  end

  def number_format(kind)
    return { format_code: VALUE_FORMAT } if kind == :value
    return { format_code: DATE_FORMAT } if kind == :date

    {}
  end
end
