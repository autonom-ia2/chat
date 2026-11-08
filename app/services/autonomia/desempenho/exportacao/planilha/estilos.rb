# Estilos da planilha do painel de desempenho (#2226), no padrão da planilha de referência: título branco sobre
# azul-escuro, contexto em faixa clara, cabeçalho azul-escuro com texto branco, rótulo do resumo em azul-claro, nota
# amarela e os formatos de número (milhar, %, dinheiro, data). Cada combinação vira um estilo do Excel uma vez só.
class Autonomia::Desempenho::Exportacao::Planilha::Estilos
  FONTE = 'Calibri'.freeze
  NAVY = 'FF0D2344'.freeze
  TINTA = 'FF1C2024'.freeze
  APOIO = 'FF60646C'.freeze
  BORDA = 'FFE8E8EC'.freeze
  FORMATOS = {
    inteiro: '#,##0', pct: '0.0%', decimal: '0.0', data_hora: 'dd/mm/yyyy hh:mm', dia: 'dd/mm/yyyy', segundos: '0\\ \\s'
  }.freeze

  def initialize(workbook, moeda: 'R$')
    @styles = workbook.styles
    @styles.fonts.first.name = FONTE
    @moeda = moeda
    @cache = {}
  end

  def titulo
    @titulo ||= @styles.add_style(font_name: FONTE, sz: 16, b: true, fg_color: 'FFFFFFFF', bg_color: NAVY,
                                  alignment: { vertical: :center })
  end

  def contexto
    @contexto ||= @styles.add_style(font_name: FONTE, sz: 10, fg_color: APOIO, bg_color: 'FFF4F7FA', alignment: { vertical: :center })
  end

  def cabecalho
    @cabecalho ||= @styles.add_style(font_name: FONTE, sz: 10, b: true, fg_color: 'FFFFFFFF', bg_color: NAVY,
                                     alignment: { vertical: :center, wrap_text: true }, border: borda)
  end

  def secao
    @secao ||= @styles.add_style(font_name: FONTE, sz: 12, b: true, fg_color: TINTA)
  end

  def rotulo
    @rotulo ||= @styles.add_style(font_name: FONTE, sz: 10, b: true, fg_color: TINTA, bg_color: 'FFD9EAF7',
                                  alignment: { vertical: :center, wrap_text: true }, border: borda)
  end

  def nota
    @nota ||= @styles.add_style(font_name: FONTE, sz: 10, fg_color: 'FF5F4500', bg_color: 'FFFFF2CC',
                                alignment: { vertical: :top, wrap_text: true })
  end

  def texto_longo
    @texto_longo ||= @styles.add_style(font_name: FONTE, sz: 10, fg_color: TINTA, alignment: { vertical: :top, wrap_text: true })
  end

  def valor(tipo)
    @cache[[:valor, tipo]] ||= @styles.add_style(
      { font_name: FONTE, sz: 13, b: true, fg_color: TINTA, alignment: { horizontal: :left, vertical: :center } }.merge(formato(tipo))
    )
  end

  def celula(tipo, negrito: false, fundo: nil)
    @cache[[tipo, negrito, fundo]] ||= @styles.add_style(
      { font_name: FONTE, sz: 10, b: negrito, fg_color: TINTA, border: borda,
        alignment: { vertical: :center, horizontal: alinhamento(tipo), wrap_text: tipo == :texto_longo } }
        .merge(fundo ? { bg_color: fundo } : {}).merge(formato(tipo))
    )
  end

  # Fundo azul-claro e negrito da linha de total.
  def total(tipo)
    celula(tipo, negrito: true, fundo: 'FFE6F4FE')
  end

  private

  def borda
    { style: :thin, color: BORDA, edges: [:bottom] }
  end

  def formato(tipo)
    return { format_code: "#{literal(@moeda)} #,##0.00" } if tipo == :dinheiro

    FORMATOS.key?(tipo) ? { format_code: FORMATOS[tipo] } : {}
  end

  # Texto fixo num formato de número: cada caractere com barra invertida (o caxlsx não escapa aspas no XML).
  def literal(texto)
    texto.to_s.chars.map { |caractere| "\\#{caractere}" }.join
  end

  def alinhamento(tipo)
    %i[texto texto_longo].include?(tipo) ? :left : :right
  end
end
