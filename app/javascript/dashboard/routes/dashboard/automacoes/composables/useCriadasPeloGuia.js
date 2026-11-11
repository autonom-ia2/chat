import { ref } from 'vue';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';

// #859 — quais automações o Guia criou para esta pessoa, lidas do que ele fez
// (#855): cada passo guarda a ação ('POST automation_rules') e o id criado. Vale
// o mesmo prazo do desfazer; o que foi desfeito não conta.
const CRIAR_AUTOMACAO = 'POST automation_rules';

export const idsCriadosPeloGuia = execucoes =>
  new Set(
    (execucoes || [])
      .filter(execucao => !execucao.desfeita_em)
      .flatMap(execucao => execucao.passos || [])
      .filter(
        passo => passo.ok && passo.registro && passo.acao === CRIAR_AUTOMACAO
      )
      .map(passo => Number(passo.registro))
  );

export const passoCriouAutomacao = passo =>
  Boolean(passo?.ok && passo.registro && passo.acao === CRIAR_AUTOMACAO);

export const passoMexeuEmAutomacao = passo =>
  Boolean(passo?.ok && (passo.acao || '').includes('automation_rules'));

// #2889 — o motor novo (autonomia/automacoes). Os ids não se misturam com os de
// automation_rules: a mesma conta tem a regra 7 e a automação 7.
const CRIAR_NO_MOTOR = 'POST autonomia/automacoes';
const RECURSO_DO_MOTOR = 'autonomia/automacoes';

export const passoCriouNoMotor = passo =>
  Boolean(passo?.ok && passo.registro && passo.acao === CRIAR_NO_MOTOR);

export const passoMexeuNoMotor = passo =>
  Boolean(
    passo?.ok && (passo.acao || '').split(' ')[1]?.startsWith(RECURSO_DO_MOTOR)
  );

export function useCriadasPeloGuia() {
  const criadas = ref(new Set());

  // O selo é um detalhe: conta sem Guia responde 404 aqui, e a lista segue sem
  // selo nenhum.
  const carregarCriadas = async () => {
    try {
      const { data } = await AutonomiaGuideAPI.execucoes();
      criadas.value = idsCriadosPeloGuia(data?.execucoes);
    } catch {
      criadas.value = new Set();
    }
  };

  return { criadas, carregarCriadas };
}
