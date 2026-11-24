# Cria ou muda o cartão fidelidade da conta (#3100, MontarPrograma) e o pausa ou liga de novo (PainelDoCartao).
#
# - Criar: o cartão nasce ligado, e a compra conta daí em diante (decisão D2 do Rodrigo, 23/11: compra de antes não
#   conta). "A cada" chega em reais inteiros (`a_cada`, como a tela fala) e fica em centavos.
# - Mudar as regras não mexe em quem já tem carimbos nem em quando eles vencem: vale para as próximas compras.
# - Pausar: as compras param de dar carimbos. Ligar de novo recomeça a contagem agora (`ligado_em`): as compras da pausa
#   não contam. Os carimbos de cada pessoa ficam guardados nos dois casos.
#
# Devolve o cartão; com regra errada, o cartão com os erros (`errors`), sem gravar.
class Fidelidade::GravarPrograma
  CAMPOS = %w[tipo a_cada ganha meta premio validade_meses].freeze

  def initialize(account, user)
    @account = account
    @user = user
  end

  def gravar(dados)
    programa = Fidelidade::Programa.da_conta(@account) || novo
    programa.assign_attributes(atributos(dados.to_h.slice(*CAMPOS)))
    programa.updated_by = @user
    programa.save
    programa
  end

  def ligar(ligado)
    programa = Fidelidade::Programa.da_conta(@account)
    return unless programa
    return programa if programa.ligado == ligado

    programa.update!(ligado: ligado, ligado_em: (ligado ? Time.current : programa.ligado_em), updated_by: @user)
    programa
  end

  private

  def novo
    Fidelidade::Programa.new(account: @account, created_by: @user, ligado: true, ligado_em: Time.current,
                             moeda: Fidelidade::Programa::MOEDA)
  end

  def atributos(dados)
    return dados unless dados.key?('a_cada')

    reais = Integer(dados['a_cada'].to_s, 10, exception: false)
    dados.except('a_cada').merge('a_cada_centavos' => reais && (reais * Fidelidade::Programa::CENTAVOS))
  end
end
