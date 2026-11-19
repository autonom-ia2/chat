# #2556: o aviso, no editor da automação, dos cards ou contatos que o gatilho de data (Tempo::Data) deixou de fora
# porque o campo tem a data escrita em outro formato. Sem ele, o dono não sabia: a automação só não chegava a parte dos
# clientes.
#
# A varredura conta uma vez por dia e grava aqui a contagem, o tipo do gatilho, o campo e o dia; nunca o valor, que é
# dado do cliente. Fica no Redis, e não no histórico (Registro), porque o histórico pede uma execução e a contagem não
# é de nenhuma. Vale 2 dias: a contagem do dia seguinte troca a de hoje, e a automação desligada (sem varredura) para de
# avisar sozinha. Sem nenhum inválido, a chave some, e o aviso também.
module Autonomia::Automacao::Tempo::DatasInvalidas
  VALIDADE = 2.days

  module_function

  def chave(definicao_id) = "automacao:tempo:datas_invalidas:aviso:#{definicao_id}"

  def gravar(definicao, quantos:, tipo:, campo:, dia:)
    return Redis::Alfred.delete(chave(definicao.id)) if quantos.zero?

    aviso = { quantos: quantos, tipo: tipo, campo: campo, dia: dia.iso8601 }
    Redis::Alfred.set(chave(definicao.id), aviso.to_json, ex: VALIDADE.to_i)
  end

  # O campo vai pelo nome que a pessoa vê na tela, não pela chave.
  def para_tela(definicao)
    aviso = do_gatilho_de_agora(definicao)
    return if aviso.nil?

    do_card = ::Autonomia::Automacao::Gatilhos.do_card?(aviso['tipo'])
    { quantos: aviso['quantos'], alvo: do_card ? 'card' : 'contato',
      campo: nome_do_campo(definicao.account, do_card ? :card_attribute : :contact_attribute, aviso['campo']) }
  end

  # A contagem gravada, se ainda é do gatilho de agora: trocar o tipo ou o campo cala a velha até a próxima varredura.
  def do_gatilho_de_agora(definicao)
    gravado = Redis::Alfred.get(chave(definicao.id))
    return if gravado.nil?

    aviso = JSON.parse(gravado)
    gatilho = definicao.versao_ativa&.receita&.dig('gatilho') || {}
    aviso if aviso.values_at('tipo', 'campo') == gatilho.values_at('tipo', 'campo')
  end

  def nome_do_campo(conta, modelo, chave)
    conta.custom_attribute_definitions.find_by(attribute_model: modelo, attribute_key: chave)&.attribute_display_name || chave
  end
end
