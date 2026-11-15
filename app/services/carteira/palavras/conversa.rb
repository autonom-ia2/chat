# Por onde sai "seu seguro em palavras simples" (E6.6, #2899): a conversa mais recente do contato do seguro em que quem
# pede pode escrever (Conversations::PermissionFilterService, a regra de caixa, funil e função de mandar mensagem; a de
# só ler não basta). O envio é a mesma mensagem de saída que a pessoa mandaria pela caixa da conversa (decisão P2).
#
# `envio` diz à tela o que fazer, sem botão desligado:
# - `conversa`: dá para mandar agora;
# - `fora_da_janela`: a conversa existe, mas o canal não deixa mandar texto livre agora (a janela de 24 h do WhatsApp
#   oficial, a mesma regra da caixa da conversa: Conversation#can_reply?). A tela oferece copiar o texto; quando o
#   cliente escrever de novo, dá para mandar;
# - `sem_conversa`: não há conversa com o contato que a pessoa possa usar. A tela oferece copiar o texto.
class Carteira::Palavras::Conversa
  CONVERSA = 'conversa'.freeze
  FORA_DA_JANELA = 'fora_da_janela'.freeze
  SEM_CONVERSA = 'sem_conversa'.freeze

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def conversa
    return @conversa if defined?(@conversa)

    account = @apolice.account
    daquele_contato = account.conversations.where(contact_id: @apolice.contact_id)
    @conversa = Conversations::PermissionFilterService.new(daquele_contato, @user, account).perform
                                                      .reorder(last_activity_at: :desc, id: :desc).first
  end

  def envio
    return SEM_CONVERSA unless conversa

    conversa.can_reply? ? CONVERSA : FORA_DA_JANELA
  end

  # O que a tela recebe: o texto guardado, quando saiu, a frase do fim e por onde sai.
  def para_a_tela
    { texto: @apolice.palavras_texto, enviadoEm: @apolice.palavras_enviadas_em&.to_i, vale: Carteira::Palavras.vale(@apolice.account),
      envio: envio }
  end
end
