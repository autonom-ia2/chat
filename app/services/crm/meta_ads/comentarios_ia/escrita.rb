# IA cuida dos comentários (#2458, PR 2 do #2436): a IA escreve a frase do comentário e a mensagem do privado para cada
# comentário, em vez das frases fixas do dono. Quem escreve é o agente da porta da caixa em que o comentário chegou
# (a do cuidado do post; no anúncio, a da rede do comentário), pelo
# Autonomia::Agents::Answerer no formato do comentário (Answerer::FormatoDoComentario), com a base dele (Retriever), sem
# ferramenta, sem busca na web e com o portão de confiança: o que o agente não sabe fica com o dono.
#
# - Atrás da flag do cuidado (Cuidar::FLAG, meta_ads_comentarios_ia): sem chave nova, decisão do Rodrigo (01/11). Quem
#   chama confere `ligada?`.
# - Recuo para as frases fixas, nunca mudo, pelos motivos da Porta (#2469: a mesma regra da tela de Agentes). O motivo
#   vai ao log só com ids (`recuo`), e o resultado diz qual foi.
# - O comentário, o de cima e o que se vê na foto são dado de terceiro: vão numa linha só, com o código do cuidado
#   (FormatoDoComentario.linha). O que o dono escreveu (a ficha, a nota, o tom) vai na regra do turno, como do dono.
# - A chave é sempre a da própria conta (ChaveDaConta, como o Classificador): sem ela, as frases fixas.
# - IA fora do ar: Classificador::Indisponivel, e o motor tenta de novo pelo job, antes de qualquer envio.
class Crm::MetaAds::ComentariosIa::Escrita
  # Só a etiqueta de custo da IA; a flag é a do cuidado.
  FEATURE = 'meta_ads_comentarios_ia_escreve'.freeze
  FORMATO = Autonomia::Agents::Answerer::FormatoDoComentario

  # status: :escrito (texto), :fica_com_o_dono (motivo: o agente não sabe, ou a resposta fora do formato) ou
  # :frases_fixas (motivo do recuo). material (#2487): no escrito, o nome dos arquivos só deste post ou anúncio de que a
  # resposta saiu ("Do seu material: …" no Testar).
  Resultado = Struct.new(:status, :texto, :motivo, :material, keyword_init: true) do
    def escrito? = status == :escrito
    def fica_com_o_dono? = status == :fica_com_o_dono
  end

  def self.ligada?(account)
    account&.feature_enabled?(Crm::MetaAds::ComentariosIa::Cuidar::FLAG) == true
  end

  # O passo 2 da tela, no Painel: o que gravar do que veio ({ temas:, assunto_proibido:, tom: }, só os que vieram:
  # pausar não apaga), e o que devolver (`writes`: a IA escreve as respostas). Sem a flag do cuidado, nada.
  def self.do_passo_2(account, escrita)
    return {} unless ligada?(account)

    escrita.slice(:temas, :assunto_proibido, :tom).to_h do |campo, valor|
      [campo, campo == :temas ? Array(valor).map { |tema| tema.to_s.strip }.compact_blank : valor.to_s.strip.presence]
    end
  end

  def self.no_painel(account, care)
    return {} unless ligada?(account)

    { writes: true, temas: Array(care.temas), assunto_proibido: care.assunto_proibido.to_s, tom: care.tom.to_s }
  end

  # inbox: a caixa em que o comentário chegou. legenda: o texto do post, lido na Meta. foto: o que a foto do post mostra
  # (Foto#texto_para_ia).
  def initialize(care:, inbox:, legenda: nil, foto: nil)
    @care = care
    @inbox = inbox
    @legenda = legenda.to_s.strip.presence
    @foto = foto.to_s.strip.presence
  end

  # Os dois textos de um comentário que recebe o privado (decisao 'private' ou 'price'), escritos ANTES de qualquer
  # envio: { privado:, publico:, material: }; { dono: motivo } quando o agente não sabe; {} nas frases fixas. O preço
  # que o dono escreveu (`price_reply`) vale no lugar da frase pública: só o privado é escrito. `material` (#2487, o
  # Testar em Agentes): os arquivos só deste post de que as respostas saíram; o motor não o usa.
  def textos(decisao, comentario:, pai: nil)
    privado = escrever(FORMATO::PRIVADO, comentario: comentario, pai: pai)
    return {} if privado.status == :frases_fixas
    return { dono: privado.motivo } if privado.fica_com_o_dono?
    return { privado: privado.texto, material: privado.material } if decisao == 'price' && @care.price_reply.present?

    publico = escrever(FORMATO::PUBLICO, comentario: comentario, pai: pai)
    return { dono: publico.motivo } if publico.fica_com_o_dono?

    { privado: privado.texto, publico: publico.texto, material: (privado.material | publico.material) }
  end

  # formato: FORMATO::PUBLICO ou FORMATO::PRIVADO. comentario: o texto de quem comentou; pai: o comentário de cima.
  def escrever(formato, comentario:, pai: nil)
    motivo = recuo
    return Resultado.new(status: :frases_fixas, motivo: motivo) if motivo

    responder(formato, comentario, pai)
  end

  # O motivo das frases fixas, ou nil quando o agente da porta escreve. Uma vez por cuidado neste objeto.
  def recuo
    return @recuo if defined?(@recuo)

    @recuo = motivo_do_recuo
    Rails.logger.info("[comentarios_ia] frases fixas motivo=#{@recuo} account=#{@care.account_id} care=#{@care.id}") if @recuo
    @recuo
  end

  private

  # A regra de quem escreve é uma só, a da Porta (#2469): o motor e a tela de Agentes leem a mesma.
  def motivo_do_recuo
    porta.motivo
  end

  def agente
    porta.agente
  end

  def porta
    @porta ||= Crm::MetaAds::ComentariosIa::Porta.new(care: @care, inbox: @inbox)
  end

  def responder(formato, comentario, pai)
    # Na prévia o cuidado ainda não tem id: o código sai da conta, nunca o mesmo para todas.
    codigo = FORMATO.codigo(@care.id || "previa-#{@care.account_id}")
    resultado = Autonomia::Agents::Answerer.new(
      agent: agente, query: FORMATO.linha(dado(comentario, pai), codigo), retrieval_query: comentario.to_s,
      allow_web_search: false, trust_instruction: false, audience: :customer, delivery: nil, feature: FEATURE,
      contexto_do_turno: [FORMATO.regra_do_dado(codigo), do_dono].compact.join("\n\n"), formato: formato, care_id: @care.id
    ).answer
    raise Crm::MetaAds::ComentariosIa::Classificador::Indisponivel, 'writing_unavailable' if resultado.error.present?

    desfecho(resultado, formato, codigo)
  end

  def desfecho(resultado, formato, codigo)
    return com_o_dono('agent_handoff', formato, resultado.handoff[:reason].presence) if resultado.handoff[:should]

    texto = FORMATO.publicavel(resultado.reply, formato, codigo)
    return com_o_dono('reply_out_of_format', formato) if texto.nil?

    Resultado.new(status: :escrito, texto: texto, material: material_do_cuidado(resultado.used_knowledge))
  end

  # Dos trechos que a resposta usou, o nome dos arquivos que são só deste cuidado.
  def material_do_cuidado(usados)
    ids = Array(usados).filter_map { |usado| usado[:id] }
    return [] if ids.empty? || @care.id.nil?

    Autonomia::Agents::Source.where(care_id: @care.id, account_id: @care.account_id,
                                    id: Autonomia::Agents::KnowledgeEntry.where(id: ids).select(:source_id))
                             .order(:id).pluck(:reference).compact_blank.uniq
  end

  # Nunca mudo: o log diz por que ficou com o dono, só com ids (o motivo escrito pelo modelo não vai ao log).
  def com_o_dono(tipo, formato, motivo = nil)
    Rails.logger.info("[comentarios_ia] fica com o dono motivo=#{tipo} formato=#{formato} account=#{@care.account_id} care=#{@care.id}")
    Resultado.new(status: :fica_com_o_dono, motivo: motivo || tipo)
  end

  # O que é de terceiro (ou pode copiar texto de terceiro): o comentário, o de cima, a foto. A legenda é do dono, mas vai
  # junto, como contexto do post.
  def dado(comentario, pai)
    { comentario: comentario, comentario_de_cima: pai, legenda_do_post: @legenda, o_que_se_ve_na_foto: @foto }.compact
  end

  # O que o dono escreveu na tela: a ficha, a nota, o tom e o assunto em que a IA não toca. Texto do dono, nunca do
  # comentário.
  def do_dono
    partes = [ficha, nota, tom, proibido].compact
    return if partes.empty?

    "O QUE O DONO DO POST DISSE (vale como orientação dele): #{partes.join(' ')}"
  end

  def ficha
    oferta = @care.offer.to_h
    return if oferta['offer'].blank?

    ["O post oferece: #{oferta['offer']}.", oferta['price'].presence && "Preço: #{oferta['price']}.",
     oferta['how'].presence && "Como comprar: #{oferta['how']}."].compact.join(' ')
  end

  def nota
    "Nota do dono: #{@care.note}." if @care.note.present?
  end

  def tom
    "Tom pedido pelo dono para todas as respostas: #{@care.tom}." if @care.tom.present?
  end

  # O Classificador já deixa com o dono o comentário sobre esse assunto (owner_topic). Aqui é a segunda trava: se ele
  # errar, o agente passa em vez de falar do assunto, inclusive em público.
  def proibido
    return if @care.assunto_proibido.blank?

    "Assunto em que o dono não quer resposta automática: #{@care.assunto_proibido}. Não fale disso. Se o comentário " \
      'for sobre esse assunto, should_handoff=true, e o dono responde.'
  end
end
