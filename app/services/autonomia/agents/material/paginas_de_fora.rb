# #1426 (tema 4b) — o que ficou de fora da leitura de um PDF (Source#paginas_de_fora, gravado pelo Processors::Pdf),
# em números e motivos para o cartão. Conta de código, sobre números que o próprio processador anotou:
# - limite: páginas além do teto de leitura de texto (300) ou de leitura de imagem (30);
# - grande: página grande demais para ler como imagem;
# - tempo: o prazo da leitura acabou;
# - falha: a página não pôde ser lida.
# `lidas`/`total` só quando o total é conhecido (leituras feitas depois do #1426 PR 2); sem ele, o cartão fala sem números.
module Autonomia::Agents::Material::PaginasDeFora
  module_function

  LISTAS = { 'grande' => 'ocr_grandes', 'tempo' => 'ocr_prazo', 'falha' => 'ocr_falhou' }.freeze

  def resumo(fora)
    alem = fora['texto_alem_do_teto'].to_i + fora['ocr_alem_do_teto'].to_i
    motivos = (alem.positive? ? ['limite'] : []) + LISTAS.select { |_, chave| Array(fora[chave]).any? }.keys
    total = fora['paginas_total'].to_i
    return { 'motivos' => motivos } unless total.positive?

    de_fora = alem + LISTAS.values.sum { |chave| Array(fora[chave]).size }
    { 'motivos' => motivos, 'total' => total, 'lidas' => (total - de_fora).clamp(0, total) }
  end
end
