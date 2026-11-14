# "Ajustar renovações" (E5, #2898): ler e guardar onde ficam as renovações da conta. Ler pede o mesmo que ver a carteira
# (ver contatos). Guardar muda uma escolha da conta inteira e diz em que funil o CRM recebe os cards: pede editar
# contatos (`contact_manage`) e a chave de funis, uma das duas (`crm_manage_pipelines` ou `crm_admin`, a mesma régua
# da Automação: Autonomia::Automacao::RegraDoFunil.chave?). Só aceita funil que quem pede enxerga no quadro. Quem só lê
# recebe `semPermissao`, e a tela não oferece o salvar.
class Api::V1::Accounts::Relacionamentos::Seguros::RenovacoesController < Api::V1::Accounts::Relacionamentos::CarteiraController
  CAMPOS = ::Carteira::Renovacao::SalvarAjustes::CAMPOS
  EDITAR_CONTATOS = 'contact_manage'.freeze

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

  # Os funis que a pessoa vê no quadro, como no "Criar cards" da lista. Com o CRM desligado, ou para quem a função não
  # dá o CRM, não há funil para escolher.
  def funis
    return ::Crm::Pipeline.none unless ::Crm::Config.enabled? && policy(::Crm::Pipeline).index?

    policy_scope(::Crm::Pipeline)
  end

  def pode_mudar?
    conta = Current.account_user
    conta.present? && conta.permission_granted?(EDITAR_CONTATOS) && ::Autonomia::Automacao::RegraDoFunil.chave?(conta)
  end

  def poder_mudar
    raise Pundit::NotAuthorizedError unless pode_mudar?
  end
end
