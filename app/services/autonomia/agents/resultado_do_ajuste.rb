# #1428 (tema 6, parte 3) — o resultado do último ajuste do "Mudar conversando", para a tela. SÓ NO PILOTO (Fase 2).
#
# Lê a conferência guardada no state da thread (ConferenciaDoAjuste + DesfechoDoAjuste). Os itens são agrupados pelo
# `pedido` que o Construtor escreveu (comparação do texto, sem ler linguagem); o destino secundário pela tabela (a
# instrução que acompanha o tom, os limites ou a passagem) entra no grupo do item principal, como no desfecho. Cada grupo
# é uma linha: `aplicado` (texto: o `resumo` do item principal), `nao_aplicado` (texto: o `pedido`) ou `sem_pedido`
# (o dono não pediu e mudou; texto: o `resumo`).
#
# NUNCA sai daqui o nome do campo, a fala do dono, texto da conferência, a instrução ou o andaime.
class Autonomia::Agents::ResultadoDoAjuste
  SECUNDARIO_DE = Autonomia::Agents::Builder::DesfechoDoAjuste::SECUNDARIO_DE

  # Sem cartão quando não sobrou nenhum pedido do dono (tudo sem pedido e o desfazer automático recusado): fica só o
  # aviso da conversa, nunca "Pronto. Mudei 0 coisas".
  def self.mostrar?(thread)
    thread.ready? && thread.agent.present? && cartao?(thread.state.to_h['conferencia']) &&
      Autonomia::Agents::Fase2.ligada?(thread.account)
  end

  # O cartão existe para esta conferência (a mesma regra da tela e da pergunta do que faltou): sem conferência, ou com o
  # desfazer automático recusado, não.
  def self.cartao?(conferencia)
    conferencia.present? && conferencia.dig('desfeito', 'ok') != false
  end

  LINHAS_DA_ULTIMA_MUDANCA = 3

  # A faixa "Última mudança" da tela do agente (sem o cartão na tela, mesmo depois de recarregar ou de uma pergunta): a
  # conversa, até 3 resumos do que entrou e até 3 do que o dono não pediu (o mesmo texto do cartão), lidos da conferência
  # do turno do ajuste. nil quando já não dá para desfazer (a mesma regra do Desfazer, Agent#conversa_desfazivel).
  def self.ultima_mudanca_desfazivel(agent)
    thread = agent.conversa_desfazivel
    return if thread.nil?

    linhas = new(thread, thread.state.dig('ultimo_ajuste', 'conferencia')).linhas
    { thread_id: thread.id, linhas: textos(linhas, 'aplicado'), sem_pedido: textos(linhas, 'sem_pedido') }
  end

  # #1850 — o que faltou, pelos GRUPOS do cartão (os mesmos de #linhas): `fora_do_cartao`, o texto dos pedidos não
  # atendidos que o cartão não mostra com ⚠; `mostrado`, se o cartão mostra alguma falta (linha ⚠ ou "uma parte não
  # entrou"). A pergunta que a tela mostra (TextosDoAjuste.pergunta_na_tela) não repete o que o cartão mostra. Sem cartão,
  # nada é mostrado; com o cartão neutro (sem a marca de todos os itens), nenhuma linha ⚠.
  def self.o_que_faltou(conferencia)
    resultado = new(nil, conferencia)
    faltando = resultado.pedidos_nao_atendidos
    return { fora_do_cartao: faltando, mostrado: false } unless cartao?(conferencia)

    no_cartao = resultado.conferido? ? resultado.linhas.select { |linha| linha[:estado] == 'nao_aplicado' }.pluck(:texto) : []
    { fora_do_cartao: faltando - no_cartao, mostrado: no_cartao.any? || conferencia['faltou_fora_da_lista'] == true }
  end

  def self.textos(linhas, estado)
    linhas.select { |linha| linha[:estado] == estado }.first(LINHAS_DA_ULTIMA_MUDANCA).map { |linha| sem_ponto(linha[:texto]) }
  end
  private_class_method :textos

  # O texto que a tela põe dentro de uma frase dela (entre aspas, ou numa lista) vai sem o ponto final.
  def self.sem_ponto(texto)
    texto.to_s.strip.chomp('.')
  end

  def initialize(thread, conferencia = thread.state.to_h['conferencia'])
    @thread = thread
    @conferencia = conferencia.to_h
    @itens = Array(@conferencia['itens'])
  end

  def to_h
    { itens: linhas_com_a_prova, faltou_fora: @conferencia['faltou_fora_da_lista'] == true, conferido: conferido?,
      desfeito_sozinho: desfeito_sozinho?, desfeito: @thread.state.to_h.dig('ultimo_ajuste', 'desfeito') == true,
      pode_desfazer: @thread.agent.conversa_desfazivel&.id == @thread.id, prova: prova }.merge(pergunta_curta)
  end

  # #1850 — a pergunta que a tela mostra no lugar da última bolha enquanto este cartão está lá: só enquanto a pergunta
  # aberta é a deste ajuste (o `next_question` é a inteira guardada) e ele não foi desfeito. No turno seguinte ou depois
  # do Desfazer, a tela mostra a pergunta inteira, que está na conversa.
  def pergunta_curta
    estado = @thread.state.to_h
    pergunta = estado['pergunta_na_tela'].to_h
    aberta = pergunta['curta'].present? && pergunta['inteira'] == estado['next_question']
    return {} unless aberta && estado.dig('ultimo_ajuste', 'desfeito') != true && !desfeito_sozinho?

    { pergunta_curta: pergunta['curta'] }
  end

  # Os pedidos de cada grupo com algum item não atendido, no texto da linha do cartão.
  def pedidos_nao_atendidos
    agrupar(@itens).select { |grupo| grupo.any? { |item| item['atendido'] != true } }
                   .map { |grupo| sem_ponto(grupo.first['pedido']) }.compact_blank.uniq
  end

  # #1428 (entrega B) — as perguntas de prova do último ajuste: só a do ajuste que está no cartão e que não foi desfeito.
  # Enquanto pendente, só quantas são; pronta, a pergunta e a resposta de cada uma (nunca o veredito por item nem texto do
  # juiz). Pendente há tempo demais vira indisponível: o job não vem mais.
  def prova
    dados = prova_do_cartao
    return if dados.nil?

    perguntas = Array(dados['perguntas'])
    status = status_da_prova(dados)
    return { status: status, total: perguntas.size } unless status == 'pronta'

    { status: status, total: dados['total'], ok: dados['ok'], completa: dados['completa'] != false,
      perguntas: perguntas.map { |item| pergunta_da_prova(item) } }.merge(pedidos_sem_teste(dados)).merge(contagem(dados))
  end

  # Os grupos dos pedidos aplicados, na ordem do cartão: a prova numera os pedidos por eles (ProvaDoAjuste).
  def grupos_aplicados
    grupos_pedidos.reject { |grupo| grupo.any? { |item| item['atendido'] == false } }
  end

  # Uma linha por pedido (aplicado ou não) e, depois, o que o dono não pediu e mudou.
  def linhas
    sem_pedido = Autonomia::Agents::Builder::DesfechoDoAjuste.sem_pedido(@itens)
    nao_pedidos = agrupar(sem_pedido_que_mudou(sem_pedido)).map do |grupo|
      { estado: 'sem_pedido', texto: sem_ponto(grupo.first['resumo']) }
    end
    grupos_pedidos.map { |grupo| linha_pedida(grupo) } + nao_pedidos
  end

  # Os pedidos do dono como o cartão os agrupa (uma linha por grupo), cada um com os seus itens. Fonte única: a prova
  # (ProvaDoAjuste) numera os pedidos por estes mesmos grupos.
  def grupos_pedidos
    agrupar(@itens - Autonomia::Agents::Builder::DesfechoDoAjuste.sem_pedido(@itens))
  end

  # Sem a conferência (o provedor falhou) ou sem a marca dos itens (a 2ª conferência passou do teto): mudou, sem conferir.
  def conferido?
    @conferencia['erro'].nil? && @itens.all? { |item| item.key?('atendido') }
  end

  private

  # Grupos pelo texto do `pedido` (sem o ponto final, como a linha mostra), na ordem da lista; o destino secundário vai
  # para o grupo do principal.
  def agrupar(itens)
    secundarios, principais = itens.partition { |item| secundario?(item, itens) }
    grupos = principais.group_by { |item| sem_ponto(item['pedido']) }.values
    secundarios.each do |item|
      grupo = grupos.find { |itens_do_grupo| itens_do_grupo.pluck('campo').intersect?(SECUNDARIO_DE[item['campo']]) }
      grupo ? grupo << item : grupos << [item]
    end
    grupos
  end

  # Não pedido pela conferência, com outro `pedido`, mas destino secundário de um item pedido (a regra do desfecho).
  def secundario?(item, itens)
    return false unless item['pedido_pelo_dono'] == false && SECUNDARIO_DE.key?(item['campo'])

    pedidos = itens.reject { |outro| outro['pedido_pelo_dono'] == false }
    pedidos.map { |outro| sem_ponto(outro['pedido']) }.exclude?(sem_ponto(item['pedido'])) &&
      pedidos.pluck('campo').intersect?(SECUNDARIO_DE[item['campo']])
  end

  def linha_pedida(grupo)
    return { estado: 'nao_aplicado', texto: sem_ponto(grupo.first['pedido']) } if grupo.any? { |item| item['atendido'] == false }

    { estado: 'aplicado', texto: grupo.first['resumo'].to_s }
  end

  def sem_ponto(texto)
    self.class.sem_ponto(texto)
  end

  # O que o dono não pediu e mudou de fato: o desfecho guarda em `sem_pedido` quando é só parte; quando era tudo e o
  # código não conseguiu desfazer (`desfeito.ok` false), tudo ficou aplicado.
  def sem_pedido_que_mudou(sem_pedido)
    return Array(@conferencia['sem_pedido']) unless @conferencia.key?('desfeito')

    desfeito_sozinho? ? [] : sem_pedido
  end

  # `ok`: true (respeitou a mudança), false (não respeitou) ou nil (a pergunta não toca a mudança). Nunca texto do juiz.
  def pergunta_da_prova(item)
    { pergunta: item['pergunta'], resposta: item['resposta'], equipe: item['equipe'] == true,
      ok: { 'ok' => true, 'nao' => false }[item['veredito']] }
  end

  # Prova incompleta (texto aprovado pelo Rodrigo em 22/10, "Não deu para ver nas respostas do teste: ..."): o texto
  # dos pedidos que nenhuma pergunta testou, na ordem do cartão. Só na prova gravada com `testes`; sem a lista, a tela
  # usa o texto geral.
  def pedidos_sem_teste(dados)
    return {} unless incompleta_com_testes?(dados)

    testados = Array(dados['perguntas']).flat_map { |item| Array(item['testes']) }.pluck('pedido')
    textos = aplicados_da_prova.each_with_index.reject { |_grupo, posicao| testados.include?(posicao) }
                               .map { |grupo, _posicao| sem_ponto(grupo.first['pedido']) }
    textos.any? ? { pedidos_sem_teste: textos } : {}
  end

  def incompleta_com_testes?(dados)
    dados['completa'] == false && Array(dados['perguntas']).any? { |item| item.key?('testes') }
  end

  # Cartão (aprovado pelo Rodrigo em 22/10): o título conta MUDANÇAS (os pedidos aplicados) e não perguntas, e diz
  # quantas a resposta do teste contrariou.
  def contagem(dados)
    vistos = vistos_pela_prova(dados)
    return {} if vistos.nil?

    { mudancas: { testadas: vistos.count { |visto| visto != 'sem_teste' }, total: vistos.size,
                  contraditas: vistos.count('nao') } }
  end

  # O ✓ de "mudei" não vem junto de "não deu para ver": cada linha aplicada leva o que a prova viu dela. Só quando o
  # cartão é o da conferência que a prova numerou (a do ultimo_ajuste); senão, as linhas ficam como sempre.
  def linhas_com_a_prova
    vistos = vistos_pela_prova(prova_do_cartao.to_h)
    mesma = @conferencia == @thread.state.to_h.dig('ultimo_ajuste', 'conferencia').to_h
    return linhas if vistos.nil? || !mesma

    proximo = vistos.each
    linhas.map { |linha| linha[:estado] == 'aplicado' ? linha.merge(prova: proximo.next) : linha }
  end

  # Por pedido aplicado, na ordem do cartão: 'nao' (algum teste viu a forma oposta), 'ok' (algum teste viu) ou
  # 'sem_teste'. nil fora da prova pronta gravada com `testes` (a prova antiga fica como antes).
  def vistos_pela_prova(dados)
    perguntas = Array(dados['perguntas'])
    return if dados['status'] != 'pronta' || perguntas.none? { |item| item.key?('testes') }

    testes = perguntas.flat_map { |item| Array(item['testes']) }
    Array.new(aplicados_da_prova.size) { |posicao| visto(testes, posicao) }
  end

  def visto(testes, posicao)
    vereditos = testes.select { |teste| teste['pedido'] == posicao }.pluck('veredito')
    %w[nao ok].find { |veredito| vereditos.include?(veredito) } || 'sem_teste'
  end

  # Os pedidos que a prova numerou: os do ajuste dela (ultimo_ajuste), não os da conferência do turno mais recente.
  def aplicados_da_prova
    self.class.new(nil, @thread.state.to_h.dig('ultimo_ajuste', 'conferencia')).grupos_aplicados
  end

  def prova_do_cartao
    dados = @thread.state.to_h['prova']
    ultimo = @thread.state.to_h['ultimo_ajuste'].to_h
    return unless dados.is_a?(Hash) && dados['versao_id'] == ultimo['versao_id']

    dados unless ultimo['desfeito'] == true || desfeito_sozinho?
  end

  def status_da_prova(dados)
    desde = Time.zone.parse(dados['desde'].to_s)
    vencida = desde&.before?(Autonomia::Agents::ProvaDoAjuste::VALIDADE_DO_PENDENTE.ago)
    dados['status'] == 'pendente' && vencida ? 'indisponivel' : dados['status']
  end

  def desfeito_sozinho?
    @conferencia.dig('desfeito', 'ok') == true
  end
end
