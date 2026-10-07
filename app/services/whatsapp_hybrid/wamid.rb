require 'base64'

# Lê o id físico da mensagem de dentro de um wamid da Meta (chat#1067).
# O wamid é "wamid." + base64 de um protobuf curto; o último campo string é o id da mensagem no
# WhatsApp — o mesmo id que o WAHA usou no envio (comprovado no spike F0, 7/7). Leitura estrutural
# do protobuf, sem regex: tag 0x18 (campo 3, length-delimited curto) seguida do tamanho e dos bytes.
module WhatsappHybrid::Wamid
  PREFIX = 'wamid.'.freeze
  STRING_TAG = 0x18

  module_function

  def message_id(wamid)
    return if wamid.blank? || !wamid.start_with?(PREFIX)

    bytes = Base64.decode64(wamid.delete_prefix(PREFIX)).bytes
    strings(bytes).last
  rescue ArgumentError
    nil
  end

  def strings(bytes)
    found = []
    index = 0
    while index < bytes.length - 1
      if bytes[index] == STRING_TAG
        length = bytes[index + 1]
        chunk = bytes[index + 2, length]
        if chunk && chunk.length == length && printable?(chunk)
          found << chunk.pack('C*')
          index += 2 + length
          next
        end
      end
      index += 1
    end
    found
  end

  def printable?(chunk)
    chunk.all? { |byte| byte.between?(0x20, 0x7e) }
  end
end
