// The name an imported model gets in "Meus modelos": its own title, or "Title (2)", "Title (3)"...
// when the account already has a model with that name (the server refuses the same name, ignoring
// case).
export const uniqueName = (base, names = []) => {
  const taken = new Set(names.map(name => name.trim().toLocaleLowerCase()));
  const clean = base.trim();
  if (!taken.has(clean.toLocaleLowerCase())) return clean;
  let copy = 2;
  while (taken.has(`${clean} (${copy})`.toLocaleLowerCase())) copy += 1;
  return `${clean} (${copy})`;
};
