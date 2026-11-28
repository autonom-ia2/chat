# A LIBERAÇÃO DO AGENTE CONTRATADO (#3270), por conta e por modelo: a marca que o super admin liga quando a fatura da
# Hub2You está paga, ou para a conta liberada sem cobrança. Conta liberada nunca pausa e não mostra a contagem dos dias
# grátis (`Contratados::Gratis`).
#
# Mesmo desenho do nicho (`Autonomia::Agents::Nicho`): fica no jsonb interno `accounts.internal_attributes`, numa lista
# com as chaves dos modelos liberados, e só o formulário do super admin escreve (`ContratadosLiberadosField`). Chave fora
# do catálogo não entra, nem na leitura nem na escrita.
module Autonomia::Agents::Contratados::Liberacao
  CHAVE = 'autonomia_contratados_liberados'.freeze

  module_function

  # -> as chaves do catálogo liberadas na conta, na ordem do catálogo.
  def modelos(account)
    gravados = Array(account.internal_attributes.to_h[CHAVE]).map(&:to_s)
    Autonomia::Agents::Contratados::MODELOS.keys & gravados
  end

  def liberado?(account, chave)
    modelos(account).include?(chave.to_s)
  end

  # Atribui a lista do formulário em `internal_attributes`, sem salvar e sem tocar nas outras chaves. Só as chaves do
  # catálogo ficam; lista vazia desliga todas.
  def atribuir(account, chaves)
    escolhidas = Autonomia::Agents::Contratados::MODELOS.keys & Array(chaves).map(&:to_s)
    account.internal_attributes = account.internal_attributes.to_h.merge(CHAVE => escolhidas)
  end
end
