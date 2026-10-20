// Keep the Flow property as a delimited string, while allowing literal delimiters.
function splitUnescaped(value, separators) {
  const parts = [];
  let part = "";
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (character === "\\" && index + 1 < value.length) {
      const next = value[index + 1];
      if (separators.includes(next) || next === "\\" || next === ":") {
        part += character + next;
        index += 1;
        continue;
      }
    }
    if (separators.includes(character)) {
      parts.push(part);
      part = "";
    } else {
      part += character;
    }
  }
  parts.push(part);
  return parts;
}

function unescapeValue(value) {
  return value.replace(/\\([\\,;:])/g, "$1");
}

export function parseDefaultValuePairs(serialized) {
  const values = {};
  if (!serialized) return values;

  // Legacy configurations choose one separator for the entire property.
  const separator = splitUnescaped(serialized, ";").length > 1 ? ";" : ",";
  splitUnescaped(serialized, separator).forEach((pair) => {
    const parts = splitUnescaped(pair, ":");
    if (parts.length < 2) return;
    const field = unescapeValue(parts.shift()).trim();
    if (field) values[field] = unescapeValue(parts.join(":")).trim();
  });
  return values;
}

export function formatDefaultValuePairs(values) {
  return Object.entries(values)
    .filter(([, value]) => value !== null && value !== undefined && value !== "")
    .map(([field, value]) => {
      const escaped = String(value).replace(/([\\,;:])/g, "\\$1");
      return `${field}:${escaped}`;
    })
    .join(",");
}
