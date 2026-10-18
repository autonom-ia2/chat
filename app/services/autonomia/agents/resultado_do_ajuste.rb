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
    conferencia = thread.state.to_h['conferencia']
    thread.ready? && thread.agent.present? && conferencia.present? && conferencia.dig('desfeito', 'ok') != false &&
      Autonomia::Agents::Fase2.ligada?(thread.account)
  end

  LINHAS_DA_ULTIMA_MUDANCA = 3

  # A faixa "Última mudança" da tela do agente (sem a conversa aberta, mesmo depois de recarregar): a conversa e até 3
  # resumos do que entrou. nil quando já não dá para desfazer (a mesma regra do Desfazer, Agent#conversa_desfazivel).
  def self.ultima_mudanca_desfazivel(agent)
    thread = agent.conversa_desfazivel
    return if thread.nil?

    aplicadas = new(thread, conferencia_da_aplicacao(agent, thread)).linhas.select { |linha| linha[:estado] == 'aplicado' }
    { thread_id: thread.id, linhas: aplicadas.first(LINHAS_DA_ULTIMA_MUDANCA).map { |linha| sem_ponto(linha[:texto]) } }
  end

  # A conferência gravada na versão da aplicação (a do turno do ajuste, mesmo depois de uma pergunta na conversa), ou a
  # do state quando a versão não foi anotada.
  def self.conferencia_da_aplicacao(agent, thread)
    versao = agent.instruction_versions.find_by(id: thread.state.dig('ultimo_ajuste', 'versao_id'))
    versao&.metadata.to_h['conferencia'] || thread.state['conferencia']
  end
  private_class_method :conferencia_da_aplicacao

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
    { itens: linhas, faltou_fora: @conferencia['faltou_fora_da_lista'] == true, conferido: conferido?,
      desfeito_sozinho: desfeito_sozinho?, desfeito: @thread.state.to_h.dig('ultimo_ajuste', 'desfeito') == true,
      pode_desfazer: @thread.agent.conversa_desfazivel&.id == @thread.id }
  end

  # Uma linha por pedido (aplicado ou não) e, depois, o que o dono não pediu e mudou.
  def linhas
    sem_pedido = Autonomia::Agents::Builder::DesfechoDoAjuste.sem_pedido(@itens)
    nao_pedidos = agrupar(sem_pedido_que_mudou(sem_pedido)).map do |grupo|
      { estado: 'sem_pedido', texto: sem_ponto(grupo.first['resumo']) }
    end
    agrupar(@itens - sem_pedido).map { |grupo| linha_pedida(grupo) } + nao_pedidos
  end

  private

  # Grupos pelo texto do `pedido`, na ordem da lista; o destino secundário vai para o grupo do principal.
  def agrupar(itens)
    secundarios, principais = itens.partition { |item| secundario?(item, itens) }
    grupos = principais.group_by { |item| item['pedido'] }.values
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
    pedidos.pluck('pedido').exclude?(item['pedido']) && pedidos.pluck('campo').intersect?(SECUNDARIO_DE[item['campo']])
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

  def desfeito_sozinho?
    @conferencia.dig('desfeito', 'ok') == true
  end

  # Sem a conferência (o provedor falhou) ou sem a marca dos itens (a 2ª conferência passou do teto): mudou, sem conferir.
  def conferido?
    @conferencia['erro'].nil? && @itens.all? { |item| item.key?('atendido') }
  end
end
