# O ÚNICO ESCRITOR de crm_memoria_fatos (#1601). Quem decide o que gravar (a avaliação, a ferramenta, a pessoa, o
# fechamento do card) passa por aqui, e aqui se decide COMO, sempre do mesmo jeito:
#
#   Crm::Memoria::Gravador.gravar!(atributos) -> Crm::MemoriaFato | nil
#
# - Mesma `idempotency_key` já gravada: nada (o retry do Sidekiq é no-op).
# - Decisão (`tipo: decisao`): acumula; a mesma decisão (mesmo valor) vigente no card não se repete.
# - Sem vigente: nasce vigente.
# - Mesmo valor do vigente: nada; vindo de fonte mais forte, nova versão (a pessoa confirmando o que o cliente disse).
# - Vigente travado (a pessoa corrigiu) e quem grava não é pessoa: vira SUGESTÃO, que a tela mostra como "a IA acha que
#   mudou". A IA nunca grava por cima da pessoa.
# - `base_versao` diferente da versão vigente (alguém mudou o fato entre a leitura e a escrita): sugestão visível.
# - Fonte mais fraca que a do vigente e valor diferente: nasce DIVERGENTE ("cliente informou X, diferente de Y").
# - Senão: nova versão; a anterior expira (expirado_em), não é apagada.
#
# Concorrência: o índice único parcial de vigente. Na corrida, relê e decide de novo uma vez; se perder de novo, sugestão
# visível, nunca um NOOP calado. Escopo contato leva uma trava consultiva curta por (conta, contato), com namespace
# próprio (hashtext), para não colidir com outras travas da conta.
module Crm::Memoria::Gravador
  module_function

  # Aceita o hash de atributos ou as mesmas chaves como palavras-chave.
  def gravar!(atributos = {}, tentativa: 1, **chaves)
    atributos = atributos.to_h.symbolize_keys.merge(chaves)
    return if ja_gravado?(atributos[:idempotency_key])

    Crm::MemoriaFato.transaction(requires_new: true) do
      travar_contato(atributos) if atributos[:escopo] == 'contato'
      decidir_e_gravar!(atributos)
    end
  rescue ActiveRecord::RecordNotUnique => e
    de_novo(atributos, tentativa, e)
  end

  def ja_gravado?(chave)
    chave.present? && Crm::MemoriaFato.exists?(idempotency_key: chave)
  end

  # A corrida com outro escritor: relê e decide de novo; na terceira, sugestão visível.
  def de_novo(atributos, tentativa, erro)
    return if erro.message.include?('idempotency_key')
    raise erro if tentativa > 2

    atributos = atributos.merge(situacao: 'sugestao') if tentativa == 2
    gravar!(atributos, tentativa: tentativa + 1)
  end

  def decidir_e_gravar!(novo)
    return criar!(novo) if novo[:situacao] == 'sugestao'
    return gravar_decisao!(novo) if novo[:tipo] == 'decisao'

    vigente = vigente_de(novo)
    return criar!(novo.merge(situacao: 'vigente')) if vigente.nil?

    acao = acao(novo, vigente)
    return if acao == :nada
    return criar!(novo.merge(situacao: acao.to_s, divergente_de_id: vigente.id)) if %i[sugestao divergente].include?(acao)

    nova_versao!(novo, vigente)
  end

  def acao(novo, vigente)
    forca = Crm::MemoriaFato.forca(novo[:fonte])
    return(forca > vigente.forca ? :versao : :nada) if mesmo_valor?(novo, vigente)
    return :sugestao if bloqueado?(novo, vigente)

    forca < vigente.forca ? :divergente : :versao
  end

  # Travado pela pessoa (e quem grava não é pessoa), ou mudou desde a versão que quem grava viu.
  def bloqueado?(novo, vigente)
    (vigente.travado? && novo[:fonte] != 'pessoa_corrigiu') || (novo[:base_versao].present? && novo[:base_versao].to_i != vigente.versao)
  end

  def nova_versao!(novo, vigente)
    vigente.update!(expirado_em: Time.current)
    criar!(novo.merge(situacao: 'vigente', versao: vigente.versao + 1, substitui_id: vigente.id))
  end

  def gravar_decisao!(novo)
    repetida = escopo_de(novo).vigentes.where(tipo: 'decisao', chave: novo[:chave]).find { |fato| mesmo_valor?(novo, fato) }
    repetida ? nil : criar!(novo.merge(situacao: 'vigente'))
  end

  def criar!(novo)
    agora = Time.current
    Crm::MemoriaFato.create!(
      novo.except(:base_versao).merge(registrado_em: agora, valido_desde: novo[:valido_desde] || agora,
                                      valor: novo[:valor] && Crm::Memoria::Normal.linha(novo[:valor]),
                                      prova_trecho: novo[:prova_trecho]&.first(Crm::MemoriaFato::VALOR_MAXIMO),
                                      item_ref: novo[:item_ref].to_s, status: novo[:status] || 'alegado')
    )
  end

  def vigente_de(novo)
    escopo_de(novo).vigentes.where.not(tipo: 'decisao').find_by(chave: novo[:chave], item_ref: novo[:item_ref].to_s)
  end

  def escopo_de(novo)
    Crm::MemoriaFato.where(account_id: novo[:account_id], contact_id: novo[:contact_id], escopo: novo[:escopo],
                           card_id: novo[:card_id], conversation_id: novo[:conversation_id])
  end

  def mesmo_valor?(novo, fato)
    Crm::Memoria::Normal.chave(novo[:valor]) == Crm::Memoria::Normal.chave(fato.valor) && novo[:valor_json] == fato.valor_json
  end

  def travar_contato(atributos)
    sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?), ?)',
                                                 "crm_memoria:#{atributos[:account_id]}", atributos[:contact_id].to_i])
    ActiveRecord::Base.connection.execute(sql)
  end
end
