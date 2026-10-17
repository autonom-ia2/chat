# O texto de uma mensagem para o histórico da IA (#1715). Localização e contato (chat#1473, e o "+" do atendente no
# #1702) vão com `content` vazio; sem isto, o item saía vazio e o teto do histórico o descartava: a IA não sabia que a
# equipe (ou o cliente) mandou uma localização ou um contato.
#
# Com `content` vazio, o resumo sai, na ordem, de:
#   1. `content_attributes.rich_message` (o que o painel manda):
#        { "type": "location", "name": "...", "address": "...", ... } -> "Localização: nome — endereço"
#        { "type": "contact", "name": "...", "phone": "...", ... }     -> "Contato: nome — telefone"
#   2. `content_attributes.shared_location` (a localização que o cliente manda pelo WhatsApp oficial, com nome e
#      endereço separados; RichMessages::ReceivedLocation)                   -> "Localização: nome — endereço"
#   3. o ANEXO de localização ou contato (como chegam o eco do app do celular e o que vem do Telegram/Twilio):
#        anexo `location`: `fallback_title` ("nome, endereço", ou vazio)     -> "Localização: nome, endereço"
#        anexo `contact`: nome em `meta` (`firstName`/`lastName` no WhatsApp, `first_name`/`last_name` no Telegram) e
#                         o telefone em `fallback_title`, um anexo por telefone -> "Contato: nome — tel1, tel2"
# Decisões do Rodrigo (17/10/2026): o TELEFONE do contato entra ("tudo"), venha da equipe ou do cliente; as COORDENADAS
# não entram (sem nome nem endereço, o resumo diz só que foi uma localização). No WhatsApp oficial o contato já vem com
# o nome em `content` (formatted_name), e o resumo não roda.
# Limite conhecido: o eco do app em caixa que não é WhatsApp (Instagram/Facebook com `external_echo`) não ganha moldura
# e vai como fala da IA (PessoaDaEquipe só reconhece o eco no WhatsApp).
# Os outros tipos levam o texto em `content` e não passam por aqui. Só a Fase 2 chama (PessoaDaEquipe); a moldura
# (pessoa, celular, automática) ou o papel (IA, cliente) é de quem chama.
module Autonomia::Agents::Operate::ResumoDaMensagemRica
  LOCALIZACAO = 'Localização'.freeze
  LOCALIZACAO_SEM_NOME = 'Localização (sem nome nem endereço)'.freeze
  CONTATO = 'Contato'.freeze
  CONTATO_SEM_NOME = 'Contato (sem nome)'.freeze
  SEPARADOR = ' — '.freeze
  # O que o Chatwoot grava no anexo de contato sem telefone (Whatsapp::IncomingContactMessageHandler#attach_contact).
  SEM_TELEFONE = 'Phone number is not available'.freeze

  module_function

  # O `content` da mensagem, ou o resumo do formato quando ele está vazio; '' quando não há nem um nem outro.
  def texto(message)
    conteudo = message.content.to_s
    return conteudo if conteudo.present?

    atributos = message.content_attributes.to_h
    resumo(atributos[RichMessages::KEY]) || localizacao_compartilhada(atributos[RichMessages::ReceivedLocation::KEY]) ||
      resumo_dos_anexos(message) || conteudo
  end

  def resumo(payload)
    return unless payload.is_a?(Hash)

    case payload['type']
    when 'location' then localizacao(payload)
    when 'contact' then contato(payload)
    end
  end

  def localizacao_compartilhada(payload)
    localizacao(payload) if payload.is_a?(Hash)
  end

  # Um resumo por localização e um por contato (os telefones de um mesmo contato vêm em anexos separados).
  def resumo_dos_anexos(message)
    anexos = message.attachments.to_a
    locais = anexos.select { |anexo| anexo.file_type == 'location' }.map { |anexo| localizacao('name' => anexo.fallback_title) }
    contatos = anexos.select { |anexo| anexo.file_type == 'contact' }.group_by { |anexo| nome_do_contato(anexo.meta) }
                     .map { |nome, grupo| contato('name' => nome, 'phone' => telefones(grupo)) }
    (locais.uniq + contatos).join("\n").presence
  end

  def telefones(anexos)
    anexos.filter_map { |anexo| linha(anexo.fallback_title) }.reject { |fone| fone == SEM_TELEFONE }.uniq.join(', ')
  end

  def nome_do_contato(meta)
    dados = meta.to_h.stringify_keys
    partes = dados.values_at('firstName', 'lastName').compact_blank.presence || dados.values_at('first_name', 'last_name')
    partes.select { |parte| parte.is_a?(String) }.join(' ')
  end

  def localizacao(payload)
    partes = [linha(payload['name']), linha(payload['address'])].compact_blank
    partes.empty? ? LOCALIZACAO_SEM_NOME : "#{LOCALIZACAO}: #{partes.join(SEPARADOR)}"
  end

  def contato(payload)
    partes = [linha(payload['name']), linha(payload['phone'])].compact_blank
    partes.empty? ? CONTATO_SEM_NOME : "#{CONTATO}: #{partes.join(SEPARADOR)}"
  end

  # Texto numa linha só, com os espaços unificados; o que não é texto conta como ausente.
  def linha(valor)
    valor.split.join(' ') if valor.is_a?(String)
  end
end
