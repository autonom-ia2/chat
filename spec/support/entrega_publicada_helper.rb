# A MENSAGEM QUE O PUBLICADOR CRIA para uma entrega, fabricada (rodada 3 da entrega 8).
#
# Desde a rodada 3, a ferramenta pergunta ao BANCO o que já chegou ao cliente: a mensagem carimbada
# com o token da entrega (`ToolRun#delivery_token`, `EntregaPublicada`). O caminho real — publicador,
# download, anexo — está nos exemplos «pelo job» e em `async_publisher_spec`; aqui o que importa é o
# FATO de a mensagem existir, com o mesmo carimbo que o publicador põe.
module EntregaPublicadaHelper
  # `entrega` é o texto ou a forma serializada de uma entrega de arquivo, como sai do `Progress`.
  def publicar_entrega!(run, conversation, entrega)
    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
    identidade = arquivo ? arquivo.identidade : entrega.to_s
    Message.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                    conversation: conversation, message_type: :outgoing,
                    sender: create(:agent_bot, account: conversation.account), content: 'entrega publicada',
                    content_attributes: { ::Autonomia::Agents::Tools::EntregaPublicada::CHAVE => run.delivery_token(identidade) })
  end
end

RSpec.configure do |config|
  config.include EntregaPublicadaHelper
end
