# #1428 (tema 6) e #2489 — a resposta do Construtor à pergunta do dono no "Mudar conversando" (Fase 2). Quem diz se a
# fala tem pergunta é o MODELO, pelo campo `dono_perguntou` do schema do ajuste (regra do Rodrigo, 20/09/2026). Só no
# turno com falta, a `resposta_ao_dono` sem pergunta declarada é cortada: ela pode ser um "Pronto" do que não entrou. A
# pergunta do dono é sempre respondida. Sem falta, vai como sempre foi (se não estiver vazia). Na correção, vale o
# `dono_perguntou` da 1ª chamada (a fala é a mesma).
# Texto lido pelo modelo: sem travessão e sem crase.
module Autonomia::Agents::Builder::RespostaAoDono
  RESPOSTA_AO_DONO_DESCRIPTION =
    'Quando a fala do dono traz pedido de mudanca E uma pergunta, a resposta a essa pergunta, curta e em portugues ' \
    'simples. Ela vai ao dono junto com o que foi aplicado. Vazia quando nao ha pergunta. So a resposta a pergunta do ' \
    'dono; nunca confirme mudanca aqui, o que entrou o sistema mostra.'.freeze

  DONO_PERGUNTOU_DESCRIPTION =
    'Sua leitura da ULTIMA fala do dono: true quando, alem do pedido de mudanca, ela traz uma pergunta para voce ' \
    'responder (ex.: "e o que ele faz hoje?"). false quando a fala so pede mudancas, ou quando e so pergunta ' \
    '(so_pergunta=true). Com false, deixe resposta_ao_dono vazia.'.freeze

  module_function

  # O texto que vai ao dono. Decidem o estado (`falta`) e o campo do schema, nunca o texto.
  def texto(resposta, falta:)
    cortada?(resposta, falta: falta) ? '' : resposta['resposta_ao_dono'].to_s.strip
  end

  # Veio preenchida e sai: turno com falta e sem pergunta declarada.
  def cortada?(resposta, falta:)
    falta && resposta['dono_perguntou'] != true && resposta['resposta_ao_dono'].to_s.strip.present?
  end
end
