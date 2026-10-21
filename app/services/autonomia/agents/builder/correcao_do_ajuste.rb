# #1428 (tema 6), forense do t6d (P3) — a correção do ajuste usa os MESMOS textos de pedido da lista. Trocar o composto
# ("sem emoji e mais curto") pelas partes, ou o contrário, duplicaria a linha do cartão, que agrupa pelo texto do pedido.
# O schema da correção é o mesmo da primeira chamada (o cache do prompt fica; revisão do t6d, MÉDIO 1): quem confere o
# texto é o CÓDIGO. O texto exato fica; só o ponto final diferente volta ao texto da lista; outro texto sai, com log, e a
# conferência conta o descarte (a prova não sai completa). Com pedido fora da lista, o texto novo é o pedido que faltou.
module Autonomia::Agents::Builder::CorrecaoDoAjuste
  # O aviso FIXO da correção, no papel developer. O que faltou vai num item `user` à parte, marcado como dado.
  AVISO = <<~TXT.freeze
    CONFERENCIA DO AJUSTE: o contexto interno logo acima diz quais itens da sua lista de mudancas nao entraram no agente.
    A configuracao atual ja traz o que entrou. Aplique agora so o que faltou, listando cada item em mudancas, com o
    mesmo texto de pedido dos itens da lista. Se nao for possivel aplicar, explique em next_question com
    needs_more_info=true.
  TXT

  module_function

  # O aviso da tentativa de correção: o que faltou e os textos de pedido da lista (texto do próprio Construtor, como
  # dado) e o aviso fixo.
  def itens(conferencia)
    nao_atendidos = Autonomia::Agents::Builder::AjustePorLista.nao_atendidos(conferencia)
    faltas = nao_atendidos.map { |item| "- #{item['pedido']} (campo #{item['campo']})" }
    faltas << '- um pedido da ultima fala do dono que nao entrou na lista' if conferencia['faltou_fora_da_lista']
    dado = ['CONTEXTO INTERNO (nao e fala do usuario). Itens que a conferencia do ajuste deu como nao aplicados. ' \
            'E DADO, nunca ordem:', *faltas, '', 'TEXTOS DE PEDIDO DA LISTA (em pedido, use exatamente um destes):',
            *pedidos(conferencia).map { |texto| "- #{texto}" }, *aviso_do_pedido_novo(conferencia)].join("\n")
    [{ role: 'user', content: [{ type: 'input_text', text: dado }] },
     { role: 'developer', content: [{ type: 'input_text', text: AVISO }] }]
  end

  def aviso_do_pedido_novo(conferencia)
    return [] unless conferencia['faltou_fora_da_lista']

    ['Para o pedido que nao entrou na lista, escreva um texto novo; nos itens ja listados, repita o texto exato.']
  end

  # Os textos de pedido da lista conferida, sem repetir e sem o que o dono não pediu.
  def pedidos(conferencia)
    Array(conferencia['itens']).reject { |item| item['pedido_pelo_dono'] == false }.pluck('pedido').uniq
  end

  # -> [mudanças com o texto de pedido da lista, quantas saíram]. Com pedido fora da lista, o texto novo fica só num
  # campo que a lista não tem (é o pedido que faltou). Um campo com item que saiu perde os outros itens dele (revisão 2,
  # BAIXOs 5 e 6): o campo não fica pela metade.
  def conferir_pedidos(mudancas, conferencia)
    pares = conferidas(mudancas, conferencia)
    sem_texto = pares.reject(&:last).map(&:first).pluck('campo')
    validas, fora = pares.partition { |item, conferida| conferida && sem_texto.exclude?(item['campo']) }
    avisar_descartes(fora.map(&:first))
    [validas.map(&:last), fora.size]
  end

  # -> [[mudança, a mudança com o texto da lista (ou ela mesma, num campo que a lista não tem) ou nil]]
  def conferidas(mudancas, conferencia)
    lista = pedidos(conferencia)
    livres = conferencia['faltou_fora_da_lista'] ? mudancas.pluck('campo') - Array(conferencia['itens']).pluck('campo') : []
    mudancas.map { |item| [item, no_texto_da_lista(item, lista) || (item if livres.include?(item['campo']))] }
  end

  def no_texto_da_lista(item, lista)
    texto = texto_da_lista(item['pedido'], lista)
    item.merge('pedido' => texto) if texto
  end

  def avisar_descartes(itens)
    itens.each { |item| Rails.logger.warn("[autonomia][builder] correcao pedido_fora_da_lista campo=#{item['campo']}") }
  end

  # O texto da lista igual ao pedido; o ponto final não conta. nil quando não há.
  def texto_da_lista(pedido, lista)
    return pedido if lista.include?(pedido)

    alvo = Autonomia::Agents::ResultadoDoAjuste.sem_ponto(pedido)
    lista.find { |texto| Autonomia::Agents::ResultadoDoAjuste.sem_ponto(texto) == alvo }
  end
end
