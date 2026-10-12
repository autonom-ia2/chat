# Texto livre no WhatsApp (#1354): a mensagem que sai numa conversa aberta (janela de 24 h) ou por número não
# oficial, sem aprovação da Meta. Primeiro consumidor: os avisos do agendamento. Não há categoria neste canal: o que
# a IA disser em `categoria_prevista` é descartado. A conferência é a comum (chaves permitidas e obrigatórias, campo
# nas pontas, tamanho e texto malformado) mais uma do canal: endereço escrito à mão fora dos campos (o link de
# verdade só vem pelo campo) descarta a opção.
class Ai::Redacao::Canais::WhatsappTexto < Ai::Redacao::Canais::Base
  ENDERECO = %w[:// www.].freeze

  def self.nome
    'whatsapp_texto'
  end

  def self.normalizar_opcao(opcao)
    super.merge(categoria_prevista: nil)
  end

  def self.problema_do_canal(opcao, **)
    fixo = Ai::Redacao::Chaves.partes(opcao['texto']).reject(&:chave?).map(&:valor).join(' ').downcase
    :link_inventado if ENDERECO.any? { |marca| fixo.include?(marca) } || fixo.split.any? { |palavra| dominio?(palavra) }
  end

  # "agenda.exemplo.com", "bit.ly/abc": ponto entre duas letras numa palavra. Fim de frase ("hoje.") não conta.
  def self.dominio?(palavra)
    letras = palavra.chars
    letras.each_index.any? { |i| letras[i] == '.' && i.positive? && letra?(letras[i - 1]) && letra?(letras[i + 1]) }
  end

  def self.letra?(char)
    char.present? && char.upcase != char.downcase
  end
  private_class_method :problema_do_canal, :dominio?, :letra?
end
