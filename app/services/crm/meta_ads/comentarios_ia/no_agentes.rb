# IA cuida dos comentários em Agentes (#2469, PR 3a do #2436): o cuidado de cada post ou anúncio, no Instagram e no
# Facebook, vira um cartão na lista de Agentes, com uma página de três gavetas (O que sabe, Testar, Comentários).
#
# - `item`: o que a lista conta, só do banco (sem Meta e sem IA): o alvo, a rede e o estado. O cabeçalho de Agentes conta
#   "cuidando de post" pelos ligados; o pausado entra em "parado".
# - `detalhe`: o que o cartão e a página mostram, lido na Meta na hora (Fonte), sem IA: a legenda, a capa, o que a foto
#   mostra (a leitura já gravada, Foto.texto_para_ia), a porta de cada rede (Porta: o agente e, quando ele não escreve,
#   por quê) e os comentários do Painel, nos grupos da tela. Uma conta só para o cartão, a gaveta e a página:
#   "esperando você" é o que ficou com o dono (Painel `to_see`), menos o que a IA leu e viu que não era o caso, que vai
#   para "não respondo" junto com o que ela escondeu.
# - `testar`: o agente da porta escreve de verdade (Escrita, a mesma do motor e da prévia), no formato do comentário
#   público ou do privado, sem publicar nada e sem gravar nada. O privado só onde o motor o manda (Painel::PRIVADO_LIBERADO):
#   no Facebook ele ainda não sai (F4), e o Testar diz isso em vez de mostrar um privado que nunca iria.
class Crm::MetaAds::ComentariosIa::NoAgentes
  FORMATOS = { 'publico' => Crm::MetaAds::ComentariosIa::Escrita::FORMATO::PUBLICO,
               'privado' => Crm::MetaAds::ComentariosIa::Escrita::FORMATO::PRIVADO }.freeze
  NAO_ERA_O_CASO = 'skipped'.freeze

  def self.item(care)
    { id: care.id, kind: care.target_kind, target_id: care.target_id, network: care.network, status: care.status,
      perfil: (SeusPosts::Perfil.id_do(care.inbox.channel) if care.target_kind == 'post' && care.inbox) }
  end

  # care: o cuidado. alvo e fonte: os do Painel (Fonte.post ou Fonte.anuncio). painel: o Painel do mesmo alvo.
  def initialize(care:, fonte:, painel:)
    @care = care
    @fonte = fonte
    @painel = painel
  end

  def detalhe
    self.class.item(@care).merge(legenda: @fonte.legenda, capa: @fonte.capa, foto: foto, nota: @care.note.to_s,
                                 portas: portas, comentarios: comentarios)
  end

  # pergunta: o texto do dono, que entra como o comentário (dado de terceiro, como no motor). formato: 'publico' ou
  # 'privado'. network: a rede do Testar (no anúncio nas duas redes, o dono escolhe; com uma rede só, ela).
  def testar(pergunta:, formato:, network:)
    chave, rede = rede_do_teste(network)
    return { status: 'invalid_network' } if chave.nil?
    return { status: 'no_private' } if formato == 'privado' && !privado?(chave)

    escrito = escrita(chave, rede).escrever(FORMATOS.fetch(formato), comentario: pergunta)
    { status: escrito.status.to_s, texto: escrito.texto, motivo: escrito.motivo }.compact
  end

  private

  def portas
    @fonte.redes.map do |network, rede|
      porta = Crm::MetaAds::ComentariosIa::Porta.new(care: @care, inbox: caixa(rede[:inbox_id]))
      agente = porta.agente
      { network: network, inbox_id: rede[:inbox_id], private: privado?(network), motivo: porta.motivo,
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
    { status: payload[:status], results: payload[:results],
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

  def escrita(network, rede)
    Crm::MetaAds::ComentariosIa::Escrita.new(
      care: @care, inbox: caixa(rede[:inbox_id]), legenda: @fonte.legenda,
      foto: Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(@care.account, network, rede[:post_id])
    )
  end

  def privado?(network)
    Crm::MetaAds::ComentariosIa::Painel::PRIVADO_LIBERADO.include?(network)
  end

  def caixa(inbox_id)
    Inbox.find_by(id: inbox_id, account_id: @care.account_id)
  end
end
