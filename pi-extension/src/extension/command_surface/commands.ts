import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

export interface CommandCompletion {
  value: string;
  label: string;
}

export interface RemotePiCommandSpec {
  readonly suffix: string;
  readonly description: string;
  readonly completionValues?: readonly string[];
  readonly complete?: (prefix: string) => Promise<CommandCompletion[]>;
  readonly run: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>;
}

export function registerRemotePiCommands(
  pi: ExtensionAPI,
  specs: readonly RemotePiCommandSpec[],
  rootRun: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>,
): void {
  pi.registerCommand("remote-pi", {
    description: "Connect (join local mesh + start relay), or run setup on first use",
    getArgumentCompletions: async (prefix) => completeRoot(prefix, specs),
    handler: async (args, ctx) => rootRun(args.trim(), ctx),
  });

  for (const spec of specs) {
    pi.registerCommand(`remote-pi ${spec.suffix}`, {
      description: spec.description,
      ...(spec.complete ? { getArgumentCompletions: spec.complete } : {}),
      handler: async (args, ctx) => spec.run(args.trim(), ctx),
    });
  }
}

async function completeRoot(
  prefix: string,
  specs: readonly RemotePiCommandSpec[],
): Promise<CommandCompletion[]> {
  const matchingSpec = specs.find(
    (spec) => prefix === spec.suffix || prefix.startsWith(`${spec.suffix} `),
  );
  if (matchingSpec?.complete) {
    const nestedPrefix = prefix === matchingSpec.suffix
      ? ""
      : prefix.slice(matchingSpec.suffix.length + 1);
    const completions = await matchingSpec.complete(nestedPrefix);
    return completions.map((completion) => ({
      value: `${matchingSpec.suffix} ${completion.value}`.trimEnd(),
      label: `${matchingSpec.suffix} ${completion.label}`.trimEnd(),
    }));
  }

  return specs
    .flatMap((spec) => spec.completionValues ?? [spec.suffix])
    .filter((suffix) => suffix.startsWith(prefix))
    .map((suffix) => ({ value: suffix, label: suffix }));
}
