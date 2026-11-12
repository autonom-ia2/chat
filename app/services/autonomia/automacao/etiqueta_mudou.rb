# G10 (F8.7, #2499): a etiqueta posta ou tirada, como gatilho, na conversa e no contato. Quatro gatilhos:
# `conversa.etiqueta_posta`, `conversa.etiqueta_tirada`, `contato.etiqueta_posta` e `contato.etiqueta_tirada`, cada um
# com a etiqueta escolhida (`etiqueta`, o nome, como a conversa e o contato a guardam).
#
# De onde vem: o conversation.updated e o contact.updated que o registro despacha no commit, com o `label_list` de antes
# e o de agora no `changed_attributes` (o previous_changes). Cada etiqueta que entrou é uma "posta"; cada uma que saiu,
# uma "tirada". Vale qualquer caminho que grava o registro (a tela, a ação em lote, a API, uma automação).
#
# Não dispara (só a escrita que passa pelo modelo despacha o evento): a importação da base de campanha
# (CampaignImports::BulkContactLabeler grava as etiquetas em lote, sob Current.suppress_contact_events), apagar ou
# renomear a etiqueta da conta (Labels::DestroyService e Labels::UpdateService, em lote) e o registro que nasce com
# etiqueta (é o conversation.created ou o contact.created). O renomear também não chega aqui como pôr e tirar: o spec
# "renomear a etiqueta da conta" prova. Renomear leva o nome novo ao gatilho, e apagar desliga a automação ligada
# (Autonomia::Automacao::EtiquetaDoGatilho).
#
# A marca: `<tipo>:<id do registro>:<etiqueta>:<instante do despacho em µs>`. O EventDispatcherJob repete o mesmo
# instante, então o evento entregue duas vezes abre uma execução só; pôr, tirar e pôr de novo são três fatos.
module Autonomia::Automacao::EtiquetaMudou
  POSTA = { 'Conversation' => 'conversa.etiqueta_posta', 'Contact' => 'contato.etiqueta_posta' }.freeze
  TIRADA = { 'Conversation' => 'conversa.etiqueta_tirada', 'Contact' => 'contato.etiqueta_tirada' }.freeze

  module_function

  # `registro`: a conversa ou o contato. `mudou`: o `changed_attributes` do evento. `instante`: o do despacho.
  def comecar(registro, mudou, instante)
    antes, agora = mudou.to_h.with_indifferent_access['label_list']
    return unless registro && antes.is_a?(Array) && agora.is_a?(Array)

    tipo = registro.class.base_class.name
    (agora - antes).each { |etiqueta| partir(registro, POSTA.fetch(tipo), etiqueta, instante) }
    (antes - agora).each { |etiqueta| partir(registro, TIRADA.fetch(tipo), etiqueta, instante) }
  end

  def partir(registro, tipo, etiqueta, instante)
    marca = "#{tipo}:#{registro.id}:#{etiqueta}:#{instante.utc.iso8601(6)}"
    ::Autonomia::Automacao::Escuta.comecar(registro, tipo, evento: marca, dados: { 'etiqueta' => etiqueta })
  end
end
