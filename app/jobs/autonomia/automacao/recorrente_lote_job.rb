# Um lote de alvos do gatilho recorrente (#2635, G7): a Partida em cada card ou contato, com a marca da ocorrência. Os
# ids são relidos pela seleção, na conta da automação e só entre os que quem ligou vê: o card que saiu da seleção
# entre a varredura e o lote fica de fora. A automação desligada ou com outro gatilho no meio do caminho não age. A
# Partida confere o resto (quem ligou alcança o alvo, a flag, o Spam) e a marca única (automacao_id, evento) não deixa
# a mesma ocorrência abrir duas execuções no mesmo alvo, mesmo com o lote repetido.
#
# Falha num alvo vai para o log (a classe e a linha, nunca a mensagem) e não para os outros; no fim, o job falha com o
# primeiro erro, para aparecer no Sidekiq. Sem nova tentativa: o lote repetido só refaria o que a marca já barra.
class Autonomia::Automacao::RecorrenteLoteJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  def perform(automacao_id, ids, ocorrencia)
    definicao = ligada_com_recorrente(automacao_id)
    return unless definicao

    tipo = definicao.versao_ativa.receita.dig('gatilho', 'tipo')
    instante = Time.zone.parse(ocorrencia)
    erro = alvos(definicao, instante, ids).filter_map { |alvo| comecar(definicao, alvo, tipo, instante) }.first
    # G55: os ids que não abriram execução contam como fora da campanha da vez.
    ::Autonomia::Automacao::CampanhaDaOcorrencia.lote_feito(definicao, tipo, instante, ids)
    raise erro if erro
  end

  private

  def ligada_com_recorrente(automacao_id)
    definicao = ::Autonomia::Automacao::Definicao.includes(:account, :versao_ativa).find_by(id: automacao_id)
    return unless definicao&.ativa && definicao.versao_ativa

    definicao if ::Autonomia::Automacao::Gatilhos.recorrente?(definicao.versao_ativa.receita.dig('gatilho', 'tipo'))
  end

  def alvos(definicao, instante, ids)
    gatilho = definicao.versao_ativa.receita['gatilho']
    return [definicao.account] if ::Autonomia::Automacao::Gatilhos.da_conta?(gatilho['tipo']) && ids == [definicao.account_id]

    selecao = ::Autonomia::Automacao::Tempo::Selecao.new(definicao.account, gatilho, agora: instante)
    selecao.de_quem_ligou(::Autonomia::Automacao::Acesso.new(definicao)).where(id: ids).to_a
  end

  # O erro do alvo, ou nil.
  def comecar(definicao, alvo, tipo, instante)
    marca = ::Autonomia::Automacao::Gatilhos.marca_do_recorrente(tipo, alvo.id, instante)
    ::Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: tipo, evento: marca).call
    nil
  rescue StandardError => e
    Rails.logger.error("[automacao][recorrente] não começou automacao=#{definicao.id} alvo=#{alvo.class.name}:#{alvo.id} " \
                       "#{e.class} em #{e.backtrace&.first}")
    e
  end
end
