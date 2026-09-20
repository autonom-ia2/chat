import { ref, computed } from 'vue';
import OnboardingProgressAPI from 'dashboard/api/onboardingProgress';

// O passo 4 (funil) fecha o essencial: com ele pronto a conta recebe, responde
// e organiza. Daí em diante a tela deixa de tomar a home.
export const PASSO_ESSENCIAL_FINAL = 'funil';

export function useOnboardingTrail() {
  const passos = ref([]);
  const carregando = ref(false);
  const erro = ref(false);

  const carregar = async () => {
    carregando.value = true;
    erro.value = false;
    try {
      const { data } = await OnboardingProgressAPI.get();
      passos.value = data.passos || [];
    } catch {
      erro.value = true;
      passos.value = [];
    } finally {
      carregando.value = false;
    }
  };

  const feitos = computed(
    () => passos.value.filter(passo => passo.status === 'feito').length
  );

  const resolvidos = computed(
    () => passos.value.filter(passo => passo.status !== 'pendente').length
  );

  const total = computed(() => passos.value.length);

  const percentual = computed(() =>
    total.value ? Math.round((resolvidos.value / total.value) * 100) : 0
  );

  // Em foco: o primeiro passo que ainda falta, na ordem da trilha.
  const passoAtual = computed(
    () => passos.value.find(passo => passo.status === 'pendente') || null
  );

  const ordemDoEssencial = computed(() => {
    const passo = passos.value.find(item => item.id === PASSO_ESSENCIAL_FINAL);
    return passo ? passo.ordem : Infinity;
  });

  const essencialConcluido = computed(() => {
    const essenciais = passos.value.filter(
      passo => passo.ordem <= ordemDoEssencial.value
    );
    return (
      essenciais.length > 0 &&
      essenciais.every(passo => passo.status !== 'pendente')
    );
  });

  const pular = async passoId => {
    await OnboardingProgressAPI.skip(passoId);
    await carregar();
  };

  const retomar = async passoId => {
    await OnboardingProgressAPI.resume(passoId);
    await carregar();
  };

  return {
    passos,
    carregando,
    erro,
    feitos,
    resolvidos,
    total,
    percentual,
    passoAtual,
    essencialConcluido,
    carregar,
    pular,
    retomar,
  };
}
