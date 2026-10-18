// Básico de Primeiros passos (decisão do Rodrigo, 18/10/2026): quando todos os passos OBRIGATÓRIOS das etapas
// "ligar" e "organizar" estão feitos, o item sai do menu e vira um cartão em Configurações. Obrigatório é o que a
// trilha (config/onboarding/trilha.yml) não marca como `pulavel` — hoje, criar o agente de IA e convidar a equipe
// são opcionais. Se um passo básico voltar a ficar pendente (ex.: canal desconectado), o item volta ao menu.
export const ETAPAS_BASICAS = ['ligar', 'organizar'];

export const basicoDaTrilhaConcluido = (passos = []) => {
  const obrigatorios = passos.filter(
    passo => ETAPAS_BASICAS.includes(passo.etapa) && !passo.pulavel
  );
  return (
    obrigatorios.length > 0 &&
    obrigatorios.every(passo => passo.status === 'feito')
  );
};

export const passosPendentes = (passos = []) =>
  passos.filter(passo => passo.status === 'pendente').length;
