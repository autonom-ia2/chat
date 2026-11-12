# Ensaiar uma automação (#2498, F5 do #2414): o que ela faria em cada conversa, sem fazer nada.
#
# Só lê. Nunca chama o Executor, as ações, o envio, a IA, o webhook, o AntiLaco, a Cadeia, o dispatcher de eventos nem o
# ActionCable; nada grava, manda ou enfileira. Mostra o que faria, passo a passo, a partir da receita (a salva ou a do
# rascunho, já conferida por quem chama).
#
# Para cada conversa:
# - não entraria: no Spam, sem mensagem (no gatilho "mensagem criada"), sem mensagem recusada (no gatilho "mensagem que
#   falhou", G53), resposta automática de e-mail (a régua da Escuta) ou fora do "Só se" do gatilho;
# - entraria: os passos em ordem, do jeito do Roteiro. O "se" vale agora e segue pelo ramo que valer. O "esperar até"
#   que ainda não vale abre dois caminhos (se chegar a tempo: segue o resto; se o prazo vencer: o ramo e depois o
#   resto; sem prazo, só o primeiro), e o "decidir" da IA abre um caminho por saída, sem escolher. "Parar" acaba o caminho.
# - a ação com valor calculado no corpo (G16) mostra o valor que daria agora, com os dados da conversa e o "hoje" de
#   agora, no fuso da conta; pula como o motor pularia.
# - "extrair", "escrever", "resumir" (#2500 F7) e "para cada item" (G24) só dizem o que a IA faria e para onde iria,
#   pelo `ensaiar` de cada passo: nenhuma IA é chamada.
# - quem age precisa poder agir na conversa (#2604, EnvioNoEnsaio#pausaria_ao_agir), a pergunta do Executor no começo de
#   cada rodada: sem isso, o primeiro passo diz "pausaria" e o caminho acaba ali. O e-mail confere também se quem age
#   começa conversa na caixa, e a mensagem no número novo (G43), na caixa da conversa.
#   A mensagem e o "escrever" ao cliente conferem o canal (#2609): com a janela fechada e sem modelo que saia no lugar,
#   "pararia", com o motivo, e o caminho acaba.
#
# No gatilho de card (#2631), o mesmo nos cards que quem pede alcança (CardsDoEnsaio): cada um como se o fato
# acontecesse agora. No de reunião, com a reunião que o gatilho leria (`reuniao.*`); o card sem ela não entraria.
# O card sem conversa segue uma regra só, a do motor: sem a caixa da conversa nova no gatilho (#2680), todo passo que
# age numa conversa (mensagem, avisar, os de IA, ia_assumir) pula com `sem_conversa`; com ela, o "mensagem" a abriria
# (ou usa a do contato que já há nessa caixa), e os passos depois dele, no mesmo caminho, agem nela.
#
# Nos gatilhos de etiqueta (G10) e de troca de quem atende (F8.3), o mesmo: na conversa ou no contato (ContatosDoEnsaio)
# como se a etiqueta fosse posta ou tirada, ou a pessoa ou o time trocasse, agora. Com a etiqueta escolhida, só os que
# a têm (no "tirada", os que a perderiam). O contato não tem conversa própria: segue a regra do card sem conversa.
#
# Cada tipo de passo diz o que faria por um mapa fechado. Tipo fora do mapa (um passo novo) só ganha a frase do
# catálogo: o ensaio nunca roda o que não conhece.
class Autonomia::Automacao::Ensaio
  RECENTES = 10
  # As seguintes, para "Ensaiar em outra conversa": só o nome, sem ensaiar.
  OUTRAS = 40
  # Contra defeito, não contra uso: cada "esperar até" ou "decidir" multiplica os caminhos.
  MAXIMO_DE_PASSOS = 500
  GATILHOS = %w[conversa.criada conversa.aberta conversa.resolvida mensagem.criada mensagem.falhou conversa.responsavel_mudou
                conversa.time_mudou conversa.etiqueta_posta conversa.etiqueta_tirada].freeze
  # G10: o gatilho de contato que o ensaio roda; os de tempo e o recorrente do contato, ainda não.
  DO_CONTATO = %w[contato.etiqueta_posta contato.etiqueta_tirada].freeze
  AMOSTRAS = { 'conversa' => ::Autonomia::Automacao::ConversasDoEnsaio, 'card' => ::Autonomia::Automacao::CardsDoEnsaio,
               'contato' => ::Autonomia::Automacao::ContatosDoEnsaio }.freeze
  SO_MOSTRA = %w[esperar].freeze
  # #2500 F7: os passos de IA que seguem em frente; o "decidir" abre caminhos e tem regra própria.
  IA_SO_DIZ = %w[extrair escrever resumir para_cada].freeze

  def self.gatilho_suportado?(receita) = de_conversa?(receita) || de_card?(receita) || de_contato?(receita)

  def self.de_conversa?(receita) = GATILHOS.include?(receita.dig('gatilho', 'tipo'))

  # #2631: o gatilho de card, de evento ou de tempo. O recorrente só conta quantos pegaria (o controller).
  def self.de_card?(receita)
    tipo = receita.dig('gatilho', 'tipo')
    ::Autonomia::Automacao::Gatilhos.do_card?(tipo) && !::Autonomia::Automacao::Gatilhos.recorrente?(tipo)
  end

  def self.de_contato?(receita) = DO_CONTATO.include?(receita.dig('gatilho', 'tipo'))

  # Em quem o ensaio roda: 'conversa', 'card' ou 'contato'.
  def self.alvo(receita) = (de_card?(receita) && 'card') || (de_contato?(receita) && 'contato') || 'conversa'

  # Só as conversas (ConversasDoEnsaio), os cards (CardsDoEnsaio) ou os contatos (ContatosDoEnsaio) que `usuario`
  # alcança. Com `conversa_id` (o número da conversa; no gatilho de card ou de contato, o id dele), ensaia só ele; fora
  # do alcance de quem pede, é como se não existisse (RecordNotFound, 404). Quem age é quem o motor agiria (#2604):
  # com `acesso` (o de quem ligou, na versão salva de uma automação ligada), quem ligou, com a mesma pergunta do motor
  # (Acesso#motivo_no); sem ele, quem pede.
  def initialize(receita:, conta:, usuario:, conversa_id: nil, acesso: nil)
    @receita = receita
    @conta = conta
    @usuario = usuario
    @conversa_id = conversa_id
    @acesso = acesso
    @quem_age = acesso&.usuario || usuario
    @alvo = self.class.alvo(receita)
    # O laço dos documentos (G46) não roda de novo no ensaio: o caminho que volta para no fim e diz para onde.
    @roteiro = ::Autonomia::Automacao::Roteiro.new(receita, voltar: false)
  end

  # `alvo` diz à tela se a lista é de conversas, de cards ou de contatos; o formato de cada item é o mesmo.
  def resultado
    return { alvo: @alvo, conversas: [ensaiar(amostra.um(@conversa_id))], outras: [] } if @conversa_id.present?

    recentes = amostra.recentes(RECENTES + OUTRAS)
    { alvo: @alvo, conversas: recentes.first(RECENTES).map { |item| ensaiar(item) },
      outras: recentes.drop(RECENTES).map { |item| amostra.base(item).except(:ultima_atividade) } }
  end

  # As conversas recentes de quem pede em que a automação entraria agora, na ordem do ensaio. O "Testar este passo"
  # (#2500 C2) roda nelas.
  def entrariam(limite)
    amostra.recentes(RECENTES + OUTRAS).select { |conversa| fora(conversa, *amostra.gatilho_de(conversa)).nil? }.first(limite)
  end

  private

  def amostra
    @amostra ||= AMOSTRAS.fetch(@alvo).new(gatilho: @receita['gatilho'].to_h, conta: @conta, usuario: @usuario)
  end

  def ensaiar(alvo)
    mensagem, fato = amostra.gatilho_de(alvo)
    base = amostra.base(alvo)
    motivo = fora(alvo, mensagem, fato)
    return base.merge(entraria: false, motivo: motivo, passos: []) if motivo

    @contados = 0
    contexto = ::Autonomia::Automacao::Contexto.de(alvo, textos: textos_da_ia, fato: fato)
    @contato = contexto.contato
    @conversa, @caixa_nova = conversa_do_ensaio(contexto)
    valores = ::Autonomia::Automacao::Valores.new(alvo: contexto, mensagem: mensagem, quem: @usuario)
    base.merge(entraria: true, motivo: nil, passos: passos_do_alvo(alvo, valores))
  end

  # O Executor confere quem age no começo da rodada, antes de qualquer passo (Executor#rodar, impedida?): sem acesso, a
  # automação pausa ali. O ensaio diz "pausaria" no primeiro passo, seja ele qual for, e não lista os seguintes.
  def passos_do_alvo(alvo, valores)
    primeiro = @roteiro.primeiro
    pausa = envio.pausaria_ao_agir(alvo) if primeiro
    pausa ? [no(primeiro, *pausa)] : caminho(primeiro, valores)
  end

  # As perguntas do motor sobre o envio (EnvioNoEnsaio) na conversa em que os passos agem agora: a do alvo ou a que o
  # "mensagem" abriria no card sem conversa.
  def envio(conversa = @conversa) = ::Autonomia::Automacao::EnvioNoEnsaio.new(conversa, @quem_age, @acesso)

  # #2679: o ensaio não chama a IA. No lugar do texto de cada "escrever" e "resumir", a marca de onde ele entraria.
  def textos_da_ia
    @textos_da_ia ||= ::Autonomia::Automacao::Contexto.marcas_da_ia(@receita, @conta)
  end

  # O Spam pela mesma pergunta da Partida (#2499): o Contexto do alvo. Depois, o que falta ao alvo para o gatilho
  # (a mensagem, a reunião) e o "Só se", que lê o fato (a reunião do gatilho de reunião, G12).
  def fora(alvo, mensagem, fato)
    contexto = ::Autonomia::Automacao::Contexto.de(alvo, fato: fato)
    return 'spam' if contexto.no_spam?

    motivo = amostra.motivo(alvo, mensagem, fato)
    return motivo if motivo

    valores = ::Autonomia::Automacao::Valores.new(alvo: contexto, mensagem: mensagem, quem: @usuario)
    filtros = Array(@receita.dig('gatilho', 'filtros'))
    'fora_do_filtro' unless filtros.all? { |condicao| ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira? }
  end

  # A conversa em que os passos agiriam e, no card sem nenhuma e no contato, a caixa por onde o "mensagem" abriria uma
  # (#2680).
  def conversa_do_ensaio(contexto)
    return [contexto.conversa, nil] if contexto.conversa || @alvo == 'conversa'

    amostra.conversa_nova(@contato)
  end

  # Os passos a partir de `passo` até o fim (ou até um "parar"), em ordem. Um passo que abre caminhos leva o resto
  # dentro de cada caminho. A conversa que o "mensagem" abriria vale neste caminho e nos de dentro, não nos irmãos.
  def caminho(passo, valores)
    antes = @conversa
    passos = []
    while passo
      return passos << { faria: 'corte' } if (@contados += 1) > MAXIMO_DE_PASSOS

      no, seguinte = ensaiar_passo(passo, valores)
      passos << no
      passo = seguinte
    end
    passos
  ensure
    @conversa = antes
  end

  # Os passos que montam com os valores desta conversa e seguem para o próximo: o método do ensaio de cada um.
  EM_LINHA = { 'mensagem' => :mensagem, 'avisar' => :avisar, 'email' => :email, 'acao' => :acao, 'ia_assumir' => :ia_assumir,
               'rodizio' => :rodizio }.freeze

  # [o que faria, o próximo passo neste caminho (nil quando acabou aqui)]. Esperar e ação só se mostram; os passos de IA
  # que não abrem caminho só dizem o que fariam; o resto do mapa fechado tem regra própria, e tipo fora dele é
  # "catalogo" (só a frase).
  def ensaiar_passo(passo, valores)
    em_linha = EM_LINHA[passo['tipo']]
    return seguir(passo, send(em_linha, passo, valores)) if em_linha

    case passo['tipo']
    when 'esperar_ate' then esperar_ate(passo, valores)
    when 'se' then se(passo, valores)
    when 'decidir' then @conversa ? [decidir(passo, valores), nil] : [no(passo, 'sem_conversa'), @roteiro.seguinte(passo['id'])]
    when 'parar' then [no(passo, 'parar'), nil]
    else seguir(passo, em_frente(passo, valores))
    end
  end

  # O passo depois do qual o motor não segue (EnvioNoEnsaio::ACABA) acaba o caminho.
  def seguir(passo, feito) = [feito, (@roteiro.seguinte(passo['id']) unless ::Autonomia::Automacao::EnvioNoEnsaio::ACABA.include?(feito[:faria]))]

  # G15: o nome da agente e, se não passaria, o motivo; nunca chama o serviço dos Agentes. O card sem conversa pula,
  # como no motor; na que o "mensagem" abriria, as mesmas perguntas valem para ela.
  def ia_assumir(passo, _valores) = sem_conversa(passo) || no(passo, *::Autonomia::Automacao::PassoDeIaAssumir.ensaiar(passo, @conversa))

  # #2502: entre quem seria o rodízio, ou por que pularia; nunca gira a fila da caixa. O card sem conversa pula, como no
  # motor (PassoDeRodizio#executar).
  def rodizio(passo, _valores) = sem_conversa(passo) || no(passo, *::Autonomia::Automacao::PassoDeRodizio.ensaiar(passo, @conversa))

  def sem_conversa(passo) = (no(passo, 'sem_conversa') if @conversa.nil?)

  def em_frente(passo, valores)
    return ia(passo, valores) if IA_SO_DIZ.include?(passo['tipo'])
    return retorno(passo, valores) if passo['tipo'] == 'retorno'

    no(passo, SO_MOSTRA.include?(passo['tipo']) ? passo['tipo'] : 'catalogo')
  end

  def no(passo, faria, dados = {}, ramos: nil)
    { id: passo['id'], tipo: passo['tipo'], faria: faria, dados: dados, ramos: ramos }.compact
  end

  # A mensagem e o aviso agem numa conversa. No card sem ela, a mensagem abre a da caixa da conversa nova, quando o
  # gatilho escolhe uma (PassoDeMensagem#abrir_e_mandar); sem a caixa, e no aviso, pulam com `sem_conversa`.
  def avisar(passo, valores) = na_conversa? ? texto(passo, valores) : no(passo, 'sem_conversa')

  def mensagem(passo, valores)
    return no_canal(passo, valores) if na_conversa?

    @caixa_nova ? abrir_conversa(passo, valores) : no(passo, 'sem_conversa')
  end

  # Há conversa, ou a flag das mensagens desligada responde antes (Executor#passo_nativo).
  def na_conversa? = @conversa || !::Autonomia::Automacao::Motor.mensagens?(@conta)

  # Depois do texto, o canal (#2609, EnvioNoEnsaio#do_canal). O texto vazio também pergunta: no motor, a janela vem antes.
  def no_canal(passo, valores, conversa = @conversa)
    pronto = texto(passo, valores, conversa&.inbox)
    canal = envio(conversa).do_canal(passo, valores) if %w[mensagem texto_vazio].include?(pronto[:faria])
    canal ? no(passo, *canal) : pronto
  end

  # Na ordem do PassoDeMensagem#abrir_e_mandar: quem age começa conversa na caixa (#2604), o contato recebe, o texto e o
  # canal da conversa que ela seria: nova, aberta, sem ninguém no nome. Só um objeto na memória, nunca gravado. Se a
  # mensagem sairia, os passos seguintes deste caminho agem nela.
  def abrir_conversa(passo, valores)
    fora = envio(nil).abre_conversa(@caixa_nova) || ::Autonomia::Automacao::ConversaNova.motivo_do_contato(@caixa_nova, @contato)
    return no(passo, *fora) if fora

    nova = ::Conversation.new(account: @conta, inbox: @caixa_nova, contact: @contato, status: :open)
    pronto = no_canal(passo, valores, nova)
    return pronto unless pronto[:faria] == 'mensagem'

    @conversa = nova
    pronto.merge(dados: pronto[:dados].merge(conversa_nova: @caixa_nova.name))
  end

  # O texto montado com os valores desta conversa, para o balão. Valor vazio: o passo pularia, como no motor.
  def texto(passo, valores, caixa = @conversa&.inbox)
    return no(passo, 'mensagens_desligadas') unless ::Autonomia::Automacao::Motor.mensagens?(@conta)

    pronto = ::Autonomia::Automacao::Texto.new(passo['texto'], valores).montar
    return no(passo, *::Autonomia::Automacao::AgendaDaPagina.do_vazio(valores.falta_da_agenda)) if pronto.nil?
    return no(passo, 'texto_vazio') if pronto.strip.empty?

    ninguem, reserva = previsto_do_aviso(passo)
    return no(passo, ninguem) if ninguem

    # F4b (#2468): o nome do modelo, para a tela dizer o que sai se a janela de 24 h estiver fechada; o de propaganda
    # (lote 5, #2681) leva o aviso de custo.
    propaganda = true if ::Autonomia::Automacao::ModeloWhatsapp.propaganda?(caixa, passo['modelo'])
    no(passo, passo['tipo'], { texto: pronto, modelo: passo.dig('modelo', 'nome'), propaganda: propaganda, reserva: reserva }.compact)
  end

  # O "avisar", e o "resumir" que sai por ele (#2523, #2552): [por que ninguém seria avisado, por que iria para a caixa].
  def previsto_do_aviso(passo) = ::Autonomia::Automacao::PassoDeAviso.ensaiar(passo, @conversa)

  # O e-mail (G2) com o assunto, o texto e a caixa por onde sairia, ou por que não sairia (EnvioNoEnsaio#email).
  def email(passo, valores) = no(passo, *envio.email(passo, valores, conta: @conta, contato: @contato))

  # O retorno (G3): o título montado, ou por que pularia, como o motor (PassoDeRetorno.ensaiar). Nada é criado.
  def retorno(passo, valores) = no(passo, *::Autonomia::Automacao::PassoDeRetorno.ensaiar(passo, valores, @conta))

  # O valor calculado do corpo (G16) com os dados do alvo e o "hoje" de agora, ou por que pularia (AcaoNoEnsaio).
  def acao(passo, valores) = no(passo, *::Autonomia::Automacao::AcaoNoEnsaio.ensaiar(passo, valores, @conta))

  def se(passo, valores)
    ramo = condicao?(passo['condicao'], valores) ? 'entao' : 'senao'
    [no(passo, 'se', { ramo: ramo }), @roteiro.entrar(passo, ramo)]
  end

  # Já vale agora: segue na hora, como o motor; com hora marcada (G64), não: o motor só confere na hora. Não vale: os
  # caminhos possíveis; sem prazo (#2750), sem o "se vencer". Com o galho "a cada mensagem" (G63), mais um caminho: os
  # passos dele, que param no fim com a marca `volta` (o roteiro do ensaio não volta a esperar).
  def esperar_ate(passo, valores)
    return [no(passo, 'esperar_ate_ja_vale'), @roteiro.seguinte(passo['id'])] if segue_na_hora?(passo, valores)

    ramos = [{ chave: 'chegou', passos: caminho(@roteiro.seguinte(passo['id']), valores) }]
    unless ::Autonomia::Automacao::Duracao.sem_prazo?(passo['prazo'])
      ramos << { chave: 'se_vencer', passos: caminho(@roteiro.entrar(passo, 'se_vencer'), valores) }
    end
    ramos << galho_do_ensaio(passo, valores) if ::Autonomia::Automacao::EnquantoEspera.a_cada?(passo)
    [no(passo, 'esperar_ate', ramos: ramos), nil]
  end

  def segue_na_hora?(passo, valores) = !::Autonomia::Automacao::EnquantoEspera.conferir_as?(passo) && condicao?(passo['condicao'], valores)

  def galho_do_ensaio(passo, valores, chave = ::Autonomia::Automacao::EnquantoEspera::A_CADA)
    { chave: chave, volta: @roteiro.volta(passo, chave), passos: caminho(@roteiro.entrar(passo, chave), valores) }
  end

  # A IA escolheria o caminho: o ensaio mostra todos, sem chamar modelo nenhum.
  # G31: o caminho que decide de novo espera a próxima resposta e não roda passo nenhum; vencido o prazo, a execução
  # acaba sem mandar nada. G46: o caminho que volta mostra os passos dele e a qual "esperar até" volta
  # (DecidirDeNovo.ramos_do_ensaio).
  def decidir(passo, valores)
    ramos = ::Autonomia::Automacao::DecidirDeNovo.ramos_do_ensaio(passo, @roteiro) { |primeiro| caminho(primeiro, valores) }
    no(passo, 'decidir', ia_do_ensaio.anexos(passo, ::Autonomia::Automacao::PassoDeDecidir), ramos: ramos)
  end

  # O que a IA faria, só com o que a receita diz, ou por que pularia (IaNoEnsaio).
  def ia(passo, valores) = no(passo, *ia_do_ensaio.ensaiar(passo, valores))

  def ia_do_ensaio = ::Autonomia::Automacao::IaNoEnsaio.new(conta: @conta, conversa: @conversa, envio: envio)

  def condicao?(condicao, valores)
    ::Autonomia::Automacao::Condicao.new(condicao, valores).verdadeira?
  end
end
