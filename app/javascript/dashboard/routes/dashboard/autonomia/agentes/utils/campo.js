// #3211 — o campo de texto dos formulários do agente contratado (dados da corretora e acesso à seguradora): a mesma
// aparência e o mesmo anel de erro nos dois. A mensagem de erro embaixo do campo é o CampoErro.
export const CLASSE_DO_CAMPO =
  'w-full px-3 text-base rounded-xl min-h-11 !bg-n-solid-1 ring-inset border-0 !mb-0 text-n-slate-12 disabled:opacity-60';

// Anel vermelho mais grosso no campo com erro; o cinza de sempre no resto.
export const anelDoCampo = invalido =>
  invalido ? 'ring-2 ring-n-ruby-9' : 'ring-1 ring-n-slate-7';
