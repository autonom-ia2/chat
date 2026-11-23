# "O cliente mostrou um cupom?" (#3100, ConferirCupom): o código digitado vale, já foi usado, venceu ou não existe.
#
# O código é coisa de máquina: compara na forma limpa (Fidelidade::CupomCodigo.limpo: maiúsculas, sem espaço e sem o
# hífen), então "volta 7kd2" e "VOLTA7KD2" acham "VOLTA-7KD2". Só conta código que chegou à pessoa (`enviado_em`): o que
# ficou sorteado num envio que não saiu responde "não existe", como um código inventado. O nome do cliente só vai para
# quem pode ver o contato (`ve_contato`); o resto da resposta não diz nada da pessoa.
#
# Contra quem tenta adivinhar códigos: limite de tentativas por pessoa (config/initializers/rack_attack.rb) e o
# alfabeto de 31 símbolos com 4 a 6 caracteres (Fidelidade::CodigoDoCupom).
class Fidelidade::ConferirCupom
  NAO_EXISTE = 'nao_existe'.freeze

  # `ve_contato`: ->(contato) { pode ver? }, a pergunta da policy de quem confere.
  def initialize(account, ve_contato:, agora: Time.current)
    @account = account
    @ve_contato = ve_contato
    @agora = agora
  end

  def call(digitado)
    codigo = Fidelidade::CupomCodigo.limpo(digitado)
    achado = achar(codigo)
    return { estado: NAO_EXISTE, codigo: codigo } unless achado

    resposta(achado)
  end

  private

  def achar(codigo)
    return if codigo.empty? || codigo.length > Fidelidade::CupomCodigo::CODIGO_MAXIMO

    Fidelidade::CupomCodigo.where(account_id: @account.id).where.not(enviado_em: nil).preload(:cupom, :contact).find_by(codigo_limpo: codigo)
  end

  def resposta(achado)
    ve = @ve_contato.call(achado.contact)
    { id: achado.id, codigo: achado.codigo, estado: achado.estado(@agora), oferta: achado.cupom.oferta, moeda: achado.cupom.moeda,
      cliente: (achado.contact.name if ve), contato_id: (achado.contact_id if ve), vale_ate: achado.vale_ate&.to_i,
      usado_em: achado.usado_em&.to_i }
  end
end
