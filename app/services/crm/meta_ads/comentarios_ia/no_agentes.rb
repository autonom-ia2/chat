# IA cuida dos comentários em Agentes (#2469, PR 3a do #2436): o cuidado de cada post ou anúncio, no Instagram e no
# Facebook, vira um cartão na lista de Agentes, com uma página de três gavetas (O que sabe, Testar, Comentários).
#
# - `item`: o que a lista conta, só do banco (sem Meta e sem IA): o alvo, a rede e o estado. O cabeçalho de Agentes conta
#   "cuidando de post" pelos ligados; o pausado entra em "parado".
# - `detalhe`: o que o cartão e a página mostram, lido na Meta na hora (Fonte), sem IA: a legenda, a capa, o que a foto
#   mostra (a leitura já gravada, Foto.texto_para_ia), a porta de cada rede (Porta: o agente e, quando ele não escreve,
#   por quê) e os comentários do Painel, nos grupos da tela. Uma conta só para o cartão, a gaveta e a página:
#   "esperando você" é o que ficou com o dono (Painel `to_see`), menos o que a IA leu e viu que não era o caso, que vai
#   para "não respondo" junto com o que ela escondeu. "No privado" (#2481) lista as conversas do privado que a pessoa
#   vê (NoPrivado), com quem, o comentário e o "Ver conversa".
# - `testar` (#2510): o que o motor faria com o comentário, na ordem do motor (Cuidar#decidir e #executar), sem publicar
#   nada e sem gravar nada. Primeiro a decisão, pelo mesmo Classificador, com o "para quem", a ficha e o assunto
#   proibido do cuidado (o uso da IA vai em FEATURE_DA_TELA); depois, só quando a decisão é mandar o privado e ele sai
#   naquela rede, o que o agente da porta escreveria (Escrita#textos, a mesma do motor): a mensagem do privado e a frase
#   do comentário, ou as frases fixas do dono, ou "fica com você" quando o agente não sabe. O dono não escolhe onde a
#   resposta sai: quem escolhe é a decisão, como no motor.
class Crm::MetaAds::ComentariosIa::NoAgentes
  NAO_ERA_O_CASO = 'skipped'.freeze
  RECEBE = %w[private price].freeze
  # Sem certeza suficiente o motor não decide: o comentário fica com o dono ("não cuidei").
  SEM_CERTEZA = 'sem_certeza'.freeze
  # Era o caso do privado, mas ele não sai nesta rede (a Página sem a pages_messaging, #2307): nada é publicado, fica
  # com o dono.
  SEM_PRIVADO_NA_REDE = 'no_private'.freeze

  def self.item(care)
    { id: care.id, kind: care.target_kind, target_id: care.target_id, network: care.network, status: care.status,
      perfil: (SeusPosts::Perfil.id_do(care.inbox.channel) if care.target_kind == 'post' && care.inbox) }
  end

  # care: o cuidado. alvo e fonte: os do Painel (Fonte.post ou Fonte.anuncio). painel: o Painel do mesmo alvo.
  # no_privado: a lista do grupo "no privado" (NoPrivado).
  def initialize(care:, fonte:, painel:, no_privado:)
    @care = care
    @fonte = fonte
    @painel = painel
    @no_privado = no_privado
  end

  def detalhe
    self.class.item(@care).merge(legenda: @fonte.legenda, capa: @fonte.capa, foto: foto, nota: @care.note.to_s,
                                 portas: portas, comentarios: comentarios)
  end

  # pergunta: o texto do dono, que entra como o comentário (dado de terceiro, como no motor). network: a rede do Testar
  # (no anúncio nas duas redes, o dono escolhe; com uma rede só, ela). Devolve `decisao` (a chave do Classificador,
  # SEM_CERTEZA, SEM_PRIVADO_NA_REDE ou Cuidar::FICA_COM_O_DONO), `motivo` (o porquê escrito pela IA) e, quando a
  # decisão é mandar o privado, `escrita` (Escrita#textos). Classificador::Erro sobe: a tela diz que a IA não respondeu.
  def testar(pergunta:, network:)
    chave, rede = rede_do_teste(network)
    return { status: 'invalid_network' } if chave.nil?

    avaliacao = classificador(chave, rede).avaliar!(pergunta)
    decisao = decisao_do_motor(avaliacao&.chave, chave)
    # Sem certeza, o porquê é o de uma escolha que não vale: a tela não o mostra.
    { status: 'ready', decisao: decisao, motivo: (avaliacao.motivo if avaliacao&.chave),
      escrita: (escrita_do_privado(decisao, chave, rede, pergunta) if RECEBE.include?(decisao)) }.compact
  end

  private

  def portas
    @fonte.redes.map do |network, rede|
      inbox = caixa(rede[:inbox_id])
      porta = Crm::MetaAds::ComentariosIa::Porta.new(care: @care, inbox: inbox)
      agente = porta.agente
      # #2487: o nome da caixa, para a tela dizer o motivo de verdade ("No Instagram, a caixa X não tem agente atendendo").
      { network: network, inbox_id: rede[:inbox_id], caixa: inbox&.name, private: privado?(network), motivo: porta.motivo,
        agente: agente && { id: agente.id, name: agente.name } }
    end
  end

  def foto
    network, rede = @fonte.redes.first
    rede && Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@care.account, network, rede[:post_id])
  end

  def comentarios
    payload = @painel.payload
    to_see = Array(payload[:to_see])
    # #2522: o status de cada rede, para a gaveta avisar qual faltou no anúncio nas duas redes.
    { status: payload[:status], network_status: payload[:network_status], results: payload[:results], no_privado: @no_privado.call,
      esperando: to_see.reject { |linha| linha[:kind] == NAO_ERA_O_CASO },
      nao_respondo: to_see.select { |linha| linha[:kind] == NAO_ERA_O_CASO } + Array(payload[:hidden]).map { |linha| linha.merge(kind: 'hidden') } }
  end

  def rede_do_teste(network)
    chave = network.presence || rede_unica
    [chave, @fonte.redes[chave]] if chave && @fonte.redes.key?(chave)
  end

  def rede_unica
    @fonte.redes.keys.sole if @fonte.redes.size == 1
  end

  # As mesmas guardas do Cuidar#decidir: o privado só com o que mandar (ficha ou "para quem") e na rede que o libera.
  def decisao_do_motor(chave_da_ia, network)
    return SEM_CERTEZA if chave_da_ia.nil?
    return chave_da_ia unless RECEBE.include?(chave_da_ia)
    return SEM_PRIVADO_NA_REDE unless privado?(network)

    @care.privado? ? chave_da_ia : Crm::MetaAds::ComentariosIa::Cuidar::FICA_COM_O_DONO
  end

  # { status: 'escrito', privado:, publico:, material: } | { status: 'fica_com_o_dono', motivo: } |
  # { status: 'frases_fixas', motivo:, privado:, publico: } (a mensagem e a frase do dono, como o motor manda; o botão
  # que o motor põe junto no privado não aparece no teste).
  def escrita_do_privado(decisao, network, rede, pergunta)
    escrita = escrita(network, rede)
    textos = escrita.textos(decisao, comentario: pergunta)
    return { status: 'fica_com_o_dono', motivo: textos[:dono] } if textos.key?(:dono)
    return frases_fixas(decisao, escrita.recuo) if textos.empty?

    { status: 'escrito', privado: textos[:privado], publico: textos[:publico] || @care.price_reply.presence,
      material: textos[:material].presence }.compact
  end

  def frases_fixas(decisao, motivo)
    { status: 'frases_fixas', motivo: motivo, privado: @care.texto_do_privado, publico: @care.resposta_publica(decisao, 0) }
  end

  def classificador(network, rede)
    Crm::MetaAds::ComentariosIa::Classificador.new(care: @care, legenda: legenda, foto: foto_da_rede(network, rede), tela: true)
  end

  def escrita(network, rede)
    Crm::MetaAds::ComentariosIa::Escrita.new(care: @care, inbox: caixa(rede[:inbox_id]), legenda: legenda,
                                             foto: foto_da_rede(network, rede))
  end

  # Lida na Meta uma vez por teste: a decisão e a escrita leem a mesma.
  def legenda
    return @legenda if defined?(@legenda)

    @legenda = @fonte.legenda
  end

  def foto_da_rede(network, rede)
    Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@care.account, network, rede[:post_id])
  end

  # Pela caixa da rede (#2307): no Facebook, a Página com a `pages_messaging` concedida.
  def privado?(network)
    Crm::MetaAds::ComentariosIa::Rede.privado_na_fonte?(@care.account, network, @fonte)
  end

  def caixa(inbox_id)
    Inbox.find_by(id: inbox_id, account_id: @care.account_id)
  end
end
