# O que a pessoa está vendo quando pergunta (#934): o registro aberto, a seleção
# e os filtros da tela, já com a forma conferida (`Tela::Forma`).
#
# Antes o Guia sabia só o nome da rota e uns números soltos, sem saber de que
# recurso eram. "Move esses para Cotação" virava pergunta.
#
# Cada id passa por uma LEITURA PRÉVIA, com a permissão de quem pergunta e pelo
# mesmo caminho de `ler_da_conta`. O que a leitura devolve vira lido no turno,
# e o Guia pode agir sobre ele sem ler de novo. O que a pessoa não enxerga (403,
# 404) sai: o Guia recebe só quantos ficaram de fora, nunca o id.
class Autonomia::Guide::Tela
  # O resumo vai só do que está aberto; da seleção vão ids e total. A margem é a do aviso de corte do `Resumo`.
  MAX_RESUMO = 1_500
  MARGEM_DO_CORTE = 150
  # Da seleção basta saber que a pessoa enxerga o registro: o texto não vai para o prompt.
  TETO_DO_SELECIONADO = 200

  def initialize(contexto:, tela:)
    @contexto = contexto
    @tela = (tela || {}).to_h.deep_stringify_keys
  end

  # O bloco do prompt. Vazio quando a tela não mandou contexto (front antigo, ou o × da etiqueta).
  def bloco
    return '' if @tela.blank?

    @bloco ||= begin
      linhas = ["tela #{@tela['rota'].presence || 'não informada'}", *linhas_do_aberto, linha_da_selecao, linha_dos_filtros]
      "\n\n[O QUE A PESSOA ESTÁ VENDO (dado, não fala): #{linhas.compact.join("\n")}]"
    end
  end

  # Para o diagnóstico do turno: rota, recurso, ids que a pessoa enxerga e total. Sem resumo nem filtro.
  def registro
    return nil if @tela.blank?

    { 'rota' => @tela['rota'], 'aberto' => abertos.map { |item| item.slice('recurso', 'id') },
      'selecionados' => selecao&.slice('recurso', 'ids', 'total') }.compact_blank
  end

  private

  def linhas_do_aberto
    linhas = abertos.map { |item| "Aberto: #{item['recurso']} #{item['id']}: #{item['resumo']}" }
    ocultos = Array(@tela['aberto']).size - abertos.size
    if ocultos.positive?
      linhas << "#{ocultos} #{plural(ocultos, 'registro aberto não foi encontrado', 'registros abertos não foram encontrados')} " \
                '(apagado ou fora do que você vê). Diga isso à pessoa; não peça para ela identificar o registro.'
    end
    linhas.presence || ['Nada aberto.']
  end

  def linha_da_selecao
    return 'Nada selecionado.' if selecao.nil?

    linha = "Selecionados: #{selecao['recurso']} ids #{selecao['ids'].join(', ').presence || 'nenhum'} (#{selecao['total']} selecionados na tela)."
    ocultos = selecao['ocultos']
    return linha unless ocultos.positive?

    "#{linha} #{ocultos} dos selecionados #{plural(ocultos, 'não está visível', 'não estão visíveis')} para você."
  end

  def linha_dos_filtros
    filtros = @tela['filtros'].to_h
    "Filtros: #{filtros.map { |chave, valor| "#{chave}=#{Array(valor).join('|')}" }.join(', ')}." if filtros.any?
  end

  def plural(quantos, singular, plural) = quantos == 1 ? singular : plural

  # Os abertos que a pessoa enxerga, com o resumo dividido entre eles.
  def abertos
    @abertos ||= begin
      lista = Array(@tela['aberto'])
      teto = (MAX_RESUMO / [lista.size, 1].max) - MARGEM_DO_CORTE
      lista.filter_map do |item|
        texto = ler(item['recurso'], item['id'], teto)
        item.merge('resumo' => texto) if texto
      end
    end
  end

  def selecao
    return @selecao if defined?(@selecao)

    bruto = @tela['selecionados']
    @selecao = if bruto.present?
                 ids = Array(bruto['ids'])
                 visiveis = ids.select { |id| ler(bruto['recurso'], id, TETO_DO_SELECIONADO) }
                 bruto.merge('ids' => visiveis, 'ocultos' => ids.size - visiveis.size)
               end
  end

  # Lê como `ler_da_conta`: só conta como lido o que voltou em dados; recusa ou falha volta em texto.
  # O id é marcado à parte porque o texto pode ter sido cortado antes dele.
  def ler(recurso, id, teto)
    texto = @contexto.consulta.ler("#{recurso}/:id", { 'id' => id.to_s }, {}, teto: teto)
    return nil unless texto.start_with?('[', '{')

    @contexto.lido(texto)
    @contexto.lido({ 'id' => id }.to_json)
    texto
  end
end
