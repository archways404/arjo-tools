const PC_TYPE_MAP = {
  T14: "ThinkPad T14 Gen 6",
  L16: "ThinkPad L16 Gen 2",
};

export function resolvePcType(type) {
  const resolved = PC_TYPE_MAP[type];
  if (!resolved) throw new Error(`Unknown PC type: "${type}"`);
  return resolved;
}
