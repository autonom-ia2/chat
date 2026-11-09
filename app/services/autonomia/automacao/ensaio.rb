# Ensaiar uma automação (#2498, F5 do #2414): o que ela faria em cada conversa, sem fazer nada.
#
# Só lê. Nunca chama o Executor, as ações, o envio, a IA, o webhook, o AntiLaco, a Cadeia, o dispatcher de eventos nem o
# ActionCable; nada grava, manda ou enfileira. Mostra o que faria, passo a passo, a partir da receita (a salva ou a do
# rascunho, já conferida por quem chama).
#
# Para cada conversa:
# - não entraria: no Spam, sem mensagem (no gatilho "mensagem criada"), resposta automática de e-mail (a régua da
#   Escuta) ou fora do "Só se" do gatilho;
# - entraria: os passos em ordem, do jeito do Roteiro. O "se" vale agora e segue pelo ramo que valer. O "esperar até"
#   que ainda não vale abre dois caminhos (se chegar a tempo: segue o resto; se o prazo vencer: o ramo e depois o
#   resto), e o "decidir" da IA abre um caminho por saída, sem escolher. "Parar" acaba o caminho.
# - a ação com valor calculado no corpo (G16) mostra o valor que daria agora, com os dados da conversa e o "hoje" de
#   agora, no fuso da conta; pula como o motor pularia.
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
  SO_MOSTRA = %w[esperar].freeze
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
    @conversa = conversa
    contexto = ::Autonomia::Automacao::Contexto.de(conversa, textos: textos_da_ia)
    valores = ::Autonomia::Automacao::Valores.new(alvo: contexto, mensagem: mensagem, quem: @usuario)
    base.merge(entraria: true, motivo: nil, passos: caminho(@roteiro.primeiro, valores))
  end

  # #2679: o ensaio não chama a IA. No lugar do texto de cada "escrever" e "resumir", a marca de onde ele entraria.
  def textos_da_ia
    @textos_da_ia ||= ::Autonomia::Automacao::Contexto.marcas_da_ia(@receita, @conta)
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
    return 'resposta_automatica' if ::Autonomia::Automacao::Escuta.resposta_automatica?(conversa, @receita.dig('gatilho', 'tipo'), mensagem)

    valores = ::Autonomia::Automacao::Valores.new(alvo: contexto, mensagem: mensagem, quem: @usuario)
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

  # Os passos que montam com os valores desta conversa e seguem para o próximo: o método do ensaio de cada um.
  EM_LINHA = { 'mensagem' => :texto, 'avisar' => :texto, 'email' => :email, 'acao' => :acao, 'ia_assumir' => :ia_assumir }.freeze

  # [o que faria, o próximo passo neste caminho (nil quando acabou aqui)]. Esperar e ação só se mostram; os passos de IA
  # que não abrem caminho só dizem o que fariam; o resto do mapa fechado tem regra própria, e tipo fora dele é
  # "catalogo" (só a frase).
  def ensaiar_passo(passo, valores)
    em_linha = EM_LINHA[passo['tipo']]
    return [send(em_linha, passo, valores), @roteiro.seguinte(passo['id'])] if em_linha

    case passo['tipo']
    when 'esperar_ate' then esperar_ate(passo, valores)
    when 'se' then se(passo, valores)
    when 'decidir' then [decidir(passo, valores), nil]
    when 'parar' then [no(passo, 'parar'), nil]
    else [em_frente(passo, valores), @roteiro.seguinte(passo['id'])]
    end
  end

  # G15: o nome da agente e, se não passaria, o motivo; nunca chama o serviço dos Agentes.
  def ia_assumir(passo, _valores) = no(passo, *::Autonomia::Automacao::PassoDeIaAssumir.ensaiar(passo, @conversa))

  def em_frente(passo, valores)
    return ia(passo) if IA_SO_DIZ.include?(passo['tipo'])
    return retorno(passo, valores) if passo['tipo'] == 'retorno'

    no(passo, SO_MOSTRA.include?(passo['tipo']) ? passo['tipo'] : 'catalogo')
  end

  def no(passo, faria, dados = {}, ramos: nil)
    { id: passo['id'], tipo: passo['tipo'], faria: faria, dados: dados, ramos: ramos }.compact
  end

  # O texto montado com os valores desta conversa, para o balão. Valor vazio: o passo pularia, como no motor.
  def texto(passo, valores)
    return no(passo, 'mensagens_desligadas') unless ::Autonomia::Automacao::Motor.mensagens?(@conta)

    pronto = ::Autonomia::Automacao::Texto.new(passo['texto'], valores).montar
    return no(passo, *::Autonomia::Automacao::AgendaDaPagina.do_vazio(valores.falta_da_agenda)) if pronto.nil?
    return no(passo, 'texto_vazio') if pronto.strip.empty?

    # F4b (#2468): o nome do modelo, para a tela dizer o que sai se a janela de 24 h estiver fechada.
    no(passo, passo['tipo'], { texto: pronto, modelo: passo.dig('modelo', 'nome') }.compact)
  end

  # O e-mail (G2) com o assunto e o texto desta conversa e a caixa por onde sairia, ou o motivo de não sair para o
  # contato dela (as mesmas perguntas do passo). Não abre conversa nem manda.
  def email(passo, valores)
    pronto = texto(passo, valores)
    return pronto unless pronto[:faria] == 'email'

    caixa = ::Autonomia::Automacao::PassoDeEmail.caixa(@conta, passo['caixa_id'])
    return no(passo, 'caixa_de_email_indisponivel') if caixa.nil?

    motivo = ::Autonomia::Automacao::PassoDeEmail.motivo_do_contato(@conta, @conversa.contact)
    return no(passo, motivo) if motivo

    assunto = ::Autonomia::Automacao::Texto.new(passo['assunto'], valores).montar
    return no(passo, *::Autonomia::Automacao::AgendaDaPagina.do_vazio(valores.falta_da_agenda)) if assunto.nil?
    return no(passo, 'texto_vazio') if assunto.strip.empty?

    pronto.merge(dados: pronto[:dados].merge(assunto: assunto.squish, caixa: caixa.name))
  end

  # O retorno (G3): o título montado, ou por que pularia, como o motor. O ensaio só descreve; nada é criado.
  def retorno(passo, valores)
    return no(passo, 'mensagens_desligadas') if passo['envio'] && !::Autonomia::Automacao::Motor.mensagens?(@conta)

    motivo = pulo_dos_textos(passo, valores)
    return no(passo, motivo) if motivo
    return no(passo, 'retorno_sem_responsavel') if [nil, 'responsavel'].include?(passo.dig('para', 'quem')) &&
                                                   valores.ler('conversa.responsavel_id').blank?

    no(passo, 'retorno', { texto: ::Autonomia::Automacao::Texto.new(passo['titulo'], valores).montar })
  end

  # O primeiro pulo do título e da mensagem do retorno, na ordem do motor: valor vazio ou texto só de espaços.
  def pulo_dos_textos(passo, valores)
    textos = passo['envio'] ? [passo['titulo'], passo.dig('envio', 'mensagem')] : [passo['titulo']]
    textos.lazy.map { |partes| pulo_do_texto(::Autonomia::Automacao::Texto.new(partes, valores).montar) }.find(&:itself)
  end

  def pulo_do_texto(pronto)
    return 'faltou_valor' if pronto.nil?

    'texto_vazio' if pronto.strip.empty?
  end

  # O valor calculado do corpo (G16) com os dados desta conversa e o "hoje" de agora: a data que daria se rodasse
  # agora. Pula como o motor: valor vazio, data que não é data, valor que não cabe no campo.
  def acao(passo, valores)
    corpo = passo['corpo'].to_h
    calculo = ::Autonomia::Automacao::Corpo
    return no(passo, 'faltou_valor') if caminho_vazio?(passo, valores)
    return no(passo, 'acao') unless calculo.calculado_em?(corpo)

    montado = calculo.new(corpo, valores: valores, conta: @conta).montar
    return no(passo, montado.motivo) if montado.motivo

    fora = ::Autonomia::Automacao::CampoDaAcao.problemas(passo['acao'], corpo, montado.corpo, conta: @conta)
    return no(passo, 'valor_fora_do_formato') if fora.any?

    calculados = calculo.lugares(corpo).map do |onde, _folha|
      { campo: onde.reverse.find { |parte| parte.is_a?(String) }, valor: montado.corpo.dig(*onde) }
    end
    no(passo, 'acao', { calculados: calculados })
  end

  # Como o motor: um valor vazio no caminho da ação pula o passo.
  def caminho_vazio?(passo, valores)
    passo['caminho'].to_h.values.any? { |valor| valor.is_a?(Hash) && valores.ler(valor['$valor']).blank? }
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
    no(passo, 'decidir', anexos(passo, ::Autonomia::Automacao::PassoDeDecidir), ramos: caminhos << nenhum)
  end

  # O que a IA faria, só com o que a receita diz. O passo que manda mensagem ou aviso (regras da F4) sem a mensagem
  # automática ligada na conta não sairia, como no motor.
  def ia(passo)
    classe = ::Autonomia::Automacao::IaNoExecutor::IA.fetch(passo['tipo'])
    return no(passo, 'mensagens_desligadas') if classe.fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta)

    no(passo, "ia_#{passo['tipo']}", classe.ensaiar(passo).merge(anexos(passo, classe)))
  end

  # G20: com `le: anexos`, quantos anexos desta conversa a IA leria, ou o motivo de o passo pular, como o motor. Não
  # baixa nada nem chama a IA.
  def anexos(passo, classe)
    return {} unless ::Autonomia::Automacao::AnexosDaConversa.le?(passo)

    lidos = ::Autonomia::Automacao::AnexosDaConversa.new(@conversa)
    motivo = lidos.motivo(modelo: classe::MODELO)
    motivo ? { anexos_motivo: motivo } : { anexos: lidos.quantos }
  end

  def condicao?(condicao, valores)
    ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
  end
end
