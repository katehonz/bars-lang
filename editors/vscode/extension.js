// Bars VS Code extension — syntax (package.json contributes) + Language Client for `bars lsp`.
"use strict";

const vscode = require("vscode");
const {
  LanguageClient,
  TransportKind,
  RevealOutputChannelOn,
} = require("vscode-languageclient/node");

/** @type {import('vscode-languageclient/node').LanguageClient | undefined} */
let client;

/**
 * @param {import('vscode').ExtensionContext} context
 */
async function activate(context) {
  const output = vscode.window.createOutputChannel("Bars Language Server");
  context.subscriptions.push(output);

  /**
   * @returns {import('vscode').WorkspaceConfiguration}
   */
  function cfg() {
    return vscode.workspace.getConfiguration("bars");
  }

  async function startClient() {
    if (client) {
      try {
        await client.stop();
      } catch (_) {
        /* ignore */
      }
      client = undefined;
    }

    if (cfg().get("lsp.enabled") === false) {
      output.appendLine("Bars LSP disabled (bars.lsp.enabled = false).");
      return;
    }

    const serverPath = cfg().get("lsp.path") || "bars";
    const trace = cfg().get("lsp.trace") || "off";

    const serverOptions = {
      run: {
        command: serverPath,
        args: ["lsp"],
        transport: TransportKind.stdio,
      },
      debug: {
        command: serverPath,
        args: ["lsp"],
        transport: TransportKind.stdio,
      },
    };

    const clientOptions = {
      documentSelector: [
        { scheme: "file", language: "bars" },
        { scheme: "untitled", language: "bars" },
      ],
      synchronize: {
        fileEvents: vscode.workspace.createFileSystemWatcher("**/*.brs"),
      },
      outputChannel: output,
      revealOutputChannelOn: RevealOutputChannelOn.Error,
      traceOutputChannel: output,
    };

    client = new LanguageClient(
      "barsLsp",
      "Bars Language Server",
      serverOptions,
      clientOptions
    );

    try {
      if (typeof client.setTrace === "function") {
        client.setTrace(trace);
      }
    } catch (_) {
      /* ignore */
    }

    try {
      await client.start();
      output.appendLine(`Bars LSP started: \`${serverPath} lsp\``);
    } catch (err) {
      const msg = err && err.message ? err.message : String(err);
      output.appendLine(`Failed to start Bars LSP: ${msg}`);
      vscode.window.showWarningMessage(
        `Bars LSP failed to start (\`${serverPath} lsp\`). ` +
          `Run \`make host\` and set bars.lsp.path to the absolute path of target/release/bars.`
      );
      client = undefined;
    }
  }

  context.subscriptions.push(
    vscode.commands.registerCommand("bars.restartServer", async () => {
      output.appendLine("Restarting Bars language server…");
      await startClient();
    })
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (e.affectsConfiguration("bars.lsp")) {
        await startClient();
      }
    })
  );

  await startClient();
}

async function deactivate() {
  if (!client) {
    return undefined;
  }
  return client.stop();
}

module.exports = { activate, deactivate };
