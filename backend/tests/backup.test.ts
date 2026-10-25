import { afterEach, expect, it } from "vitest";
import {
  mkdtempSync,
  mkdirSync,
  copyFileSync,
  writeFileSync,
  readdirSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const folders: string[] = [];
afterEach(() => {
  for (const folder of folders.splice(0))
    rmSync(folder, { recursive: true, force: true });
});
function runBackup(dumpCommand: string, copyCommand = 'test -s "$1"') {
  const folder = mkdtempSync(join(tmpdir(), "repick-backup-test-"));
  folders.push(folder);
  const bin = join(folder, "bin");
  mkdirSync(bin);
  copyFileSync(
    new URL("../../infra/backup.sh", import.meta.url),
    join(folder, "backup.sh"),
  );
  writeFileSync(join(bin, "docker"), `#!/bin/sh\n${dumpCommand}\n`, {
    mode: 0o700,
  });
  writeFileSync(join(bin, "scp"), `#!/bin/sh\n${copyCommand}\n`, {
    mode: 0o700,
  });
  const result = spawnSync("sh", [join(folder, "backup.sh")], {
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH ?? "/usr/bin:/bin"}`,
      BACKUP_REMOTE: "test-only:/unused",
    },
  });
  return { folder, result };
}
it("writes a complete dump and copies it before retaining it", () => {
  const { folder, result } = runBackup("printf 'test-dump'");
  expect(result.status).toBe(0);
  const files = readdirSync(join(folder, "backups"));
  expect(files).toHaveLength(1);
  expect(files[0]).toMatch(/^repick-.*\.dump$/);
  expect(readFileSync(join(folder, "backups", files[0] ?? ""), "utf8")).toBe(
    "test-dump",
  );
});
it("cleans a partial dump after pg_dump fails", () => {
  const { folder, result } = runBackup("printf 'partial'; exit 1");
  expect(result.status).not.toBe(0);
  expect(readdirSync(join(folder, "backups"))).toEqual([]);
});
it("preserves the local dump and reports an off-host copy failure", () => {
  const { folder, result } = runBackup("printf 'test-dump'", "exit 1");
  expect(result.status).not.toBe(0);
  expect(readdirSync(join(folder, "backups"))).toHaveLength(1);
});
