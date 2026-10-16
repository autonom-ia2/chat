# O texto de uma mensagem para o histórico da IA (#1715). Localização e contato (chat#1473, e o "+" do atendente no
# #1702) vão com `content` vazio, e o dado fica em `content_attributes.rich_message`; sem isto, o item saía vazio e o
# teto do histórico o descartava: a IA não sabia que a equipe mandou uma localização ou um contato.
#
# Com `content` vazio e `rich_message` de localização ou contato, monta um resumo:
#   { "type": "location", "latitude": ..., "longitude": ..., "name": "...", "address": "..." } -> "Localização: nome — endereço"
#   { "type": "contact", "name": "...", "phone": "...", "wa_id": "..." }                       -> "Contato: nome"
# O TELEFONE do contato nunca entra (o contrato não tem e-mail). Se o número já foi escrito na conversa, o modelo já o
# lê naquela mensagem e o resumo não acrescenta nada; se não foi, seria dado novo levado ao modelo sem necessidade.
# Coordenadas também não entram: sem nome nem endereço, o resumo diz só que foi uma localização.
# Os outros tipos levam o texto em `content` e não passam por aqui. Só a Fase 2 chama (PessoaDaEquipe); a moldura
# (pessoa, celular) ou o papel (IA, envio automático) é de quem chama.
module Autonomia::Agents::Operate::ResumoDaMensagemRica
  LOCALIZACAO = 'Localização'.freeze
  LOCALIZACAO_SEM_NOME = 'Localização (sem nome nem endereço)'.freeze
  CONTATO = 'Contato'.freeze
  SEPARADOR = ' — '.freeze

  module_function

  # O `content` da mensagem, ou o resumo do formato quando ele está vazio; '' quando não há nem um nem outro.
  def texto(message)
    conteudo = message.content.to_s
    return conteudo if conteudo.present?

    resumo(message.content_attributes.to_h[RichMessages::KEY]) || conteudo
  end

  def resumo(payload)
    return unless payload.is_a?(Hash)

    case payload['type']
    when 'location' then localizacao(payload)
    when 'contact' then contato(payload)
    end
  end

  def localizacao(payload)
    partes = [linha(payload['name']), linha(payload['address'])].compact_blank
    partes.empty? ? LOCALIZACAO_SEM_NOME : "#{LOCALIZACAO}: #{partes.join(SEPARADOR)}"
  end

  def contato(payload)
    nome = linha(payload['name'])
    "#{CONTATO}: #{nome}" if nome.present?
  end

  # Texto numa linha só, com os espaços unificados; o que não é texto conta como ausente.
  def linha(valor)
    valor.split.join(' ') if valor.is_a?(String)
  end
end
