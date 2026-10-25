# Exclusão do usuário (#2135): antes do DELETE de users, o fork solta o que guarda da pessoa (Autonomia::ExclusaoDoUsuario).
# Registro aditivo no modelo do upstream (sem editar app/models/user.rb). Sem `prepend`: roda depois dos dependentes do
# upstream (conversas, mensagens), na mesma ordem de travas do Agents::DestroyJob, que pode estar rodando ao mesmo tempo
# para a mesma pessoa.
Rails.application.config.to_prepare do
  User.before_destroy { |user| Autonomia::ExclusaoDoUsuario.new(user).soltar }
end
