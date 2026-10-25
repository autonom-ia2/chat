# Exclusão do usuário (#2135): antes do DELETE de users, o fork solta o que guarda da pessoa (Autonomia::ExclusaoDoUsuario).
# Registro aditivo no modelo e no job do upstream (sem editar app/models/user.rb).
# - A conferência roda primeiro (`prepend: true`): se a pessoa não pode sair, nada é feito, nem os dependentes do upstream.
# - As escritas rodam depois dos dependentes do upstream (conversas, mensagens): mesma ordem de travas do
#   Agents::DestroyJob, que pode estar rodando ao mesmo tempo para a mesma pessoa.
Rails.application.config.to_prepare do
  User.before_destroy(prepend: true) do |user|
    throw(:abort) unless Autonomia::ExclusaoDoUsuario.new(user).pode_sair?
  end
  User.before_destroy { |user| Autonomia::ExclusaoDoUsuario.new(user).soltar }
  DeleteObjectJob.prepend(Autonomia::ExclusaoDoUsuarioNoJob)
end
