import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const templateRoot = new URL("../", import.meta.url);

test("build emits a Vercel-compatible Nitro application", async () => {
  await access(new URL("../.output/server/index.mjs", import.meta.url));
  await access(new URL("../.output/public/og.png", import.meta.url));
});

test("keeps student identities anonymous and Supabase flows present", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /"use client"/);
  assert.match(page, /function Apply/);
  assert.match(page, /function Manage/);
  assert.match(page, /25명/);
  assert.doesNotMatch(page, /김지우|박서준|이민서/);
  assert.match(layout, /export const metadata/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.match(page, /submit_role_applications/);
  assert.match(page, /teacher_lottery/);
  assert.match(page, /teacher_reset/);
  assert.match(page, /teacher_change_password/);
  assert.match(page, /teacher_record_class_points/);
  assert.match(page, /teacher_record_reading_bonus/);
  assert.match(page, /PAYROLL_RULES/);
  assert.match(page, /teacher_run_payroll/);
  assert.match(page, /teacher_update_role_salary/);
  assert.match(page, /PublicLedger/);
  assert.match(page, /publicLedger/);
  assert.match(page, /ledger-pagination/);
  assert.match(page, /PayrollAdjustments/);
  assert.match(page, /모두의 역할/);
  assert.match(page, /CSV 내려받기/);
  assert.doesNotMatch(page, /localhost:3001/);

  await assert.rejects(
    access(new URL("app/_sites-preview/SkeletonPreview.tsx", templateRoot)),
  );
});
