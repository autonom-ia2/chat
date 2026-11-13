# #3006: a pronta declara se houve leitura pela `situacao`, antes do corte de tamanho do Bound. O pedido inválido
# permite corrigir e consultar de novo; a consulta que falhou é recusa do turno, sem trocar o texto para o modelo.
module Autonomia::Agents::Tools::LeituraDaPronta
  # A última chamada da pronta não trouxe dado; as demais ferramentas mantêm a regra do Answerer.
  def sem_dado? = %w[pedido_invalido nao_consegui_consultar].include?(@situacao_da_pronta)

  # Só o principal pede o registro: a leitura interna do especialista ou ajudante mantém a regra que já tinha.
  def registrar_recusa_da_leitura
    return unless @situacao_da_pronta == 'nao_consegui_consultar'

    ::Autonomia::Agents::Tools::Recusa.registrar(
      'consulta_pronta_indisponivel',
      slug: slug, agente: @agent, conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(@turno_da_leitura)
    )
  end

  # A saída de uma consulta que não chegou na janela: não é dado de sistema (`Answerer#anotar_leitura`).
  def consulta_em_andamento?(output)
    output == ::Autonomia::Agents::Tools::ConsultaNoTurno::EM_ANDAMENTO
  end

  private

  def anotar_saida_pronta(saida, operador, turno)
    return if operador || !@record&.pronta? || consulta_em_andamento?(saida)

    dado = JSON.parse(saida.to_s)
    @situacao_da_pronta = dado['situacao'] if dado.is_a?(Hash)
    @turno_da_leitura = turno
  rescue JSON::ParserError
    # O resultado em segundo plano já pode vir cortado: conserva a regra anterior para essa saída.
    nil
  end
end
