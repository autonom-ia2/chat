# IA cuida dos comentários (#2212): as três ações da IA num comentário — o privado (Private Reply: a mensagem que
# responde a um comentário, a única que a Meta deixa mandar a quem nunca escreveu), a resposta pública e o esconder.
# Cada rede tem o seu adaptador, que usa os serviços do #2196 e do #2197 sempre que eles existem:
# - Instagram (Rede::Instagram): o privado pelo Crm::MetaAds::InstagramPrivateReply, que reivindica, confere a janela
#   de 7 dias, envia e abre a conversa; a resposta e o esconder pelo Instagram::CommentsClient;
# - Facebook (Rede::Facebook): o privado pelo Messenger é nosso (Rede::Pagina, token da caixa); a leitura, a resposta e
#   o esconder pelo Rede::ComentariosDaPagina, também com o token da caixa (#2587), que grava a ação.
#
# `privado_disponivel?` diz se a rede deixa a IA mandar o privado: no Instagram, sempre; no Facebook, só na Página cujo
# login tem a `pages_messaging` concedida pela Meta (privado_liberado?, Rede::PermissaoDoMessenger, #2307).
# Todo adaptador responde `privado(care)` com um Envio (ok, conversation, erro) e `responder(texto)` e `esconder` com
# true ou false. Nada levanta para o job: a recusa da Meta é um resultado.
#
# E `ler`: o texto e o nome de quem comentou, lidos na Meta na hora, porque o evento leva só ids (#2327). Devolve
# `{ text:, from_name:, from_id: }`, ou nil quando não dá para ler (comentário apagado ou de outro post, Página de outra
# conta): esse não volta. Meta fora do ar levanta Indisponivel, e o CuidarJob tenta de novo, com teto.
# E `legenda` (#2424): o texto do post, para a IA saber do que o comentário fala; nil quando não dá para ler.
# E `ler_pai` (#2454): o texto do comentário que uma resposta responde, lido na Meta pelo id, como o `ler`; nil no
# comentário de primeiro nível ou quando não dá para ler o de cima.
# E `imagens` (#2454): os endereços das imagens do post, para a leitura da foto (Foto); [] quando não dá para ler.
module Crm::MetaAds::ComentariosIa::Rede
  # `codigo`, `subcodigo` e `http`: os da Meta na recusa (#2454), para decidir e gravar sem ler a mensagem dela.
  Envio = Struct.new(:ok, :recipient_id, :message_id, :conversation, :erro, :talvez_entregue, :codigo, :subcodigo, :http,
                     keyword_init: true)
  # O privado já tinha saído (pela pessoa, na tela do #2196, ou por outro job): nada a fazer, nem falha a mostrar.
  JA_FEITO = 'private_reply_done'.freeze
  # A Meta não respondeu à leitura do comentário (rede, 5xx, limite).
  class Indisponivel < StandardError; end

  module_function

  def para(inbox, comentario)
    case inbox.channel
    when Channel::Instagram then Instagram.new(inbox, comentario)
    when Channel::FacebookPage then Facebook.new(inbox, comentario)
    end
  end

  # Se a IA pode mandar o privado nesta rede, por esta caixa: o motor (Rede#privado_disponivel?), a tela do cuidado
  # (Painel, `private_available`) e o teste em Agentes (NoAgentes) perguntam aqui. No Facebook, o que vale é o que a
  # Meta concedeu ao login da Página (#2307): quem tem papel no app usa já; o cliente, quando a Meta aprovar a
  # `pages_messaging`. Sem a caixa da Página, não sai.
  def privado_liberado?(network, inbox)
    case network
    when 'instagram' then true
    when 'facebook' then inbox.present? && PermissaoDoMessenger.new(inbox.channel).liberada?
    else false
    end
  end

  # O mesmo, pela caixa da rede na Fonte (Fonte#redes): a tela do cuidado e o teste em Agentes.
  def privado_na_fonte?(account, network, fonte)
    return privado_liberado?(network, nil) unless network == 'facebook'

    inbox_id = fonte.redes.dig(network, :inbox_id)
    privado_liberado?(network, inbox_id && Inbox.find_by(id: inbox_id, account_id: account.id))
  end

  # A recusa do privado por falta de permissão (#2307), pela tabela de erros da Graph: (#200–299) e o (#10) sem
  # subcódigo, "a permissão não foi concedida ou foi removida". O (#10) com subcódigo é outra coisa (fora da janela de
  # 7 dias, já respondido). O Painel diz o porquê só daquele comentário.
  def sem_permissao?(codigo, subcodigo)
    return false if codigo.nil?

    codigo.between?(200, 299) || (codigo == 10 && subcodigo.nil?)
  end
end
