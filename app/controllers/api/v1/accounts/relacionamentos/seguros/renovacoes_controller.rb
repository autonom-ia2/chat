# "Ajustar renovações" (E5, #2898): ler e guardar onde ficam as renovações da conta. Ler pede o mesmo que ver a carteira
# (ver contatos). Guardar muda uma escolha da conta inteira: pede `contact_manage` (administrador, ou função com editar
# contatos) e só aceita funil que quem pede enxerga no quadro. Quem só lê recebe `semPermissao`, e a tela não oferece
# o salvar.
class Api::V1::Accounts::Relacionamentos::Seguros::RenovacoesController < Api::V1::Accounts::Relacionamentos::CarteiraController
  CAMPOS = ::Carteira::Renovacao::SalvarAjustes::CAMPOS

  before_action :sem_parametros, only: :show
  before_action :poder_mudar, only: :update

  def show
    render json: ::Carteira::Renovacao::Ajustes.new(Current.account, funis: funis, pode_mudar: pode_mudar?).call
  end

  def update
    config = ::Carteira::Renovacao::SalvarAjustes.new(Current.account, corpo(*CAMPOS), user: Current.user, funis: funis).call
    render json: ::Carteira::Renovacao::Ajustes.guardados(config)
  end

  private

  # Os funis que a pessoa vê no quadro, como no "Criar cards" da lista. Com o CRM desligado não há funil.
  def funis
    authorize ::Crm::Pipeline, :index?
    ::Crm::Config.enabled? ? policy_scope(::Crm::Pipeline) : ::Crm::Pipeline.none
  end

  def pode_mudar?
    Current.account_user&.permission_granted?('contact_manage') || false
  end

  def poder_mudar
    raise Pundit::NotAuthorizedError unless pode_mudar?
  end
end
