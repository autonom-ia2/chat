# Grava a leitura de UMA conversa no formato do painel de desempenho (#2301), o mesmo da carga
# (Autonomia::Desempenho::Procuras): os campos de filtro em coluna, cortes, resumo e porquê em `dados`.
#
# Numa transação: apaga as procuras daquela conversa e daquele agente (de qualquer lote, a carga inclusive), grava as
# novas no lote da leitura automática e atualiza a leitura da conversa (lida até a última mensagem lida).
#
# `inicio` e `fim` voltam do modelo como 'MM-DD HH:MM' (UTC, o horário da transcrição): o início é a primeira
# mensagem daquele minuto, o fim a última. Horário que não é de nenhuma mensagem recusa a leitura (Esquema::Invalida).
class Autonomia::Desempenho::LeituraAutomatica::Gravacao
  LOTE = 'leitura_automatica'.freeze

  # `mensagens`: as que a leitura viu, em ordem.
  def initialize(ficha:, conversa:, mensagens:, esquema:)
    @ficha = ficha
    @conversa = conversa
    @mensagens = mensagens
    @esquema = esquema
  end

  def lida_ate = @mensagens.last&.created_at || @conversa.created_at

  # `procuras`: o que o Esquema conferiu ([{papel => valor}]).
  def gravar!(procuras)
    linhas = procuras.each_with_index.map { |procura, indice| linha(procura, indice + 1) }
    Autonomia::Desempenho::Procura.transaction do
      escopo(Autonomia::Desempenho::Procura).delete_all
      linhas.each { |atributos| Autonomia::Desempenho::Procura.create!(atributos) }
      marcar!('lida')
    end
  end

  # A conversa não foi lida (grande demais, ou falhou duas vezes seguidas): as procuras de antes ficam, e a leitura
  # anda até a última mensagem para a conversa só voltar quando tiver mensagem nova.
  def nao_lida!
    marcar!('nao_lida')
  end

  private

  def sujeito = { account_id: @ficha.account_id, sujeito_type: @ficha.sujeito_type, sujeito_id: @ficha.sujeito_id }

  def escopo(classe) = classe.where(**sujeito, conversation_id: @conversa.id)

  def marcar!(status)
    leitura = escopo(Autonomia::Desempenho::Leitura).first_or_initialize
    leitura.update!(lida_ate_em: lida_ate, versao_ficha: @ficha.versao, status: status, lote: LOTE)
  end

  # O papel da leitura -> a coluna da procura.
  COLUNAS = { 'quem' => :quem_id, 'origem' => :origem_id, 'pedido' => :pedido_id, 'tema' => :tema_id, 'resultado' => :resultado_id,
              'qualidade' => :qualidade_id }.freeze
  LISTAS = { 'marcos' => :marcos, 'motivos' => :motivo_ids, 'regras' => :regra_ids }.freeze
  SIM_OU_NAO = %w[teste perda_evitavel precisava_pessoa teve_pessoa].freeze

  def linha(procura, ordem)
    atributos = sujeito.merge(conversation_id: @conversa.id, ordem: ordem, versao_ficha: @ficha.versao, lote: LOTE, anuncio_id: anuncio_id,
                              inicio_em: instante(procura['inicio'], :first), fim_em: instante(procura['fim'], :last),
                              dados: dados(procura))
    COLUNAS.each { |papel, coluna| atributos[coluna] = procura[papel] }
    LISTAS.each { |papel, coluna| atributos[coluna] = Array(procura[papel]) }
    SIM_OU_NAO.each { |papel| atributos[papel.to_sym] = procura[papel] == true }
    conferir_horarios!(atributos)
    atributos
  end

  def dados(procura)
    { 'cortes' => @esquema.cortes(procura), 'resumo' => procura['resumo'], 'por_que' => procura['por_que'].presence }
  end

  # 'MM-DD HH:MM' (ou com T, como na transcrição) -> a primeira ou a última mensagem daquele minuto.
  def instante(texto, ponta)
    minuto = texto.to_s.strip.tr(' ', 'T')
    no_minuto = @mensagens.select { |m| Autonomia::Desempenho::LeituraAutomatica::Transcricao.minuto(m.created_at) == minuto }
    momento = no_minuto.public_send(ponta)&.created_at
    raise Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida, 'horário fora da conversa' if momento.nil?

    momento
  end

  def conferir_horarios!(atributos)
    return if atributos[:fim_em] >= atributos[:inicio_em]

    raise Autonomia::Desempenho::LeituraAutomatica::Esquema::Invalida, 'fim antes do início'
  end

  # A origem da conversa é o primeiro toque (Crm::MetaAds::Links): o anúncio só entra com os anúncios ligados na ficha.
  def anuncio_id
    return @anuncio_id if defined?(@anuncio_id)

    @anuncio_id = if @ficha.configuracao['anuncios_ligados'] == true
                    Crm::MetaAdLink.where(account_id: @ficha.account_id, conversation_id: @conversa.id, first_touch: true).pick(:ad_id)
                  end
  end
end
