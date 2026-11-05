# Ensaiar uma automação (#2498, F5 do #2414): o que ela faria em cada conversa, sem fazer nada.
#
# Só lê. Nunca chama o Executor, as ações, o envio, a IA, o webhook, o AntiLaco, a Cadeia, o dispatcher de eventos nem o
# ActionCable; nada grava, manda ou enfileira. Mostra o que faria, passo a passo, a partir da receita (a salva ou a do
# rascunho, já conferida por quem chama).
#
# Para cada conversa:
# - não entraria: no Spam, sem mensagem (no gatilho "mensagem criada") ou fora do "Só se" do gatilho;
# - entraria: os passos em ordem, do jeito do Roteiro. O "se" vale agora e segue pelo ramo que valer. O "esperar até"
#   que ainda não vale abre dois caminhos (se chegar a tempo: segue o resto; se o prazo vencer: o ramo e depois o
#   resto), e o "decidir" da IA abre um caminho por saída, sem escolher. "Parar" acaba o caminho.
# - "extrair", "escrever" e "resumir" (#2500 F7) só dizem o que a IA faria e para onde iria, pelo `ensaiar` de cada
#   passo: nenhuma IA é chamada.
#
# Cada tipo de passo diz o que faria por um mapa fechado. Tipo fora do mapa (um passo novo) só ganha a frase do
# catálogo: o ensaio nunca roda o que não conhece.
class Autonomia::Automacao::Ensaio
  RECENTES = 10
  # As seguintes, para "Ensaiar em outra conversa": só o nome, sem ensaiar.
  OUTRAS = 40
  # Contra defeito, não contra uso: cada "esperar até" ou "decidir" multiplica os caminhos.
  MAXIMO_DE_PASSOS = 500
  GATILHOS = %w[conversa.criada conversa.aberta conversa.resolvida mensagem.criada].freeze
  SO_MOSTRA = %w[esperar acao].freeze
  # #2500 F7: os passos de IA que seguem em frente; o "decidir" abre caminhos e tem regra própria.
  IA_SO_DIZ = %w[extrair escrever resumir].freeze

  def self.gatilho_suportado?(receita)
    GATILHOS.include?(receita.dig('gatilho', 'tipo'))
  end

  # Só as conversas que `usuario` enxerga, pelo mesmo filtro da lista de conversas. Com `conversa_id` (o número que a
  # pessoa vê), ensaia só ela; fora do alcance de quem pede, é como se não existisse (RecordNotFound, 404).
  def initialize(receita:, conta:, usuario:, conversa_id: nil)
    @receita = receita
    @conta = conta
    @usuario = usuario
    @conversa_id = conversa_id
    @roteiro = ::Autonomia::Automacao::Roteiro.new(receita)
  end

  def resultado
    return { conversas: [ensaiar(visiveis.find_by!(display_id: @conversa_id))], outras: [] } if @conversa_id.present?

    recentes = visiveis.includes(:contact).reorder(last_activity_at: :desc, id: :desc).limit(RECENTES + OUTRAS).to_a
    { conversas: recentes.first(RECENTES).map { |conversa| ensaiar(conversa) },
      outras: recentes.drop(RECENTES).map { |conversa| { conversa_id: conversa.display_id, nome: conversa.contact&.name } } }
  end

  # As conversas recentes de quem pede em que a automação entraria agora, na ordem do ensaio. O "Testar este passo"
  # (#2500 C2) roda nelas.
  def entrariam(limite)
    recentes = visiveis.includes(:contact).reorder(last_activity_at: :desc, id: :desc).limit(RECENTES + OUTRAS)
    recentes.select { |conversa| fora(conversa, (ultima_mensagem(conversa) if mensagem_no_gatilho?)).nil? }.first(limite)
  end

  private

  def visiveis
    ::Conversations::PermissionFilterService.new(@conta.conversations, @usuario, @conta, for_reading: true).perform
  end

  def ensaiar(conversa)
    mensagem = ultima_mensagem(conversa) if mensagem_no_gatilho?
    base = { conversa_id: conversa.display_id, nome: conversa.contact&.name, ultima_atividade: conversa.last_activity_at }
    motivo = fora(conversa, mensagem)
    return base.merge(entraria: false, motivo: motivo, passos: []) if motivo

    @contados = 0
    valores = ::Autonomia::Automacao::Valores.new(alvo: conversa, mensagem: mensagem)
    base.merge(entraria: true, motivo: nil, passos: caminho(@roteiro.primeiro, valores))
  end

  def mensagem_no_gatilho? = @receita.dig('gatilho', 'tipo') == ::Autonomia::Automacao::Valores::GATILHO_DA_MENSAGEM

  # A régua da Escuta: atividade não é mensagem de ninguém; a nota privada conta.
  def ultima_mensagem(conversa)
    conversa.messages.where.not(message_type: :activity).reorder(created_at: :desc, id: :desc).first
  end

  # O Spam pela mesma pergunta da Partida (#2499): o Contexto do alvo.
  def fora(conversa, mensagem)
    contexto = ::Autonomia::Automacao::Contexto.de(conversa)
    return 'spam' if contexto.no_spam?
    return 'sem_mensagem' if mensagem_no_gatilho? && mensagem.nil?

    valores = ::Autonomia::Automacao::Valores.new(alvo: contexto, mensagem: mensagem)
    filtros = Array(@receita.dig('gatilho', 'filtros'))
    'fora_do_filtro' unless filtros.all? { |condicao| ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira? }
  end

  # Os passos a partir de `passo` até o fim (ou até um "parar"), em ordem. Um passo que abre caminhos leva o resto
  # dentro de cada caminho.
  def caminho(passo, valores)
    passos = []
    while passo
      return passos << { faria: 'corte' } if (@contados += 1) > MAXIMO_DE_PASSOS

      no, seguinte = ensaiar_passo(passo, valores)
      passos << no
      passo = seguinte
    end
    passos
  end

  # [o que faria, o próximo passo neste caminho (nil quando acabou aqui)]. Esperar e ação só se mostram; os passos de IA
  # que não abrem caminho só dizem o que fariam; o resto do mapa fechado tem regra própria, e tipo fora dele é
  # "catalogo" (só a frase).
  def ensaiar_passo(passo, valores)
    case passo['tipo']
    when 'mensagem', 'avisar' then [texto(passo, valores), @roteiro.seguinte(passo['id'])]
    when 'esperar_ate' then esperar_ate(passo, valores)
    when 'se' then se(passo, valores)
    when 'decidir' then [decidir(passo, valores), nil]
    when 'parar' then [no(passo, 'parar'), nil]
    else [em_frente(passo), @roteiro.seguinte(passo['id'])]
    end
  end

  def em_frente(passo)
    return ia(passo) if IA_SO_DIZ.include?(passo['tipo'])

    no(passo, SO_MOSTRA.include?(passo['tipo']) ? passo['tipo'] : 'catalogo')
  end

  def no(passo, faria, dados = {}, ramos: nil)
    { id: passo['id'], tipo: passo['tipo'], faria: faria, dados: dados, ramos: ramos }.compact
  end

  # O texto montado com os valores desta conversa, para o balão. Valor vazio: o passo pularia, como no motor.
  def texto(passo, valores)
    return no(passo, 'mensagens_desligadas') unless ::Autonomia::Automacao::Motor.mensagens?(@conta)

    pronto = ::Autonomia::Automacao::Texto.new(passo['texto'], valores).montar
    return no(passo, 'faltou_valor') if pronto.nil?
    return no(passo, 'texto_vazio') if pronto.strip.empty?

    no(passo, passo['tipo'], { texto: pronto })
  end

  def se(passo, valores)
    ramo = condicao?(passo['condicao'], valores) ? 'entao' : 'senao'
    [no(passo, 'se', { ramo: ramo }), @roteiro.entrar(passo, ramo)]
  end

  # Já vale agora: segue na hora, como o motor. Não vale: os dois caminhos possíveis.
  def esperar_ate(passo, valores)
    return [no(passo, 'esperar_ate_ja_vale'), @roteiro.seguinte(passo['id'])] if condicao?(passo['condicao'], valores)

    ramos = [
      { chave: 'chegou', passos: caminho(@roteiro.seguinte(passo['id']), valores) },
      { chave: 'se_vencer', passos: caminho(@roteiro.entrar(passo, 'se_vencer'), valores) }
    ]
    [no(passo, 'esperar_ate', ramos: ramos), nil]
  end

  # A IA escolheria o caminho: o ensaio mostra todos, sem chamar modelo nenhum.
  def decidir(passo, valores)
    caminhos = Array(passo['caminhos']).map do |item|
      { chave: item['chave'], nome: item['nome'], passos: caminho(Array(item['passos']).first || @roteiro.seguinte(passo['id']), valores) }
    end
    chave = ::Autonomia::Automacao::Receita::NENHUM
    nenhum = { chave: chave, passos: caminho(@roteiro.entrar(passo, chave), valores) }
    no(passo, 'decidir', ramos: caminhos << nenhum)
  end

  # O que a IA faria, só com o que a receita diz. O passo que manda mensagem ou aviso (regras da F4) sem a mensagem
  # automática ligada na conta não sairia, como no motor.
  def ia(passo)
    classe = ::Autonomia::Automacao::IaNoExecutor::IA.fetch(passo['tipo'])
    return no(passo, 'mensagens_desligadas') if classe.fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta)

    no(passo, "ia_#{passo['tipo']}", classe.ensaiar(passo))
  end

  def condicao?(condicao, valores)
    ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
  end
end
